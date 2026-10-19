class_name NavigationBenchmarkUI
extends Control

const BENCHMARK_SCREENSHOT = preload("res://benchmark/NavigationBenchmarkScreenshot.gd")

enum Mode {
	PATH_BUILD,
	MOVEMENT,
}

signal RunAllRequested(mode: int)
signal RunSelectedRequested(mode: int, caseIndex: int)

var _pathResultsByCase: Dictionary = { }
var _movementResultsByCase: Dictionary = { }
var _isSavingScreenshots: bool = false

@onready var _panel: PanelContainer = $Panel
@onready var _content: VBoxContainer = _panel.get_node("Margin/VBox")

#region Controls

@onready var _controlRow: HBoxContainer = _content.get_node("ControlRow")
@onready var _runAllButton: Button = _controlRow.get_node("RunAllButton")
@onready var _runSelectedButton: Button = _controlRow.get_node("RunSelectedButton")
@onready var _saveAllButton: Button = _controlRow.get_node("SaveAllButton")
@onready var _modeSelect: OptionButton = _controlRow.get_node("ModeSelect")
@onready var _caseSelect: OptionButton = _controlRow.get_node("CaseSelect")
@onready var _statusLabel: Label = _content.get_node("StatusLabel")

#endregion

#region Group Input

@onready var _groupInput: HBoxContainer = _content.get_node("GroupInputPanel/HBox")
@onready var _groupRadiusValue: Label = _groupInput.get_node("GroupRadiusValue")
@onready var _averageCenterDistanceValue: Label = _groupInput.get_node("AverageCenterDistanceValue")
@onready var _targetDistanceValue: Label = _groupInput.get_node("TargetDistanceValue")

#endregion

#region Summary

@onready var _summaryRow: HBoxContainer = _content.get_node("SummaryRow")
@onready var _executionVBox: VBoxContainer = _summaryRow.get_node("ExecutionPanel/VBox")
@onready var _executionGrid: GridContainer = _executionVBox.get_node("Grid")
@onready var _avgValue: Label = _executionGrid.get_node("AvgValue")
@onready var _p50Value: Label = _executionGrid.get_node("P50Value")
@onready var _p95Value: Label = _executionGrid.get_node("P95Value")
@onready var _maxValue: Label = _executionGrid.get_node("MaxValue")

@onready var _resultVBox: VBoxContainer = _summaryRow.get_node("PathPanel/VBox")
@onready var _resultGrid: GridContainer = _resultVBox.get_node("Grid")
@onready var _pathSizeValue: Label = _resultGrid.get_node("PathSizeValue")
@onready var _emptyPathsValue: Label = _resultGrid.get_node("EmptyPathsValue")
@onready var _pathOverlapValue: Label = _resultGrid.get_node("PathOverlapValue")
@onready var _pathLengthValue: Label = _resultGrid.get_node("PathLengthValue")

#endregion

#region Detail

@onready var _detailRow: HBoxContainer = _content.get_node("DetailRow")
@onready var _phaseVBox: VBoxContainer = _detailRow.get_node("PhasePanel/VBox")
@onready var _phaseGrid: GridContainer = _phaseVBox.get_node("Grid")
@onready var _startAnchorValue: Label = _phaseGrid.get_node("StartAnchorValue")
@onready var _targetAnchorValue: Label = _phaseGrid.get_node("TargetAnchorValue")
@onready var _anchorGraphValue: Label = _phaseGrid.get_node("AnchorGraphValue")
@onready var _fallbackGridValue: Label = _phaseGrid.get_node("FallbackGridValue")
@onready var _startAnchorBar: ProgressBar = _phaseGrid.get_node("StartAnchorBar")
@onready var _targetAnchorBar: ProgressBar = _phaseGrid.get_node("TargetAnchorBar")
@onready var _anchorGraphBar: ProgressBar = _phaseGrid.get_node("AnchorGraphBar")
@onready var _fallbackGridBar: ProgressBar = _phaseGrid.get_node("FallbackGridBar")
@onready var _rebuildLabel: Label = _phaseGrid.get_node("RebuildLabel")
@onready var _rebuildValue: Label = _phaseGrid.get_node("RebuildValue")
@onready var _rebuildBar: ProgressBar = _phaseGrid.get_node("RebuildBar")

@onready var _rightDetail: VBoxContainer = _detailRow.get_node("RightDetail")
@onready var _segmentVBox: VBoxContainer = _rightDetail.get_node("SegmentPanel/VBox")
@onready var _segmentGrid: GridContainer = _segmentVBox.get_node("Grid")
@onready var _segmentTimeValue: Label = _segmentGrid.get_node("SegmentTimeValue")
@onready var _segmentCallsValue: Label = _segmentGrid.get_node("SegmentCallsValue")
@onready var _segmentAverageValue: Label = _segmentGrid.get_node("SegmentAverageValue")
@onready var _staticChecksValue: Label = _segmentGrid.get_node("StaticChecksValue")

@onready var _groupVBox: VBoxContainer = _rightDetail.get_node("GroupBuildPanel/VBox")
@onready var _groupGrid: GridContainer = _groupVBox.get_node("Grid")
@onready var _groupJoinPointValue: Label = _groupGrid.get_node("GroupJoinPointValue")
@onready var _groupSharedPathValue: Label = _groupGrid.get_node("GroupSharedPathValue")
@onready var _groupUnitPathsValue: Label = _groupGrid.get_node("GroupUnitPathsValue")
@onready var _groupSegmentJoinValue: Label = _groupGrid.get_node("GroupSegmentJoinValue")
@onready var _groupWaypointJoinValue: Label = _groupGrid.get_node("GroupWaypointJoinValue")
@onready var _groupFallbackValue: Label = _groupGrid.get_node("GroupFallbackValue")

