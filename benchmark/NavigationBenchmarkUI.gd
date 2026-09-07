class_name NavigationBenchmarkUI
extends Control

signal RunAllRequested

var _resultsByCase: Dictionary = { }

@onready var _runAllButton: Button = %RunAllButton
@onready var _caseSelect: OptionButton = %CaseSelect
@onready var _statusLabel: Label = %StatusLabel

@onready var _avgValue: Label = %AvgValue
@onready var _p50Value: Label = %P50Value
@onready var _p95Value: Label = %P95Value
@onready var _maxValue: Label = %MaxValue

@onready var _pathSizeValue: Label = %PathSizeValue
@onready var _emptyPathsValue: Label = %EmptyPathsValue

@onready var _startAnchorValue: Label = %StartAnchorValue
@onready var _targetAnchorValue: Label = %TargetAnchorValue
@onready var _anchorGraphValue: Label = %AnchorGraphValue
@onready var _fallbackGridValue: Label = %FallbackGridValue

@onready var _startAnchorBar: ProgressBar = %StartAnchorBar
@onready var _targetAnchorBar: ProgressBar = %TargetAnchorBar
@onready var _anchorGraphBar: ProgressBar = %AnchorGraphBar
@onready var _fallbackGridBar: ProgressBar = %FallbackGridBar

@onready var _gridCallsValue: Label = %GridCallsValue
@onready var _gridExpandedValue: Label = %GridExpandedValue
@onready var _gridRelaxedValue: Label = %GridRelaxedValue

@onready var _worstTimeValue: Label = %WorstTimeValue
@onready var _worstExpandedValue: Label = %WorstExpandedValue
@onready var _worstRelaxedValue: Label = %WorstRelaxedValue
@onready var _worstTargetsValue: Label = %WorstTargetsValue


func _ready() -> void:
	_runAllButton.pressed.connect(_OnRunAllButtonPressed)
	_caseSelect.item_selected.connect(_OnCaseSelected)


func SetCases(cases: Array[NavigationBenchmarkCase]) -> void:
	_caseSelect.clear()

	for benchmarkCase: NavigationBenchmarkCase in cases:
		_caseSelect.add_item(benchmarkCase.caseName)

	if not cases.is_empty():
		_caseSelect.select(0)

	_SetEmptyResult()


func SetRunning(isRunning: bool) -> void:
	_runAllButton.disabled = isRunning
	_caseSelect.disabled = isRunning

	if isRunning:
		show()
		_resultsByCase.clear()
		_SetEmptyResult()
		_statusLabel.text = "Running benchmark..."
	else:
		_statusLabel.text = "Complete - select a case to inspect"


func ShowResult(
	caseName: String,
	elapsedTimes: Array[float],
	metrics: Dictionary,
	pathSizeTotal: int,
	emptyPathCount: int,
	runCount: int,
	worstMetrics: Dictionary,
) -> void:
	_resultsByCase[caseName] = {
		"elapsedTimes": elapsedTimes.duplicate(),
		"metrics": metrics.duplicate(),
		"pathSizeTotal": pathSizeTotal,
		"emptyPathCount": emptyPathCount,
		"runCount": runCount,
		"worstMetrics": worstMetrics.duplicate(),
	}

	if _GetSelectedCaseName() == caseName:
		_ShowSelectedResult()


func _OnRunAllButtonPressed() -> void:
	RunAllRequested.emit()


func _OnCaseSelected(_index: int) -> void:
	_ShowSelectedResult()


func _ShowSelectedResult() -> void:
	var caseName: String = _GetSelectedCaseName()
	if not _resultsByCase.has(caseName):
		_SetEmptyResult()
		return

	var result: Dictionary = _resultsByCase[caseName]
	var elapsedTimes: Array = result["elapsedTimes"]
	var metrics: Dictionary = result["metrics"]
	var runCount: int = int(result["runCount"])
	var worstMetrics: Dictionary = result["worstMetrics"]

	_avgValue.text = _FormatDuration(_GetAverage(elapsedTimes))
	_p50Value.text = _FormatDuration(_GetPercentile(elapsedTimes, 0.50))
	_p95Value.text = _FormatDuration(_GetPercentile(elapsedTimes, 0.95))
	_maxValue.text = _FormatDuration(
		float(elapsedTimes.back()) if not elapsedTimes.is_empty() else 0.0
	)

	_pathSizeValue.text = "%.2f" % (
		float(result["pathSizeTotal"]) / float(runCount) if runCount > 0 else 0.0
	)
	_emptyPathsValue.text = str(result["emptyPathCount"])

	var startAnchorMs: float = _GetMetricAverageMs(
		metrics,
		"start_anchor_connection_usec",
		runCount,
	)
	var targetAnchorMs: float = _GetMetricAverageMs(
		metrics,
		"target_anchor_connection_usec",
		runCount,
	)
	var anchorGraphMs: float = _GetMetricAverageMs(metrics, "anchor_graph_usec", runCount)
	var fallbackGridMs: float = _GetMetricAverageMs(metrics, "fallback_grid_usec", runCount)

	_startAnchorValue.text = _FormatDuration(startAnchorMs)
	_targetAnchorValue.text = _FormatDuration(targetAnchorMs)
	_anchorGraphValue.text = _FormatDuration(anchorGraphMs)
	_fallbackGridValue.text = _FormatDuration(fallbackGridMs)

	_UpdatePhaseBars(startAnchorMs, targetAnchorMs, anchorGraphMs, fallbackGridMs)

	var gridCalls: float = _GetMetricAverage(metrics, "grid_search_calls", runCount)
	_gridCallsValue.text = "%.2f" % gridCalls
	_gridExpandedValue.text = "%.2f" % _GetMetricAverage(metrics, "grid_expanded", runCount)
	_gridRelaxedValue.text = "%.2f" % _GetMetricAverage(metrics, "grid_relaxed", runCount)

	_UpdateWorstAnchorBatch(worstMetrics)
	_UpdateResultDescription(
		int(result["pathSizeTotal"]),
		runCount,
		gridCalls,
		startAnchorMs,
		targetAnchorMs,
		anchorGraphMs,
		fallbackGridMs,
	)


