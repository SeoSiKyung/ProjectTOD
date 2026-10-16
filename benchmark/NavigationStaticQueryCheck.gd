extends Node

# 검증 전용: 수정 전 판정 코드와 비교한다. 일반 실행에서는 사용하지 않는다.
const REFERENCE = preload("res://benchmark/NavigationStaticQueryReference.gd")
const MAP_PATH: String = "res://maps/2_navigation.res"
const EXPECTED_MAP_SHA256: String = "b461aa28adbe730651c397058159e7783a02982ea29d8eae6516df621d630a62"
const OBSERVED_PAIRS: Array = [
	[330.0, 330.0, 3040.0, 3120.0],
	[370.0, 294.0, 410.0, 366.0],
	[370.0, 390.0, 368.0, 388.0],
	[370.0, 390.0, 368.0, 392.0],
	[370.0, 390.0, 370.0, 294.0],
	[370.0, 390.0, 370.0, 344.0],
	[370.0, 390.0, 372.0, 392.0],
	[370.0, 390.0, 376.0, 388.0],
	[378.0, 398.0, 378.0, 494.0],
	[378.0, 398.0, 410.0, 430.0],
	[378.0, 398.0, 474.0, 398.0],
	[390.0, 398.0, 390.0, 302.0],
	[390.0, 398.0, 410.0, 366.0],
	[390.0, 430.0, 388.0, 428.0],
	[390.0, 430.0, 392.0, 432.0],
	[390.0, 430.0, 392.0, 436.0],
	[390.0, 430.0, 396.0, 428.0],
	[390.0, 430.0, 3020.0, 3144.0],
	[392.222229003906, 334.0, 488.222229003906, 334.0],
	[410.0, 360.0, 408.0, 356.0],
	[410.0, 360.0, 416.0, 356.0],
	[410.0, 390.0, 408.0, 392.0],
	[410.0, 390.0, 408.0, 396.0],
	[410.0, 390.0, 410.0, 344.0],
	[410.0, 390.0, 410.0, 430.0],
	[410.0, 390.0, 412.0, 388.0],
	[410.0, 390.0, 416.0, 388.0],
	[410.0, 390.0, 3040.0, 3104.0],
	[410.0, 430.0, 412.0, 432.0],
	[422.0, 404.399993896484, 326.0, 404.399993896484],
	[422.0, 404.399993896484, 410.0, 366.0],
	[427.777770996094, 334.0, 427.777770996094, 430.0],
	[430.0, 430.0, 410.0, 430.0],
	[430.0, 430.0, 428.0, 432.0],
	[430.0, 430.0, 430.0, 384.0],
	[430.0, 430.0, 436.0, 436.0],
	[430.0, 430.0, 3060.0, 3144.0],
	[442.0, 398.0, 346.0, 398.0],
	[442.0, 398.0, 410.0, 430.0],
	[450.0, 390.0, 410.0, 366.0],
	[450.0, 390.0, 448.0, 388.0],
	[450.0, 390.0, 448.0, 392.0],
	[450.0, 390.0, 452.0, 388.0],
	[450.0, 390.0, 456.0, 392.0],
	[450.0, 390.0, 3080.0, 3104.0],
	[490.0, 374.0, 3040.0, 3120.0],
	[510.0, 390.0, 2634.0, 2726.0],
	[510.0, 390.0, 3040.0, 3120.0],
	[570.0, 342.0, 3040.0, 3120.0],
	[2002.0, 2094.0, 3040.0, 3120.0],
]

var _compared: int = 0
var _mismatchCount: int = 0
var _mismatches: Array[Dictionary] = []
var _metrics: NavigationProfileMetrics = NavigationProfileMetrics.new()