#endregion

#region Bottom

@onready var _bottomRow: HBoxContainer = _content.get_node("BottomRow")
@onready var _gridVBox: VBoxContainer = _bottomRow.get_node("GridPanel/VBox")
@onready var _grid: GridContainer = _gridVBox.get_node("Grid")
@onready var _gridCallsValue: Label = _grid.get_node("GridCallsValue")
@onready var _gridExpandedValue: Label = _grid.get_node("GridExpandedValue")
@onready var _gridRelaxedValue: Label = _grid.get_node("GridRelaxedValue")

@onready var _worstVBox: VBoxContainer = _bottomRow.get_node("WorstPanel/VBox")
@onready var _worstGrid: GridContainer = _worstVBox.get_node("Grid")
@onready var _worstTimeValue: Label = _worstGrid.get_node("WorstTimeValue")
@onready var _worstExpandedValue: Label = _worstGrid.get_node("WorstExpandedValue")
@onready var _worstRelaxedValue: Label = _worstGrid.get_node("WorstRelaxedValue")
@onready var _worstTargetsValue: Label = _worstGrid.get_node("WorstTargetsValue")
@onready var _tickPanel: PanelContainer = _content.get_node("TickPanel")
@onready var _tickStatistics: Label = _tickPanel.get_node("VBox/Statistics")
@onready var _slowestTick: Label = _tickPanel.get_node("VBox/SlowestTick")

#endregion


func _ready() -> void:
	_modeSelect.clear()
	_modeSelect.add_item("경로 생성", Mode.PATH_BUILD)
	_modeSelect.add_item("실제 이동", Mode.MOVEMENT)
	_modeSelect.select(0)

	_runAllButton.pressed.connect(_OnRunAllButtonPressed)
	_runSelectedButton.pressed.connect(_OnRunSelectedButtonPressed)
	_saveAllButton.pressed.connect(_OnSaveAllButtonPressed)
	_modeSelect.item_selected.connect(_OnModeSelected)
	_caseSelect.item_selected.connect(_OnCaseSelected)

	_ApplyModeLabels(GetSelectedMode())


func SetImplementationLabel(revision: String) -> void:
	var title: Label = _content.get_node("Title")
	title.text = "길찾기 벤치마크 / " + revision


func SetCases(cases: Array[NavigationBenchmarkCase]) -> void:
	_caseSelect.clear()

	for benchmarkCase: NavigationBenchmarkCase in cases:
		_caseSelect.add_item(GetCaseDisplayName(benchmarkCase.caseName))
		_caseSelect.set_item_metadata(_caseSelect.item_count - 1, benchmarkCase.caseName)

	if not cases.is_empty():
		_caseSelect.select(0)

	_SetEmptyResult()


func GetSelectedMode() -> int:
	if _modeSelect.item_count <= 0 or _modeSelect.selected < 0:
		return Mode.PATH_BUILD

	return _modeSelect.get_item_id(_modeSelect.selected)


func SetRunning(isRunning: bool, mode: int, clearResults: bool = true) -> void:
	_runAllButton.disabled = isRunning
	_runSelectedButton.disabled = isRunning
	_saveAllButton.disabled = isRunning
	_modeSelect.disabled = isRunning
	_caseSelect.disabled = isRunning

	if isRunning:
		show()

		if clearResults:
			_ClearModeResults(mode)

		_SetEmptyResult()
		_statusLabel.text = ("실제 이동 측정 중..."
			if mode == Mode.MOVEMENT
			else "경로 생성 측정 중...")
	else:
		_ShowSelectedResult()


func ShowPathResult(
	caseName: String,
	elapsedTimes: Array[int],
	metrics: Dictionary,
	pathSizeTotal: int,
	emptyPathCount: int,
	staticCheckedPathCount: int,
	initialBlockedPathCount: int,
	initialBlockedSegmentCount: int,
	overlapCellTotal: int,
	comparedCellTotal: int,
	pathLengthTotal: int,
	runCount: int,
	worstMetrics: Dictionary,
	groupRadius: int,
	averageCenterDistance: int,
	targetDistance: int,
) -> void:
	_pathResultsByCase[caseName] = {
		"elapsedTimes": elapsedTimes.duplicate(),
		"metrics": metrics.duplicate(),
		"pathSizeTotal": pathSizeTotal,
		"emptyPathCount": emptyPathCount,
		"staticCheckedPathCount": staticCheckedPathCount,
		"initialBlockedPathCount": initialBlockedPathCount,
		"initialBlockedSegmentCount": initialBlockedSegmentCount,
		"overlapCellTotal": overlapCellTotal,
		"comparedCellTotal": comparedCellTotal,
		"pathLengthTotal": pathLengthTotal,
		"runCount": runCount,
		"worstMetrics": worstMetrics.duplicate(),
		"groupRadius": groupRadius,
		"averageCenterDistance": averageCenterDistance,
		"targetDistance": targetDistance,
	}

	if GetSelectedMode() == Mode.PATH_BUILD and _GetSelectedCaseName() == caseName:
		_ShowSelectedResult()


