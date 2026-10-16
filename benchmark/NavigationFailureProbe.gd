extends Node

# 기존 Benchmark의 측정 결과를 재료로 하는 일회성 조회다.
const OBSERVED_REPORT: String = "20261016T195421_Movement_414528046.json"
const EXPECTED_MAP_SHA256: String = "b461aa28adbe730651c397058159e7783a02982ea29d8eae6516df621d630a62"
const MAP_PATH: String = "res://maps/2_navigation.res"


func _ready() -> void:
	var states: Array[Dictionary] = [
		{
			"unit_id": 0,
			"position": Vector2(1106, 1030),
			"target": Vector2(3000, 3104),
			"waypoint_index": 0,
		},
		{
			"unit_id": 1,
			"position": Vector2(1202, 1370),
			"target": Vector2(3040, 3104),
			"waypoint_index": 13,
		},
		{
			"unit_id": 2,
			"position": Vector2(1242, 1370),
			"target": Vector2(3080, 3104),
			"waypoint_index": 13,
		},
		{
			"unit_id": 3,
			"position": Vector2(390, 430),
			"target": Vector2(3020, 3144),
			"waypoint_index": -1,
		},
	]
	var mapHash: String = FileAccess.get_sha256(MAP_PATH)
	if mapHash != EXPECTED_MAP_SHA256:
		push_error(
			"Failure probe: map hash differs from the supplied report; do not compare these snapshots."
		)
		return
	var navigation: NavigationService = NavigationService.new()
	navigation.navigationData = load(MAP_PATH) as NavigationData
	navigation.Ready()
	if not navigation.IsReady():
		push_error("Failure probe: navigation is not ready.")
		return
	var benchmarkCases: Array[NavigationBenchmarkCase] = NavigationBenchmarkCase.CreateCases()
	var benchmarkCase: NavigationBenchmarkCase = benchmarkCases[0]
	if benchmarkCase.caseName != "Group5_Close_FarTarget":
		push_error("Failure probe: case order has changed.")
		return
	var paths: Array[PackedVector2Array] = navigation.BuildPaths(
		benchmarkCase.unitStarts,
		benchmarkCase.target,
		benchmarkCase.halfSize,
	)
	if paths.size() != benchmarkCase.unitStarts.size():
		push_error("Failure probe: failed to reproduce path array.")
		return
	var regionQuery: NavigationRegionQuery = NavigationRegionQuery.new(navigation.navigationData)
	var units: Array[Dictionary] = []
	for observed: Dictionary in states:
		var unitId: int = int(observed["unit_id"])
		var position: Vector2 = observed["position"]
		var target: Vector2 = observed["target"]
		var selectedIndex: int = int(observed["waypoint_index"])
		var regionIds: Array[int] = []
		regionQuery.FillRegionIds(regionIds, position)
		var cell: Vector2i = navigation.WorldToCell(position)
		var isPortalCell: bool = (
			navigation.IsCellInGrid(cell)
			and navigation \
					.navigationData \
					.portalMap[Grid.CellToIndex(cell, navigation.navigationData.gridSize.x)]
			!= 0
		)
		var path: PackedVector2Array = paths[unitId]
		var rawPath: Array = []
		var blockedSegments: Array[Dictionary] = []
		var previousPoint: Vector2 = benchmarkCase.unitStarts[unitId]
		for index: int in range(path.size()):
			rawPath.append([path[index].x, path[index].y])
			if not navigation.SegmentClear(previousPoint, path[index], benchmarkCase.halfSize):
				blockedSegments.append({ "from_index": index - 1, "to_index": index })
			previousPoint = path[index]
		var futureVisibility: Array[Dictionary] = []
		for index: int in range(maxi(0, selectedIndex + 1), path.size()):
			if position.distance_to(path[index]) < PathFollower.REACH_DISTANCE:
				continue
			futureVisibility.append(
				{
					"index": index,
					"segment_clear": navigation.SegmentClear(
						position,
						path[index],
						benchmarkCase.halfSize,
					),
				}
			)
		var offsetStart: int = Time.get_ticks_usec()
		var offsetPath: PackedVector2Array = navigation.FindPath(
			position,
			target,
			benchmarkCase.halfSize,
		)
		var offsetUsec: int = Time.get_ticks_usec() - offsetStart
		var commandStart: int = Time.get_ticks_usec()
		var commandPath: PackedVector2Array = navigation.FindPath(
			position,
			benchmarkCase.target,
			benchmarkCase.halfSize,
		)
		var commandUsec: int = Time.get_ticks_usec() - commandStart
		units.append(
			{
				"unit_id": unitId,
				"observed_position": [position.x, position.y],
				"position_region_ids": regionIds,
				"position_is_portal_cell": isPortalCell,
				"observed_agent_target": [target.x, target.y],
				"observed_waypoint_index": selectedIndex,
				"reproduced_path": rawPath,
				"reproduced_path_size_matches": path.size() == 23,
				"reproduced_goal_matches": _EndsAt(path, target),
				"selected_point_matches_observed_position": selectedIndex >= 0
				and selectedIndex < path.size()
				and position.distance_to(path[selectedIndex]) < PathFollower.REACH_DISTANCE,
				"blocked_original_segments": blockedSegments,
				"future_visibility": futureVisibility,
				"current_position_placeable": navigation.CanPlaceStatic(
					position,
					benchmarkCase.halfSize,
				),
				"agent_target_placeable": navigation.CanPlaceStatic(target, benchmarkCase.halfSize),
				"position_component": navigation.GetComponentId(position, benchmarkCase.halfSize),
				"agent_target_component": navigation.GetComponentId(target, benchmarkCase.halfSize),
				"path_to_agent_target": {
					"reaches_target": _EndsAt(offsetPath, target),
					"size": offsetPath.size(),
					"elapsed_usec": offsetUsec,
				},
				"path_to_original_target": {
					"reaches_target": _EndsAt(commandPath, benchmarkCase.target),
					"size": commandPath.size(),
					"elapsed_usec": commandUsec,
				},
			}
		)
	var report: Dictionary = {
		"schema": "failure-probe-v1",
		"observed_report": OBSERVED_REPORT,
		"expected_base_commit": "039c758799d46db7d38a2a861fccaca8334023b7",
		"engine": Engine.get_version_info(),
		"navigation_data_sha256": mapHash,
		"case_name": benchmarkCase.caseName,
		"original_command_target": [benchmarkCase.target.x, benchmarkCase.target.y],
		"half_size": benchmarkCase.halfSize,
		"notes": [
			"One-shot static queries on regenerated paths at positions recorded in the observed report. No unit movement is executed.",
			"future_visibility checks every index after the recorded selected waypoint; it does not assume visibility is monotonic.",
			"The recorded originalPathIndex was not available. This does not replay the actual shortcut selection or find the first invalid tick.",
			"FindPath calls are isolated feasibility probes, not connected repath. They do not prove Movement success.",
			"Query times are single-shot, ordered and cache-dependent. They are NOT before/after performance results.",
		],
		"units": units,
	}
	var directory: String = "user://navigation_benchmark_reports"
	var error: Error = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(directory)
	)
	if error != OK:
		push_error("Failure probe: cannot create report directory.")
		return
	var path: String = "%s/FailureProbe_%d.json" % [directory, Time.get_ticks_usec()]
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Failure probe: cannot open report file.")
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.flush()
	error = file.get_error()
	file.close()
	if error != OK:
		push_error("Failure probe: cannot write report.")
		return
	print("Failure probe saved: ", ProjectSettings.globalize_path(path))


func _EndsAt(path: PackedVector2Array, target: Vector2) -> bool:
	return not path.is_empty() and path[path.size() - 1].distance_squared_to(target) <= Math.EPSILON