func _UpdatePhaseBars(
	startAnchorMs: float,
	targetAnchorMs: float,
	anchorGraphMs: float,
	fallbackGridMs: float,
) -> void:
	var maxValue: float = maxf(
		0.001,
		maxf(startAnchorMs, maxf(targetAnchorMs, maxf(anchorGraphMs, fallbackGridMs))),
	)

	for bar: ProgressBar in [
		_startAnchorBar,
		_targetAnchorBar,
		_anchorGraphBar,
		_fallbackGridBar,
	]:
		bar.max_value = maxValue

	_startAnchorBar.value = startAnchorMs
	_targetAnchorBar.value = targetAnchorMs
	_anchorGraphBar.value = anchorGraphMs
	_fallbackGridBar.value = fallbackGridMs


func _UpdateWorstAnchorBatch(metrics: Dictionary) -> void:
	var worstUsec: int = int(metrics.get("anchor_batch_max_usec", 0))
	if worstUsec <= 0:
		_worstTimeValue.text = "None"
		_worstExpandedValue.text = "-"
		_worstRelaxedValue.text = "-"
		_worstTargetsValue.text = "-"
		return

	_worstTimeValue.text = _FormatDuration(worstUsec / 1000.0)
	_worstExpandedValue.text = str(int(metrics.get("anchor_batch_max_expanded", 0)))
	_worstRelaxedValue.text = str(int(metrics.get("anchor_batch_max_relaxed", 0)))
	_worstTargetsValue.text = str(int(metrics.get("anchor_batch_max_target_count", 0)))


func _SetEmptyResult() -> void:
	for label: Label in [
		_avgValue,
		_p50Value,
		_p95Value,
		_maxValue,
		_pathSizeValue,
		_emptyPathsValue,
		_startAnchorValue,
		_targetAnchorValue,
		_anchorGraphValue,
		_fallbackGridValue,
		_gridCallsValue,
		_gridExpandedValue,
		_gridRelaxedValue,
		_worstTimeValue,
		_worstExpandedValue,
		_worstRelaxedValue,
		_worstTargetsValue,
	]:
		label.text = "-"

	for bar: ProgressBar in [
		_startAnchorBar,
		_targetAnchorBar,
		_anchorGraphBar,
		_fallbackGridBar,
	]:
		bar.max_value = 1.0
		bar.value = 0.0

	if _resultsByCase.is_empty():
		_statusLabel.text = "Press Run All"


func _GetSelectedCaseName() -> String:
	if _caseSelect.item_count <= 0 or _caseSelect.selected < 0:
		return ""

	return _caseSelect.get_item_text(_caseSelect.selected)


func _FormatDuration(valueMs: float) -> String:
	if valueMs < 1.0:
		return "%.1f us" % (valueMs * 1000.0)

	return "%.3f ms" % valueMs


func _UpdateResultDescription(
	pathSizeTotal: int,
	runCount: int,
	gridCalls: float,
	startAnchorMs: float,
	targetAnchorMs: float,
	anchorGraphMs: float,
	fallbackGridMs: float,
) -> void:
	var hasPath: bool = pathSizeTotal > 0 and runCount > 0
	var usedMeasuredSearchPhase: bool = (
		gridCalls > 0.0
		or startAnchorMs > 0.0
		or targetAnchorMs > 0.0
		or anchorGraphMs > 0.0
		or fallbackGridMs > 0.0
	)

	if hasPath and not usedMeasuredSearchPhase:
		_statusLabel.text = "Direct path - A* / Anchor phases skipped"
	else:
		_statusLabel.text = "Complete - select a case to inspect"


func _GetAverage(values: Array) -> float:
	if values.is_empty():
		return 0.0

	var total: float = 0.0
	for value: float in values:
		total += value

	return total / values.size()


func _GetPercentile(values: Array, percentile: float) -> float:
	if values.is_empty():
		return 0.0

	var sortedValues: Array = values.duplicate()
	sortedValues.sort()
	var index: int = int(ceil((sortedValues.size() - 1) * percentile))
	return float(sortedValues[index])


func _GetMetricAverage(metrics: Dictionary, key: String, count: int) -> float:
	if count <= 0:
		return 0.0

	return float(metrics.get(key, 0)) / float(count)


func _GetMetricAverageMs(metrics: Dictionary, key: String, count: int) -> float:
	return _GetMetricAverage(metrics, key, count) / 1000.0