func ShowMovementResult(caseName: String, summary: Dictionary) -> void:
	_movementResultsByCase[caseName] = summary.duplicate(true)

	if GetSelectedMode() == Mode.MOVEMENT and _GetSelectedCaseName() == caseName:
		_ShowSelectedResult()


func _OnRunAllButtonPressed() -> void:
	RunAllRequested.emit(GetSelectedMode())


func _OnRunSelectedButtonPressed() -> void:
	if _caseSelect.selected < 0:
		return

	RunSelectedRequested.emit(GetSelectedMode(), _caseSelect.selected)


func _OnSaveAllButtonPressed() -> void:
	await _SaveAllScreenshots()


func _SaveAllScreenshots() -> void:
	if _isSavingScreenshots:
		return

	var mode: int = GetSelectedMode()
	var results: Dictionary = (
		_movementResultsByCase
		if mode == Mode.MOVEMENT
		else _pathResultsByCase
	)

	if results.is_empty():
		_statusLabel.text = "저장할 결과가 없습니다. 먼저 측정하세요"
		return

	var originalCaseIndex: int = _caseSelect.selected
	var modeName: String = "Movement" if mode == Mode.MOVEMENT else "PathBuild"
	var directory: String = BENCHMARK_SCREENSHOT.BuildDirectory(modeName)
	var absoluteDirectory: String = ProjectSettings.globalize_path(directory)
	var makeDirectoryError: Error = DirAccess.make_dir_recursive_absolute(absoluteDirectory)
	if makeDirectoryError != OK:
		push_error("이미지 저장 폴더 생성 실패: %s" % absoluteDirectory)
		_statusLabel.text = "이미지 저장 폴더를 만들지 못했습니다"
		return

	_isSavingScreenshots = true

	var savedCount: int = 0
	for caseIndex: int in range(_caseSelect.item_count):
		var caseName: String = str(_caseSelect.get_item_metadata(caseIndex))
		if not results.has(caseName):
			continue

		_caseSelect.select(caseIndex)
		_ShowSelectedResult()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw

		var fileName: String = "%02d_%s.png" % [
			savedCount + 1,
			BENCHMARK_SCREENSHOT.SanitizeFileName(caseName),
		]
		var saveError: Error = BENCHMARK_SCREENSHOT.SavePanel(
			_panel,
			"%s/%s" % [directory, fileName],
		)
		if saveError != OK:
			push_error("이미지 저장 실패: %s" % fileName)
			continue

		savedCount += 1

	if originalCaseIndex >= 0 and originalCaseIndex < _caseSelect.item_count:
		_caseSelect.select(originalCaseIndex)
		_ShowSelectedResult()

	_isSavingScreenshots = false
	_statusLabel.text = "이미지 %d장 저장: %s" % [savedCount, absoluteDirectory]
	print("벤치마크 이미지 저장: ", absoluteDirectory)


func _OnModeSelected(_index: int) -> void:
	_ApplyModeLabels(GetSelectedMode())
	_ShowSelectedResult()


func _OnCaseSelected(_index: int) -> void:
	_ShowSelectedResult()


func _ShowSelectedResult() -> void:
	_ApplyModeLabels(GetSelectedMode())

	match GetSelectedMode():
		Mode.MOVEMENT:
			_ShowSelectedMovementResult()
		_:
			_ShowSelectedPathResult()


func _ShowSelectedPathResult() -> void:
	var caseName: String = _GetSelectedCaseName()
	if not _pathResultsByCase.has(caseName):
		_SetEmptyResult()
		return

	var result: Dictionary = _pathResultsByCase[caseName]
	var elapsedTimes: Array = result["elapsedTimes"]
	var metrics: Dictionary = result["metrics"]
	var runCount: int = int(result["runCount"])
	var worstMetrics: Dictionary = result["worstMetrics"]

	_UpdateExecutionTimes(elapsedTimes)

	_pathSizeValue.text = "%.2f" % (
		float(result["pathSizeTotal"]) / float(runCount) if runCount > 0 else 0.0
	)
	_emptyPathsValue.text = "%d / %d" % [
		int(result["emptyPathCount"]),
		int(result["initialBlockedPathCount"]),
	]
	var overlapCellTotal: int = int(result["overlapCellTotal"])
	var comparedCellTotal: int = int(result["comparedCellTotal"])
	if comparedCellTotal <= 0:
		_pathOverlapValue.text = "-"
	else:
		var overlapRatio: int = Math.DivideInt(
			overlapCellTotal * Math.RATIO_SCALE,
			comparedCellTotal,
		)

		_pathOverlapValue.text = _FormatOverlapRatio(overlapRatio)

	var pathLengthTotal: int = int(result["pathLengthTotal"])
	_pathLengthValue.text = (
		"%d px" % Math.DivideInt(pathLengthTotal, runCount)
		if runCount > 0
		else "-"
	)

	var startAnchorUsec: int = _GetMetricAverageInt(
		metrics,
		"start_anchor_connection_usec",
		runCount,
	)
	var targetAnchorUsec: int = _GetMetricAverageInt(
		metrics,
		"target_anchor_connection_usec",
		runCount,
	)
	var anchorGraphUsec: int = _GetMetricAverageInt(metrics, "anchor_graph_usec", runCount)
	var fallbackGridUsec: int = _GetMetricAverageInt(metrics, "fallback_grid_usec", runCount)

	_startAnchorValue.text = _FormatDurationUsec(startAnchorUsec)
	_targetAnchorValue.text = _FormatDurationUsec(targetAnchorUsec)
	_anchorGraphValue.text = _FormatDurationUsec(anchorGraphUsec)
	_fallbackGridValue.text = _FormatDurationUsec(fallbackGridUsec)

	_UpdatePhaseBars(startAnchorUsec, targetAnchorUsec, anchorGraphUsec, fallbackGridUsec)

	var gridCallsTotal: int = int(metrics.get("grid_search_calls", 0))
	var gridCalls: float = _GetMetricAverageFloat(metrics, "grid_search_calls", runCount)
	_gridCallsValue.text = "%.2f" % gridCalls
	_gridExpandedValue.text = "%.2f" % _GetMetricAverageFloat(metrics, "grid_expanded", runCount)
	_gridRelaxedValue.text = "%.2f" % _GetMetricAverageFloat(metrics, "grid_relaxed", runCount)

	_UpdateSegmentClearResult(metrics, runCount)
	_UpdateGroupBuildResult(metrics, runCount)
	_UpdateWorstAnchorBatch(worstMetrics)
	_UpdateResultDescription(
		int(result["pathSizeTotal"]),
		runCount,
		gridCallsTotal,
		startAnchorUsec,
		targetAnchorUsec,
		anchorGraphUsec,
		fallbackGridUsec,
	)
	_UpdateGroupInputResult(result)

	var initialBlockedPathCount: int = int(result["initialBlockedPathCount"])
	var initialBlockedSegmentCount: int = int(result["initialBlockedSegmentCount"])
	var staticCheckedPathCount: int = int(result["staticCheckedPathCount"])
	if initialBlockedPathCount > 0:
		_statusLabel.text = "측정 종료 — 원시 경로 %d개 정적 검사 / 초기 막힘 %d개 / 막힌 인접 구간 %d개" % [
			staticCheckedPathCount,
			initialBlockedPathCount,
			initialBlockedSegmentCount,
		]
	else:
		_statusLabel.text = "측정 종료 — 원시 경로 %d개 정적 검사 / 초기 막힘 0개" % staticCheckedPathCount


