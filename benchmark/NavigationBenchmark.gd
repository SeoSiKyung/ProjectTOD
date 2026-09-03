extends Node2D

const WARMUP_COUNT: int = 3
const MEASUREMENT_COUNT: int = 10

@export var navigationData: NavigationData
var _navigationService: NavigationService

var _cases: Array[NavigationBenchmarkCase] = [
	NavigationBenchmarkCase.new("SameRegion_Direct", Vector2(290, 430), Vector2(1026, 915), 16),
	NavigationBenchmarkCase.new("CrossRegion_Reachable", Vector2(290, 430), Vector2(3040, 3120), 16),
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

	print("Navigation Ready: ", _navigationService.IsReady())


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.pressed and not event.echo and event.keycode == KEY_B:
			_RunAllBenchmarks()


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
	for benchmarkCase in _cases:
		_RunBenchmark(benchmarkCase)


func _RunBenchmark(benchmarkCase: NavigationBenchmarkCase) -> void:
	if not _navigationService.CanPlaceStatic(benchmarkCase.start, benchmarkCase.halfSize):
		push_error(
			"Invalid benchmark start: %s / %s" % [benchmarkCase.caseName, benchmarkCase.start]
		)
		return

	for i: int in range(WARMUP_COUNT):
		_RunPathFinding(benchmarkCase)

	var results: Array[BenchmarkRunResult] = []
	for i: int in range(MEASUREMENT_COUNT):
		results.append(_RunPathFinding(benchmarkCase))

	_PrintResult(benchmarkCase, results)


func _RunPathFinding(benchmarkCase: NavigationBenchmarkCase) -> BenchmarkRunResult:
	# 동일 Start/Target 반복으로 Anchor Connection Cache가 측정값을 가리지 않도록 요청 캐시만 제거한다.
	_navigationService.ClearBenchmarkRequestCache()

	var metrics: NavigationProfileMetrics = NavigationProfileMetrics.new()
	_navigationService.SetProfileMetrics(metrics)

	var startTime: int = Time.get_ticks_usec()
	var path: PackedVector2Array = _navigationService.FindPath(
		benchmarkCase.start,
		benchmarkCase.target,
		benchmarkCase.halfSize,
	)
	var elapsedUsec: int = Time.get_ticks_usec() - startTime

	_navigationService.ClearProfileMetrics()

	var result := BenchmarkRunResult.new()
	result.elapsedMsec = elapsedUsec / 1000.0
	result.pathSize = path.size()
	result.metrics = metrics.ToDictionary()

	return result


func _PrintResult(
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

	print("")
	print("========================================")
	print("[Navigation Benchmark] ", benchmarkCase.caseName)
	print("Runs : ", results.size())

	_PrintExecutionTime(elapsedTimes)
	_PrintPathResult(pathSizeTotal, emptyPathCount, metricTotals, results.size())
	_PrintPhaseTime(metricTotals, results.size())
	_PrintGridSearch(metricTotals, results.size())
	_PrintAnchorConnection(metricTotals, results.size())
	_PrintAnchorGraph(metricTotals, results.size())
	_PrintStaticQuery(metricTotals, results.size())
	_PrintWorstAnchorBatch(results)

	print("========================================")


func _PrintExecutionTime(elapsedTimes: Array[float]) -> void:
	print("")
	print("[Execution Time]")
	print("  Avg : %.3f ms" % _GetAverage(elapsedTimes))
	print("  P50 : %.3f ms" % _GetPercentile(elapsedTimes, 0.50))
	print("  P95 : %.3f ms" % _GetPercentile(elapsedTimes, 0.95))
	print("  Max : %.3f ms" % elapsedTimes.back())


func _PrintPathResult(
	pathSizeTotal: int,
	emptyPathCount: int,
	metrics: Dictionary,
	runCount: int,
) -> void:
	print("")
	print("[Path Result]")
	print("  %-26s : %.2f" % ["Path Size Avg", float(pathSizeTotal) / runCount])
	print("  %-26s : %d" % ["Empty Paths", emptyPathCount])

	_PrintMetricAverage(metrics, "target_correction_count", "Target Correction", runCount)


func _PrintPhaseTime(metrics: Dictionary, count: int) -> void:
	print("")
	print("[FindPath Phase]")
	_PrintMetricUsecAsMs(metrics, "resolve_target_usec", "Resolve Target", count)
	_PrintMetricUsecAsMs(metrics, "start_anchor_connection_usec", "Start Anchor Connection", count)
	_PrintMetricUsecAsMs(
		metrics,
		"target_anchor_connection_usec",
		"Target Anchor Connection",
		count,
	)
	_PrintMetricUsecAsMs(metrics, "anchor_graph_usec", "Anchor Graph", count)
	_PrintMetricUsecAsMs(metrics, "fallback_grid_usec", "Fallback Grid", count)


func _PrintGridSearch(metrics: Dictionary, count: int) -> void:
	print("")
	print("[Grid A* Search]")

	_PrintMetricAverage(metrics, "grid_search_calls", "Calls", count)
	_PrintMetricAverage(metrics, "grid_expanded", "Expanded", count)
	_PrintMetricAverage(metrics, "grid_relaxed", "Relaxed", count)


func _PrintAnchorConnection(metrics: Dictionary, count: int) -> void:
	print("")
	print("[Anchor Connection]")

	print("  Direct Check")
	_PrintMetricUsecAsMs(metrics, "anchor_direct_check_usec", "Time", count, "    ")
	_PrintMetricAverage(metrics, "anchor_direct_check_count", "Checks", count, "    ")
	_PrintMetricAverage(metrics, "anchor_direct_success_count", "Success", count, "    ")

	print("  Component Probe")
	_PrintMetricUsecAsMs(metrics, "anchor_probe_usec", "Time", count, "    ")
	_PrintMetricAverage(metrics, "anchor_probe_count", "Calls", count, "    ")
	_PrintMetricAverage(metrics, "anchor_probe_success_count", "Success", count, "    ")

	print("  Portal Batch")
	_PrintMetricUsecAsMs(metrics, "anchor_portal_batch_usec", "Time", count, "    ")
	_PrintMetricAverage(metrics, "anchor_portal_batch_search_calls", "Calls", count, "    ")
	_PrintMetricAverage(metrics, "anchor_portal_batch_expanded", "Expanded", count, "    ")
	_PrintMetricAverage(metrics, "anchor_portal_batch_relaxed", "Relaxed", count, "    ")

	print("  Individual Fallback")
	_PrintMetricUsecAsMs(metrics, "anchor_individual_fallback_usec", "Time", count, "    ")
	_PrintMetricAverage(metrics, "anchor_individual_fallback_count", "Calls", count, "    ")
	_PrintMetricAverage(
		metrics,
		"anchor_individual_fallback_success_count",
		"Success",
		count,
		"    ",
	)

	print("  Cache")
	_PrintMetricAverage(metrics, "anchor_cache_hits", "Hit", count, "    ")
	_PrintMetricAverage(metrics, "anchor_cache_misses", "Miss", count, "    ")


func _PrintAnchorGraph(metrics: Dictionary, count: int) -> void:
	print("")
	print("[Anchor Graph]")

	_PrintMetricAverage(metrics, "anchor_graph_search_calls", "Calls", count)
	_PrintMetricAverage(metrics, "anchor_graph_expanded", "Expanded", count)
	_PrintMetricAverage(metrics, "anchor_graph_relaxed", "Relaxed", count)


func _PrintStaticQuery(metrics: Dictionary, count: int) -> void:
	print("")
	print("[Static Query]")

	_PrintMetricAverage(metrics, "segment_clear_query_calls", "SegmentClear Queries", count)
	_PrintMetricAverage(metrics, "static_segment_checks", "Static Segment Checks", count)


func _PrintWorstAnchorBatch(results: Array[BenchmarkRunResult]) -> void:
	var worstMetrics: Dictionary = { }
	var worstUsec: int = 0

	for result: BenchmarkRunResult in results:
		var usec: int = int(result.metrics.get("anchor_batch_max_usec", 0))
		if usec <= worstUsec:
			continue

		worstUsec = usec
		worstMetrics = result.metrics

	print("")
	print("[Worst Anchor Batch]")

	if worstUsec <= 0:
		print("  None")
		return

	print("  %-26s : %.3f ms" % ["Time", worstUsec / 1000.0])
	print("  %-26s : %d" % ["Expanded", int(worstMetrics.get("anchor_batch_max_expanded", 0))])
	print("  %-26s : %d" % ["Relaxed", int(worstMetrics.get("anchor_batch_max_relaxed", 0))])
	print("  %-26s : %d" % ["Targets", int(worstMetrics.get("anchor_batch_max_target_count", 0))])
	print(
		"  %-26s : %d" % ["Search Area", int(worstMetrics.get("anchor_batch_max_search_area", 0))]
	)


func _PrintMetricAverage(
	metrics: Dictionary,
	key: String,
	label: String,
	count: int,
	indent: String = "  ",
) -> void:
	print("%s%-26s : %.2f" % [indent, label, _GetMetricAverage(metrics, key, count)])


func _PrintMetricUsecAsMs(
	metrics: Dictionary,
	key: String,
	label: String,
	count: int,
	indent: String = "  ",
) -> void:
	var averageUsec: float = _GetMetricAverage(metrics, key, count)
	print("%s%-26s : %.3f ms" % [indent, label, averageUsec / 1000.0])


func _AccumulateMetrics(totals: Dictionary, metrics: Dictionary) -> void:
	for key: Variant in metrics.keys():
		totals[key] = int(totals.get(key, 0)) + int(metrics[key])


func _GetAverage(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0

	var total: float = 0.0
	for value in values:
		total += value

	return total / values.size()


func _GetPercentile(values: Array[float], percentile: float) -> float:
	if values.is_empty():
		return 0.0

	var index: int = int(ceil((values.size() - 1) * percentile))
	return values[index]


func _GetMetricAverage(totals: Dictionary, key: String, count: int) -> float:
	if count <= 0:
		return 0.0

	return float(totals.get(key, 0)) / float(count)
