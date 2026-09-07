extends Node2D

const WARMUP_COUNT: int = 3
const MEASUREMENT_COUNT: int = 10

@export var navigationData: NavigationData
var _navigationService: NavigationService
var _isRunning: bool = false

@onready var _benchmarkUI: NavigationBenchmarkUI = $CanvasLayer/BenchmarkUI
@onready var _runBenchmarkButton: Button = $CanvasLayer/RunBenchmarkButton

var _cases: Array[NavigationBenchmarkCase] = [
	NavigationBenchmarkCase.new("CrossRegion_Reachable", Vector2(290, 430), Vector2(3040, 3120), 16),
	NavigationBenchmarkCase.new("SameRegion_Direct", Vector2(290, 430), Vector2(1026, 915), 16),
	NavigationBenchmarkCase.new(
		"UnreachableTarget_Correction",
		Vector2(290, 430),
		Vector2(1862, 618),
		16,
	),
]


class BenchmarkRunResult:
	var elapsedMsec: float = 0.0
	var pathSize: int = 0
	var metrics: Dictionary = { }


func _ready() -> void:
	_navigationService = NavigationService.new()
	_navigationService.navigationData = navigationData
	_navigationService.Ready()

	_benchmarkUI.SetCases(_cases)
	_benchmarkUI.RunAllRequested.connect(_RunAllBenchmarks)
	_runBenchmarkButton.pressed.connect(_RunAllBenchmarks)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var pos: Vector2 = get_global_mouse_position()
			print(
				"Position: ",
				pos,
				" / CanPlace(16): ",
				_navigationService.CanPlaceStatic(pos, 16),
			)


func _draw() -> void:
	for benchmarkCase: NavigationBenchmarkCase in _cases:
		draw_circle(benchmarkCase.start, 12.0, Color.WHITE)
		draw_circle(benchmarkCase.target, 12.0, Color.RED)
		draw_line(benchmarkCase.start, benchmarkCase.target, Color.YELLOW, 2.0)


func _RunAllBenchmarks() -> void:
	if _isRunning:
		return

	_isRunning = true
	_runBenchmarkButton.hide()
	_benchmarkUI.SetRunning(true)

	# UI가 먼저 표시된 뒤 벤치마크를 실행한다.
	await get_tree().process_frame

	for benchmarkCase: NavigationBenchmarkCase in _cases:
		_RunBenchmark(benchmarkCase)

	_benchmarkUI.SetRunning(false)
	_isRunning = false


func _RunBenchmark(benchmarkCase: NavigationBenchmarkCase) -> void:
	if not _navigationService.CanPlaceStatic(benchmarkCase.start, benchmarkCase.halfSize):
		push_error(
			"Invalid benchmark start: %s / %s" % [benchmarkCase.caseName, benchmarkCase.start]
		)
		return

	# if not _navigationService.CanPlaceStatic(benchmarkCase.target, benchmarkCase.halfSize):
	# 	push_error(
	# 		"Invalid benchmark target: %s / %s" % [benchmarkCase.caseName, benchmarkCase.target]
	# 	)
	# 	return
	for i: int in range(WARMUP_COUNT):
		_RunPathFinding(benchmarkCase)

	var results: Array[BenchmarkRunResult] = []
	for i: int in range(MEASUREMENT_COUNT):
		results.append(_RunPathFinding(benchmarkCase))

	_ShowResult(benchmarkCase, results)


func _RunPathFinding(benchmarkCase: NavigationBenchmarkCase) -> BenchmarkRunResult:
	# 동일 Start/Target 반복으로 Anchor Connection Cache가 측정값을 가리지 않도록 요청 캐시만 제거한다.
	_navigationService.ClearBenchmarkRequestCache()

	var metrics: NavigationProfileMetrics = NavigationProfileMetrics.new()
	_navigationService.SetProfileMetrics(metrics)

	var startTime: int = Time.get_ticks_usec()

	var target: Vector2 = benchmarkCase.target
	if benchmarkCase.caseName == "UnreachableTarget_Correction":
		target = _navigationService.GetNearestReachablePoint(
			benchmarkCase.target,
			benchmarkCase.halfSize,
			benchmarkCase.start,
		)

	var path: PackedVector2Array = _navigationService.FindPath(
		benchmarkCase.start,
		target,
		benchmarkCase.halfSize,
	)

	var elapsedUsec: int = Time.get_ticks_usec() - startTime

	_navigationService.ClearProfileMetrics()

	var result: BenchmarkRunResult = BenchmarkRunResult.new()
	result.elapsedMsec = elapsedUsec / 1000.0
	result.pathSize = path.size()
	result.metrics = metrics.ToDictionary()

	return result


func _ShowResult(
	benchmarkCase: NavigationBenchmarkCase,
	results: Array[BenchmarkRunResult],
) -> void:
	var elapsedTimes: Array[float] = []
	var metricTotals: Dictionary = { }

	var pathSizeTotal: int = 0
	var emptyPathCount: int = 0

	for result: BenchmarkRunResult in results:
		elapsedTimes.append(result.elapsedMsec)
		pathSizeTotal += result.pathSize

		if result.pathSize == 0:
			emptyPathCount += 1

		_AccumulateMetrics(metricTotals, result.metrics)

	elapsedTimes.sort()

	_benchmarkUI.ShowResult(
		benchmarkCase.caseName,
		elapsedTimes,
		metricTotals,
		pathSizeTotal,
		emptyPathCount,
		results.size(),
		_GetWorstAnchorBatchMetrics(results),
	)


func _GetWorstAnchorBatchMetrics(results: Array[BenchmarkRunResult]) -> Dictionary:
	var worstMetrics: Dictionary = { }
	var worstUsec: int = 0

	for result: BenchmarkRunResult in results:
		var usec: int = int(result.metrics.get("anchor_batch_max_usec", 0))
		if usec <= worstUsec:
			continue

		worstUsec = usec
		worstMetrics = result.metrics

	return worstMetrics


func _AccumulateMetrics(totals: Dictionary, metrics: Dictionary) -> void:
	for key: String in metrics:
		totals[key] = int(totals.get(key, 0)) + int(metrics[key])