func _ShowSelectedMovementResult() -> void:
	var caseName: String = _GetSelectedCaseName()
	if not _movementResultsByCase.has(caseName):
		_SetEmptyResult()
		return

	var result: Dictionary = _movementResultsByCase[caseName]
	var elapsedTimes: Array = result["elapsedTimes"]
	var commandTimes: Array = result["commandTimes"]
	var movementTimes: Array = result["movementTimes"]
	var navigationMetrics: Dictionary = result["navigationMetrics"]
	var movementMetrics: Dictionary = result["movementMetrics"]
	var runCount: int = int(result["runCount"])

	_UpdateExecutionTimes(elapsedTimes)

	_pathSizeValue.text = (
		"%.1f" % (float(result["tickTotal"]) / float(runCount))
		if runCount > 0
		else "-"
	)
	_emptyPathsValue.text = "%d / %d" % [
		int(result["completedUnitTotal"]),
		int(result["expectedUnitTotal"]),
	]

	var targetErrorSampleCount: int = int(result["targetErrorSampleCount"])
	_pathOverlapValue.text = (
		"%.1f px" % (float(result["targetErrorTotal"]) / float(targetErrorSampleCount))
		if targetErrorSampleCount > 0
		else "-"
	)
	_pathLengthValue.text = _FormatDurationUsec(_GetAverage(movementTimes))

	var commandUsec: int = _GetAverage(commandTimes)
	var captureUsec: int = _GetMetricAverageInt(movementMetrics, "capture_tick_usec", runCount)
	var commitUsec: int = _GetMetricAverageInt(movementMetrics, "commit_tick_usec", runCount)
	var pathFollowUsec: int = captureUsec + commitUsec
	var collisionUsec: int = _GetMetricAverageInt(
		movementMetrics,
		"collision_resolve_usec",
		runCount,
	)
	var arrivalUsec: int = _GetMetricAverageInt(movementMetrics, "arrival_resolve_usec", runCount)
	var rebuildUsec: int = _GetMetricAverageInt(movementMetrics, "path_rebuild_usec", runCount)

	_startAnchorValue.text = _FormatDurationUsec(commandUsec)
	_targetAnchorValue.text = _FormatDurationUsec(pathFollowUsec)
	_anchorGraphValue.text = _FormatDurationUsec(collisionUsec)
	_fallbackGridValue.text = _FormatDurationUsec(arrivalUsec)
	_rebuildValue.text = _FormatDurationUsec(rebuildUsec)
	_UpdatePhaseBars(commandUsec, pathFollowUsec, collisionUsec, arrivalUsec, rebuildUsec)
	_UpdateTickResult(result)

	_UpdateMovementSegmentClearResult(
		navigationMetrics,
		movementTimes,
		int(result["tickTotal"]),
		runCount,
	)
	_UpdateMovementCollisionResult(movementMetrics, runCount)
	_UpdateMovementRunSummary(result)
	_UpdateWorstMovementRun(result["worstRun"])
	_UpdateGroupInputResult(result)

	var timedOutCount: int = int(result["timedOutRunCount"])
	var failedCount: int = int(result["failedRunCount"])
	if timedOutCount > 0 or failedCount > 0:
		_statusLabel.text = "측정 종료 — 시간 초과 %d회 / 실패 %d회" % [timedOutCount, failedCount]
	else:
		_statusLabel.text = "측정 종료 — 모든 실행에서 도착 처리 완료"