func _ready() -> void:
	_metrics.captureStaticQueryDetails = true
	if FileAccess.get_sha256(MAP_PATH) != EXPECTED_MAP_SHA256:
		push_error("Static query check: map hash differs from the measured baseline.")
		return
	var data: NavigationData = load(MAP_PATH) as NavigationData
	var optimized: NavigationStaticQuery = NavigationStaticQuery.new(data)
	var reference = REFERENCE.new(data)
	for pair: Array in OBSERVED_PAIRS:
		var start: Vector2 = Vector2(float(pair[0]), float(pair[1]))
		var end: Vector2 = Vector2(float(pair[2]), float(pair[3]))
		for halfSize: int in [0, 16, 32]:
			_Compare(optimized, reference, start, end, halfSize, "observed")
			_Compare(optimized, reference, end, start, halfSize, "observed_reverse")
		await get_tree().process_frame

	# 실제 맵의 배치 가능 지점으로 고정 시드의 양방향 선분을 만든다.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 104365073
	var points: Array[Vector2] = []
	var rect: Rect2 = data.GetWorldRect()
	for attempt: int in range(4096):
		var point: Vector2 = rect.position + Vector2(
			rng.randf_range(0.0, rect.size.x),
			rng.randf_range(0.0, rect.size.y),
		)
		if optimized.CanPlace(point, 16):
			points.append(point)
		if points.size() >= 64:
			break
	if points.size() < 2:
		push_error("Static query check: not enough placeable map samples.")
		return
	for index: int in range(256):
		var start: Vector2 = points[rng.randi_range(0, points.size() - 1)]
		var end: Vector2 = points[rng.randi_range(0, points.size() - 1)]
		for halfSize: int in [0, 16, 32]:
			_Compare(optimized, reference, start, end, halfSize, "map_seeded")
			_Compare(optimized, reference, end, start, halfSize, "map_seeded_reverse")
		if index % 16 == 0:
			await get_tree().process_frame

	# 단일 장애물의 경계/모서리/수평/수직/미소 이동 및 음수 원점을 비교한다.
	for origin: Vector2 in [Vector2.ZERO, Vector2(-128.5, 64.25), Vector2(10000.25, -10000.5)]:
		for cellSize: int in [4, 8]:
			for slop: float in [0.0, 1.0]:
				_RunFixture(origin, cellSize, slop)
				await get_tree().process_frame
	var report: Dictionary = {
		"schema": "static-row-pruning-check-v1",
		"timestamp": Time.get_datetime_string_from_system(),
		"engine": Engine.get_version_info(),
		"navigation_data_sha256": FileAccess.get_sha256(MAP_PATH),
		"optimized_script_sha256": FileAccess.get_sha256(
			"res://scripts/navigation/NavigationStaticQuery.gd"
		),
		"reference_script_sha256": FileAccess.get_sha256(
			"res://benchmark/NavigationStaticQueryReference.gd"
		),
		"seed": 104365073,
		"placeable_map_points": points.size(),
		"compared_queries": _compared,
		"mismatch_count": _mismatchCount,
		"passed": _mismatchCount == 0,
		"first_mismatches": _mismatches,
		"notes": [
			"Frozen pre-optimization query versus optimized query with details OFF and ON. No movement or pathfinding is run.",
			"Observed worst-query coordinates, fixed-seed real-map samples and small geometry fixtures. Sample agreement does not prove all possible inputs.",
			"These ordered reference comparisons are correctness checks, NOT before/after performance measurements. Use Movement Run All for performance and completion.",
		],
	}
	var directory: String = "user://navigation_benchmark_reports"
	var error: Error = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(directory)
	)
	if error != OK:
		push_error("Static query check: report directory creation failed.")
		return
	var path: String = "%s/StaticRowCheck_%d.json" % [directory, Time.get_ticks_usec()]
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Static query check: cannot open report file.")
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print(
		"Static row check: %s / %d queries / %d mismatches"
		% ["PASS" if _mismatchCount == 0 else "FAIL", _compared, _mismatchCount]
	)
	print("Static row check report saved: ", ProjectSettings.globalize_path(path))
	if _mismatchCount > 0:
		push_error("Static row check failed. Do not use performance results as an improvement.")


func _Compare(
	optimized: NavigationStaticQuery,
	reference,
	start: Vector2,
	end: Vector2,
	halfSize: int,
	label: String,
) -> void:
	var expected: bool = reference.SegmentClear(start, end, halfSize)
	var actual: bool = optimized.SegmentClear(start, end, halfSize)
	var detailed: bool = optimized.SegmentClear(start, end, halfSize, _metrics)
	_compared += 1
	if actual == expected and detailed == expected:
		return
	_mismatchCount += 1
	if _mismatches.size() < 20:
		_mismatches.append(
			{
				"label": label,
				"start": [start.x, start.y],
				"end": [end.x, end.y],
				"half_size": halfSize,
				"expected": expected,
				"actual_details_off": actual,
				"actual_details_on": detailed,
			}
		)


func _RunFixture(origin: Vector2, cellSize: int, slop: float) -> void:
	var data: NavigationData = NavigationData.new()
	data.gridSize = Vector2i(64, 64)
	data.cellSize = cellSize
	data.worldOrigin = origin
	data.staticContactSlop = slop
	data.blocked.resize(64 * 64)
	data.blocked.fill(0)
	data.blocked[32 * 64 + 32] = 1
	data.prefixSum.resize(65 * 65)
	data.prefixSum.fill(0)
	for y: int in range(64):
		for x: int in range(64):
			data.prefixSum[(y + 1) * 65 + x + 1] = (
				int(data.blocked[y * 64 + x]) + data.prefixSum[y * 65 + x + 1]
				+ data.prefixSum[(y + 1) * 65 + x]
				- data.prefixSum[y * 65 + x]
			)
	var optimized: NavigationStaticQuery = NavigationStaticQuery.new(data)
	var reference = REFERENCE.new(data)
	var center: Vector2 = origin + Vector2(32.5, 32.5) * float(cellSize)
	var reach: float = float(cellSize) * 24.0
	for halfSize: int in [0, 16, 32]:
		var expanded: float = maxf(0.0, float(halfSize) - slop) + float(cellSize) * 0.5 - 0.001
		for offset: float in [
			0.0,
			expanded - 0.001,
			expanded,
			expanded + 0.001,
			-expanded - 0.001,
			-expanded,
			-expanded + 0.001,
		]:
			var pairs: Array = [
				[center + Vector2(-reach, offset), center + Vector2(reach, offset)],
				[center + Vector2(offset, -reach), center + Vector2(offset, reach)],
				[center + Vector2(-reach, -reach + offset), center + Vector2(reach, reach + offset)],
				[center + Vector2(-reach, reach + offset), center + Vector2(reach, -reach + offset)],
				[center + Vector2(-reach, offset), center + Vector2(reach, offset + 0.00001)],
			]
			for pair: Array in pairs:
				_Compare(optimized, reference, pair[0], pair[1], halfSize, "fixture")
				_Compare(optimized, reference, pair[1], pair[0], halfSize, "fixture_reverse")
		for point: Vector2 in [center, center + Vector2(reach, 0), origin - Vector2.ONE]:
			_Compare(optimized, reference, point, point, halfSize, "fixture_zero_length_or_invalid")
			_Compare(
				optimized,
				reference,
				point,
				point + Vector2(1.0, 0.0),
				halfSize,
				"fixture_short_recovery",
			)