func _UpdateExecutionTimes(elapsedTimes: Array) -> void:
	_avgValue.text = _FormatDurationUsec(_GetAverage(elapsedTimes))
	_p50Value.text = _FormatDurationUsec(Math.Percentile(elapsedTimes, 50))
	_p95Value.text = _FormatDurationUsec(Math.Percentile(elapsedTimes, 95))
	_maxValue.text = _FormatDurationUsec(
		int(elapsedTimes.back()) if not elapsedTimes.is_empty() else 0
	)


func _UpdateSegmentClearResult(metrics: Dictionary, runCount: int) -> void:
	var segmentClearUsec: int = _GetMetricAverageInt(metrics, "segment_clear_query_usec", runCount)
	var segmentClearCalls: int = _GetMetricAverageInt(
		metrics,
		"segment_clear_query_calls",
		runCount,
	)

	var totalSegmentClearUsec: int = int(metrics.get("segment_clear_query_usec", 0))
	var totalSegmentClearCalls: int = int(metrics.get("segment_clear_query_calls", 0))

	if totalSegmentClearCalls <= 0:
		_segmentAverageValue.text = "-"
	else:
		var averageSegmentUsec: int = Math.DivideInt(totalSegmentClearUsec, totalSegmentClearCalls)
		_segmentAverageValue.text = _FormatDurationUsec(averageSegmentUsec)

	var staticSegmentChecks: int = _GetMetricAverageInt(metrics, "static_segment_checks", runCount)
	_segmentTimeValue.text = _FormatDurationUsec(segmentClearUsec)
	_segmentCallsValue.text = str(segmentClearCalls)
	_staticChecksValue.text = str(staticSegmentChecks)


func _UpdateMovementSegmentClearResult(
	metrics: Dictionary,
	movementTimes: Array,
	tickTotal: int,
	runCount: int,
) -> void:
	var segmentClearUsec: int = _GetMetricAverageInt(metrics, "segment_clear_query_usec", runCount)
	var segmentClearCalls: int = _GetMetricAverageInt(
		metrics,
		"segment_clear_query_calls",
		runCount,
	)

	_segmentTimeValue.text = _FormatDurationUsec(segmentClearUsec)
	_segmentCallsValue.text = str(segmentClearCalls)

	if tickTotal <= 0:
		_segmentAverageValue.text = "-"
		_staticChecksValue.text = "-"
		return

	var totalMovementUsec: int = 0
	for movementUsec: Variant in movementTimes:
		totalMovementUsec += int(movementUsec)

	var totalSegmentClearCalls: int = int(metrics.get("segment_clear_query_calls", 0))

	var movementUsecPerTick: int = Math.DivideInt(totalMovementUsec, tickTotal)

	var segmentClearCallsPerTick: float = (float(totalSegmentClearCalls) / float(tickTotal))

	_segmentAverageValue.text = _FormatDurationUsec(movementUsecPerTick)
	_staticChecksValue.text = "%.1f" % segmentClearCallsPerTick


func _UpdateGroupBuildResult(metrics: Dictionary, runCount: int) -> void:
	var joinPointUsec: int = _GetMetricAverageInt(metrics, "group_join_point_usec", runCount)
	var sharedPathUsec: int = _GetMetricAverageInt(metrics, "group_shared_path_usec", runCount)
	var unitPathsUsec: int = _GetMetricAverageInt(metrics, "group_unit_paths_usec", runCount)

	var segmentAttempts: int = _GetMetricAverageInt(
		metrics,
		"group_join_segment_attempts",
		runCount,
	)
	var segmentSuccesses: int = _GetMetricAverageInt(
		metrics,
		"group_join_segment_successes",
		runCount,
	)

	var waypointAttempts: int = _GetMetricAverageInt(
		metrics,
		"group_join_waypoint_attempts",
		runCount,
	)
	var waypointSuccesses: int = _GetMetricAverageInt(
		metrics,
		"group_join_waypoint_successes",
		runCount,
	)

	var fallbackCalls: int = _GetMetricAverageInt(metrics, "group_join_fallback_calls", runCount)
	var fallbackSuccesses: int = _GetMetricAverageInt(
		metrics,
		"group_join_fallback_successes",
		runCount,
	)

	var hasGroupMetrics: bool = (
		joinPointUsec > 0 or sharedPathUsec > 0 or unitPathsUsec > 0
		or segmentAttempts > 0 or waypointAttempts > 0 or fallbackCalls > 0
	)

	if not hasGroupMetrics:
		_groupJoinPointValue.text = "-"
		_groupSharedPathValue.text = "-"
		_groupUnitPathsValue.text = "-"
		_groupSegmentJoinValue.text = "-"
		_groupWaypointJoinValue.text = "-"
		_groupFallbackValue.text = "-"
		return

	_groupJoinPointValue.text = _FormatDurationUsec(joinPointUsec)
	_groupSharedPathValue.text = _FormatDurationUsec(sharedPathUsec)
	_groupUnitPathsValue.text = _FormatDurationUsec(unitPathsUsec)

	_groupSegmentJoinValue.text = "%d / %d" % [segmentAttempts, segmentSuccesses]
	_groupWaypointJoinValue.text = "%d / %d" % [waypointAttempts, waypointSuccesses]
	_groupFallbackValue.text = "%d / %d" % [fallbackCalls, fallbackSuccesses]


func _UpdateMovementCollisionResult(metrics: Dictionary, runCount: int) -> void:
	_groupJoinPointValue.text = str(
		_GetMetricAverageInt(metrics, "simulation_tick_count", runCount)
	)
	_groupSharedPathValue.text = str(
		_GetMetricAverageInt(metrics, "collision_candidate_queries", runCount)
	)
	_groupUnitPathsValue.text = str(
		_GetMetricAverageInt(metrics, "dynamic_blocked_candidates", runCount)
	)
	_groupSegmentJoinValue.text = str(
		_GetMetricAverageInt(metrics, "alternate_candidate_queries", runCount)
	)
	_groupWaypointJoinValue.text = str(
		_GetMetricAverageInt(metrics, "stalled_agent_ticks", runCount)
	)
	_groupFallbackValue.text = str(_GetMetricAverageInt(metrics, "settled_agent_count", runCount))


func _UpdateMovementRunSummary(result: Dictionary) -> void:
	_gridCallsValue.text = str(int(result["runCount"]))
	_gridExpandedValue.text = str(int(result["succeededRunCount"]))
	_gridRelaxedValue.text = "%d / %d" % [
		int(result["timedOutRunCount"]),
		int(result["failedRunCount"]),
	]


func _FormatOverlapRatio(ratio: int) -> String:
	var percent: int = Math.DivideInt(ratio, 10)
	var decimal: int = Math.RemainderInt(ratio, 10)
	return "%d.%d%%" % [percent, decimal]


func _UpdatePhaseBars(
	firstUsec: int,
	secondUsec: int,
	thirdUsec: int,
	fourthUsec: int,
	rebuildUsec: int = 0,
) -> void:
	var maxValue: int = maxi(
		1,
		maxi(rebuildUsec, maxi(firstUsec, maxi(secondUsec, maxi(thirdUsec, fourthUsec)))),
	)

	for bar: ProgressBar in [
		_startAnchorBar,
		_targetAnchorBar,
		_anchorGraphBar,
		_fallbackGridBar,
		_rebuildBar,
	]:
		bar.max_value = maxValue

	_startAnchorBar.value = firstUsec
	_targetAnchorBar.value = secondUsec
	_anchorGraphBar.value = thirdUsec
	_fallbackGridBar.value = fourthUsec
	_rebuildBar.value = rebuildUsec


func _UpdateTickResult(result: Dictionary) -> void:
	var statistics: Dictionary = result.get("tickStatistics", { })
	var slowest: Dictionary = result.get("slowestTick", { })
	if statistics.is_empty():
		_tickStatistics.text = "기록 없음 (진단 꺼짐 또는 측정된 틱 없음)"
		_slowestTick.text = "최대 지연 틱: -"
		return

	_tickStatistics.text = "평균 %s    P50 %s    P95 %s    최대 %s" % [
		_FormatDurationUsec(int(statistics["average_usec"])),
		_FormatDurationUsec(int(statistics["p50_usec"])),
		_FormatDurationUsec(int(statistics["p95_usec"])),
		_FormatDurationUsec(int(statistics["max_usec"])),
	]
	if slowest.is_empty():
		_slowestTick.text = "최대 지연 틱: -"
	else:
		_slowestTick.text = "최대 지연: %d회차 / %d틱    해당 틱 재탐색: %s" % [
			int(slowest["run"]),
			int(slowest["tick"]),
			_FormatDurationUsec(int(slowest["rebuild_usec"])),
		]


func _UpdateWorstAnchorBatch(metrics: Dictionary) -> void:
	var worstUsec: int = int(metrics.get("anchor_batch_max_usec", 0))
	if worstUsec <= 0:
		_worstTimeValue.text = "None"
		_worstExpandedValue.text = "-"
		_worstRelaxedValue.text = "-"
		_worstTargetsValue.text = "-"
		return

	_worstTimeValue.text = _FormatDurationUsec(worstUsec)
	_worstExpandedValue.text = str(int(metrics.get("anchor_batch_max_expanded", 0)))
	_worstRelaxedValue.text = str(int(metrics.get("anchor_batch_max_relaxed", 0)))
	_worstTargetsValue.text = str(int(metrics.get("anchor_batch_max_target_count", 0)))


func _UpdateWorstMovementRun(worstRun: Dictionary) -> void:
	if worstRun.is_empty():
		_worstTimeValue.text = "None"
		_worstExpandedValue.text = "-"
		_worstRelaxedValue.text = "-"
		_worstTargetsValue.text = "-"
		return

	_worstTimeValue.text = _FormatDurationUsec(int(worstRun["elapsedUsec"]))
	_worstExpandedValue.text = str(int(worstRun["ticks"]))
	_worstRelaxedValue.text = str(int(worstRun["dynamicBlockedCandidates"]))
	_worstTargetsValue.text = "%d / %d" % [int(worstRun["completed"]), int(worstRun["expected"])]


func _UpdateGroupInputResult(result: Dictionary) -> void:
	var groupRadius: int = int(result["groupRadius"])
	var averageCenterDistance: int = int(result["averageCenterDistance"])
	var targetDistance: int = int(result["targetDistance"])

	if groupRadius < 0:
		_groupRadiusValue.text = "-"
		_averageCenterDistanceValue.text = "-"
		_targetDistanceValue.text = "-"
	else:
		_groupRadiusValue.text = "%d px" % groupRadius
		_averageCenterDistanceValue.text = "%d px" % averageCenterDistance
		_targetDistanceValue.text = "%d px" % targetDistance


func _ApplyModeLabels(mode: int) -> void:
	var isMovement: bool = mode == Mode.MOVEMENT
	_rebuildLabel.visible = isMovement
	_rebuildValue.visible = isMovement
	_rebuildBar.visible = isMovement
	_tickPanel.visible = isMovement
	if mode == Mode.MOVEMENT:
		_ApplyMovementLabels()
	else:
		_ApplyPathBuildLabels()


func _ApplyMovementLabels() -> void:
	_SetLabelText(_executionVBox, "Heading", "명령부터 이동 완료까지 CPU 시간")
	_SetLabelText(_resultVBox, "Heading", "실제 이동 결과")
	_SetLabelText(_resultGrid, "PathSizeLabel", "평균 틱")
	_SetLabelText(_resultGrid, "EmptyLabel", "완료 유닛")
	_SetLabelText(_resultGrid, "OverlapLabel", "평균 목표 오차")
	_SetLabelText(_resultGrid, "PathLengthLabel", "평균 이동 CPU")

	_SetLabelText(_phaseVBox, "Heading", "명령 / 이동 (실행당 평균)")
	_SetLabelText(_phaseGrid, "StartAnchorLabel", "명령 처리")
	_SetLabelText(_phaseGrid, "TargetAnchorLabel", "경로 추종 / 반영")
	_SetLabelText(_phaseGrid, "AnchorGraphLabel", "충돌 해소")
	_SetLabelText(_phaseGrid, "FallbackGridLabel", "도착 판정")

	_SetLabelText(_segmentVBox, "Heading", "이동 중 구간 검사")
	_SetLabelText(_segmentGrid, "TimeLabel", "시간")
	_SetLabelText(_segmentGrid, "CallsLabel", "호출")
	_SetLabelText(_segmentGrid, "AverageLabel", "CPU / 틱")
	_SetLabelText(_segmentGrid, "StaticLabel", "호출 / 틱")

	_SetLabelText(_groupVBox, "Heading", "충돌 / 도착")
	_SetLabelText(_groupGrid, "JoinPointLabel", "틱")
	_SetLabelText(_groupGrid, "SharedPathLabel", "후보")
	_SetLabelText(_groupGrid, "UnitPathsLabel", "막힘")
	_SetLabelText(_groupGrid, "SegmentJoinLabel", "대체 후보")
	_SetLabelText(_groupGrid, "WaypointJoinLabel", "정체 틱")
	_SetLabelText(_groupGrid, "FallbackLabel", "도착 처리")

	_SetLabelText(_gridVBox, "Heading", "이동 반복 실행")
	_SetLabelText(_grid, "CallsLabel", "실행")
	_SetLabelText(_grid, "ExpandedLabel", "완료")
	_SetLabelText(_grid, "RelaxedLabel", "시간 초과 / 실패")

	_SetLabelText(_worstVBox, "Heading", "가장 느린 이동 실행")
	_SetLabelText(_worstGrid, "TimeLabel", "시간")
	_SetLabelText(_worstGrid, "ExpandedLabel", "틱")
	_SetLabelText(_worstGrid, "RelaxedLabel", "막힘")
	_SetLabelText(_worstGrid, "TargetsLabel", "도착 처리")


func _ApplyPathBuildLabels() -> void:
	_SetLabelText(_executionVBox, "Heading", "실행 시간")
	_SetLabelText(_resultVBox, "Heading", "경로 생성 결과")
	_SetLabelText(_resultGrid, "PathSizeLabel", "평균 경유점 수")
	_SetLabelText(_resultGrid, "EmptyLabel", "빈 경로 / 초기 막힘")
	_SetLabelText(_resultGrid, "OverlapLabel", "경로 중복")
	_SetLabelText(_resultGrid, "PathLengthLabel", "평균 총 길이")

	_SetLabelText(_phaseVBox, "Heading", "경로 생성 구간")
	_SetLabelText(_phaseGrid, "StartAnchorLabel", "시작점 연결")
	_SetLabelText(_phaseGrid, "TargetAnchorLabel", "목표점 연결")
	_SetLabelText(_phaseGrid, "AnchorGraphLabel", "연결 그래프")
	_SetLabelText(_phaseGrid, "FallbackGridLabel", "대체 격자 탐색")

	_SetLabelText(_segmentVBox, "Heading", "구간 통과 검사")
	_SetLabelText(_segmentGrid, "TimeLabel", "시간")
	_SetLabelText(_segmentGrid, "CallsLabel", "호출")
	_SetLabelText(_segmentGrid, "AverageLabel", "평균")
	_SetLabelText(_segmentGrid, "StaticLabel", "정적 검사")

	_SetLabelText(_groupVBox, "Heading", "그룹 경로 생성")
	_SetLabelText(_groupGrid, "JoinPointLabel", "합류점")
	_SetLabelText(_groupGrid, "SharedPathLabel", "공통 경로")
	_SetLabelText(_groupGrid, "UnitPathsLabel", "개별 경로")
	_SetLabelText(_groupGrid, "SegmentJoinLabel", "구간 합류")
	_SetLabelText(_groupGrid, "WaypointJoinLabel", "경유점 합류")
	_SetLabelText(_groupGrid, "FallbackLabel", "대체 탐색")

	_SetLabelText(_gridVBox, "Heading", "격자 A* 탐색")
	_SetLabelText(_grid, "CallsLabel", "호출")
	_SetLabelText(_grid, "ExpandedLabel", "확장")
	_SetLabelText(_grid, "RelaxedLabel", "비용 갱신")

	_SetLabelText(_worstVBox, "Heading", "가장 느린 연결 탐색")
	_SetLabelText(_worstGrid, "TimeLabel", "시간")
	_SetLabelText(_worstGrid, "ExpandedLabel", "확장")
	_SetLabelText(_worstGrid, "RelaxedLabel", "비용 갱신")
	_SetLabelText(_worstGrid, "TargetsLabel", "목표 수")


func _SetLabelText(parent: Node, path: String, text: String) -> void:
	var label: Label = parent.get_node(NodePath(path))
	label.text = text


func _SetEmptyResult() -> void:
	for label: Label in [
		_avgValue,
		_p50Value,
		_p95Value,
		_maxValue,
		_pathSizeValue,
		_emptyPathsValue,
		_pathOverlapValue,
		_pathLengthValue,
		_startAnchorValue,
		_targetAnchorValue,
		_anchorGraphValue,
		_fallbackGridValue,
		_rebuildValue,
		_tickStatistics,
		_slowestTick,
		_gridCallsValue,
		_gridExpandedValue,
		_gridRelaxedValue,
		_segmentTimeValue,
		_segmentCallsValue,
		_segmentAverageValue,
		_staticChecksValue,
		_groupJoinPointValue,
		_groupSharedPathValue,
		_groupUnitPathsValue,
		_groupSegmentJoinValue,
		_groupWaypointJoinValue,
		_groupFallbackValue,
		_worstTimeValue,
		_worstExpandedValue,
		_worstRelaxedValue,
		_worstTargetsValue,
		_groupRadiusValue,
		_averageCenterDistanceValue,
		_targetDistanceValue,
	]:
		label.text = "-"

	for bar: ProgressBar in [
		_startAnchorBar,
		_targetAnchorBar,
		_anchorGraphBar,
		_fallbackGridBar,
		_rebuildBar,
	]:
		bar.max_value = 1.0
		bar.value = 0.0

	if not _HasModeResults(GetSelectedMode()):
		_statusLabel.text = "전체 실행을 눌러 측정하세요"


func _ClearModeResults(mode: int) -> void:
	if mode == Mode.MOVEMENT:
		_movementResultsByCase.clear()
	else:
		_pathResultsByCase.clear()


func _HasModeResults(mode: int) -> bool:
	return (
		not _movementResultsByCase.is_empty()
		if mode == Mode.MOVEMENT
		else not _pathResultsByCase.is_empty()
	)


func _GetSelectedCaseName() -> String:
	if _caseSelect.item_count <= 0 or _caseSelect.selected < 0:
		return ""

	return str(_caseSelect.get_item_metadata(_caseSelect.selected))


func _FormatDurationUsec(valueUsec: int) -> String:
	if valueUsec < 1000:
		return "%d us" % valueUsec

	var millisecondsTimesTen: int = Math.DivideInt(valueUsec, 100)
	var milliseconds: int = Math.DivideInt(millisecondsTimesTen, 10)
	var decimal: int = Math.RemainderInt(millisecondsTimesTen, 10)
	return "%d.%d ms" % [milliseconds, decimal]


func _UpdateResultDescription(
	pathSizeTotal: int,
	runCount: int,
	gridCallsTotal: int,
	startAnchorUsec: int,
	targetAnchorUsec: int,
	anchorGraphUsec: int,
	fallbackGridUsec: int,
) -> void:
	var hasPath: bool = pathSizeTotal > 0 and runCount > 0
	var usedMeasuredSearchPhase: bool = (
		gridCallsTotal > 0 or startAnchorUsec > 0 or targetAnchorUsec > 0
		or anchorGraphUsec > 0 or fallbackGridUsec > 0
	)

	if hasPath and not usedMeasuredSearchPhase:
		_statusLabel.text = "직선 경로 — A* / 연결 탐색 생략"
	else:
		_statusLabel.text = "측정 종료 — 사례를 선택하세요"


func _GetAverage(values: Array) -> int:
	if values.is_empty():
		return 0

	var total: int = 0
	for value: int in values:
		total += value

	return Math.DivideInt(total, values.size())


func _GetMetricAverageInt(metrics: Dictionary, key: String, count: int) -> int:
	if count <= 0:
		return 0

	return Math.DivideInt(int(metrics.get(key, 0)), count)


func _GetMetricAverageFloat(metrics: Dictionary, key: String, count: int) -> float:
	if count <= 0:
		return 0.0

	return float(metrics.get(key, 0)) / float(count)


static func GetCaseDisplayName(caseName: String) -> String:
	match caseName:
		"Group5_Close_FarTarget":
			return "5유닛 밀집 · 장거리"
		"Group5_Medium_FarTarget":
			return "5유닛 중간 간격 · 장거리"
		"Group5_Spread_FarTarget":
			return "5유닛 분산 · 장거리"
		"Group5_Spread_Inline_FarTarget":
			return "5유닛 종방향 분산 · 장거리"
		"Group5_Spread_Lateral_FarTarget":
			return "5유닛 횡방향 분산 · 장거리"
		"Group5_Close_InsideRadius":
			return "5유닛 밀집 · 반경 안쪽"
		"Group5_Close_RadiusInsideEdge":
			return "5유닛 밀집 · 반경 경계 안쪽"
		"Group5_Close_RadiusOutsideEdge":
			return "5유닛 밀집 · 반경 경계 바깥"
	return caseName
