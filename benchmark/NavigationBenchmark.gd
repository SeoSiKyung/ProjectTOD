extends Node2D

const PORTAL_COMPARISON = preload("res://benchmark/NavigationPortalComparison.gd")

const PATH_WARMUP_COUNT: int = 3
const PATH_MEASUREMENT_COUNT: int = 25

const MOVEMENT_WARMUP_COUNT: int = 1
const MOVEMENT_MEASUREMENT_COUNT: int = 10

const SELECTED_PATH_WARMUP_COUNT: int = 1
const SELECTED_PATH_MEASUREMENT_COUNT: int = 3

const SELECTED_MOVEMENT_WARMUP_COUNT: int = 1
const SELECTED_MOVEMENT_MEASUREMENT_COUNT: int = 3

const MOVEMENT_MAX_TICKS: int = 1000
const MOVEMENT_FIXED_DELTA: float = 1.0 / 60.0
const MOVEMENT_SPEED: float = 96.0

@export var enableDiagnostics: bool = true
@export var enablePathRebuildRecovery: bool = true
@export var enableStaticQueryDetails: bool = true
@export var enablePortalBatchDetails: bool = true
@export var comparePortalHeuristicWeights: bool = true
@export var sourceCommitOverride: String = ""

const DIAGNOSTICS_REVISION: String = "observability-v1"
const DIAGNOSTIC_STALL_TICKS: int = 30
const DIAGNOSTIC_STALL_DISTANCE_SQUARED: float = 0.000001
var _report: Dictionary = { }

@export var navigationData: NavigationData
var _navigationService: NavigationService
var _isRunning: bool = false

@onready var _benchmarkUI: NavigationBenchmarkUI = $CanvasLayer/BenchmarkUI

var _cases: Array[NavigationBenchmarkCase] = NavigationBenchmarkCase.CreateCases()


class BenchmarkRunResult:
	var elapsedUsec: int = 0
	var pathSize: int = 0
	var pathLengthTotal: int = 0
	var emptyPathCount: int = 0
	var overlapCellCount: int = 0
	var comparedCellCount: int = 0
	var metrics: Dictionary = { }
	var staticQueryDetails: Dictionary = { }
	var portalBatchDetails: Dictionary = { }


class MovementRunResult:
	var elapsedUsec: int = 0
	var commandUsec: int = 0
	var movementUsec: int = 0
	var tickCount: int = 0
	var completedUnitCount: int = 0
	var expectedUnitCount: int = 0
	var targetErrorTotal: float = 0.0
	var targetErrorSampleCount: int = 0
	var succeeded: bool = false
	var timedOut: bool = false
	var errorMessage: String = ""
	var navigationMetrics: Dictionary = { }
	var movementMetrics: Dictionary = { }
	var commandMetrics: Dictionary = { }
	var commandStaticQueryDetails: Dictionary = { }
	var movementStaticQueryDetails: Dictionary = { }
	var commandPortalBatchDetails: Dictionary = { }
	var movementPortalBatchDetails: Dictionary = { }
	var tickTimesUsec: Array[int] = []
	var worstTick: Dictionary = { }
	var firstStalls: Array[Dictionary] = []
	var unfinishedAgents: Array[Dictionary] = []


class PathOverlapResult:
	var overlapCellCount: int = 0
	var comparedCellCount: int = 0


func _ready() -> void:
	_navigationService = NavigationService.new()
	_navigationService.navigationData = navigationData
	_navigationService.Ready()

	_benchmarkUI.SetImplementationLabel("portal-weighted-v1")
	_benchmarkUI.SetCases(_cases)
	_benchmarkUI.RunAllRequested.connect(_RunAllBenchmarks)
	_benchmarkUI.RunSelectedRequested.connect(_RunSelectedBenchmark)
	_benchmarkUI.show()


func _draw() -> void:
	for benchmarkCase: NavigationBenchmarkCase in _cases:
		draw_circle(benchmarkCase.target, 12.0, Color.RED)

		match benchmarkCase.type:
			NavigationBenchmarkCase.Type.SINGLE_PATH:
				draw_circle(benchmarkCase.start, 12.0, Color.WHITE)
				draw_line(benchmarkCase.start, benchmarkCase.target, Color.YELLOW, 2.0)

			NavigationBenchmarkCase.Type.GROUP_PATHS:
				for unitStart: Vector2 in benchmarkCase.unitStarts:
					draw_circle(unitStart, 8.0, Color.WHITE)

				if not benchmarkCase.unitStarts.is_empty():
					var center: Vector2 = _GetGroupCenter(benchmarkCase.unitStarts)
					draw_circle(center, 6.0, Color.YELLOW)
					draw_line(center, benchmarkCase.target, Color.YELLOW, 2.0)


func _RunAllBenchmarks(mode: int) -> void:
	if mode == NavigationBenchmarkUI.Mode.PORTAL_COMPARISON:
		await _RunPortalComparison(-1)
		return
	if _isRunning:
		return

	_isRunning = true
	_BeginReport(mode, true)
	_benchmarkUI.SetRunning(true, mode)

	await get_tree().process_frame

	for benchmarkCase: NavigationBenchmarkCase in _cases:
		match mode:
			NavigationBenchmarkUI.Mode.MOVEMENT:
				_RunMovementBenchmark(benchmarkCase)
			_:
				_RunPathBenchmark(benchmarkCase)

		await get_tree().process_frame

	_benchmarkUI.SetRunning(false, mode)
	_SaveReport()
	_isRunning = false


func _RunSelectedBenchmark(mode: int, caseIndex: int) -> void:
	if mode == NavigationBenchmarkUI.Mode.PORTAL_COMPARISON:
		await _RunPortalComparison(caseIndex)
		return
	if _isRunning:
		return

	if caseIndex < 0 or caseIndex >= _cases.size():
		return

	_isRunning = true
	_BeginReport(mode, false)
	_benchmarkUI.SetRunning(true, mode, false)

	await get_tree().process_frame

	var benchmarkCase: NavigationBenchmarkCase = _cases[caseIndex]

	match mode:
		NavigationBenchmarkUI.Mode.MOVEMENT:
			_RunMovementBenchmark(
				benchmarkCase,
				SELECTED_MOVEMENT_WARMUP_COUNT,
				SELECTED_MOVEMENT_MEASUREMENT_COUNT,
			)
		_:
			_RunPathBenchmark(
				benchmarkCase,
				SELECTED_PATH_WARMUP_COUNT,
				SELECTED_PATH_MEASUREMENT_COUNT,
			)

	await get_tree().process_frame

	_benchmarkUI.SetRunning(false, mode, false)
	_SaveReport()
	_isRunning = false


func _RunPathBenchmark(
	benchmarkCase: NavigationBenchmarkCase,
	warmupCount: int = PATH_WARMUP_COUNT,
	measurementCount: int = PATH_MEASUREMENT_COUNT,
) -> void:
	if not _ValidateBenchmarkCase(benchmarkCase):
		return

	for i: int in range(warmupCount):
		_RunPathFinding(benchmarkCase)

	var results: Array[BenchmarkRunResult] = []
	for i: int in range(measurementCount):
		results.append(_RunPathFinding(benchmarkCase))

	_ShowPathResult(benchmarkCase, results)
	var runs: Array[Dictionary] = []
	for result: BenchmarkRunResult in results:
		runs.append(
			{
				"elapsed_usec": result.elapsedUsec,
				"path_size": result.pathSize,
				"path_length_total": result.pathLengthTotal,
				"empty_path_count": result.emptyPathCount,
				"overlap_cell_count": result.overlapCellCount,
				"compared_cell_count": result.comparedCellCount,
				"navigation_metrics_nested": result.metrics,
				"static_query_details": result.staticQueryDetails,
				"portal_batch_details": result.portalBatchDetails,
			}
		)
	_AppendCaseReport(benchmarkCase, runs, warmupCount)


func _RunMovementBenchmark(
	benchmarkCase: NavigationBenchmarkCase,
	warmupCount: int = MOVEMENT_WARMUP_COUNT,
	measurementCount: int = MOVEMENT_MEASUREMENT_COUNT,
) -> void:
	if benchmarkCase.type != NavigationBenchmarkCase.Type.GROUP_PATHS:
		return
	if not _ValidateBenchmarkCase(benchmarkCase):
		return

	for i: int in range(warmupCount):
		_RunMovement(benchmarkCase)

	var results: Array[MovementRunResult] = []
	for i: int in range(measurementCount):
		results.append(_RunMovement(benchmarkCase))

	_ShowMovementResult(benchmarkCase, results)
	var runs: Array[Dictionary] = []
	for result: MovementRunResult in results:
		var correctionUsec: int = int(
			result.commandMetrics.get("command_target_correction_usec", 0)
		)
		var buildUsec: int = int(result.commandMetrics.get("command_build_paths_usec", 0))
		var assignmentUsec: int = int(result.commandMetrics.get("command_assignment_usec", 0))
		var commandPhases: Dictionary = { }
		if enableDiagnostics:
			commandPhases = {
				"target_correction_usec": correctionUsec,
				"build_paths_usec": buildUsec,
				"agent_assignment_usec": assignmentUsec,
				"group_and_other_usec": result.commandUsec - correctionUsec
				- buildUsec - assignmentUsec,
			}
		var tickTotal: int = 0
		for tickUsec: int in result.tickTimesUsec:
			tickTotal += tickUsec
		runs.append(
			{
				"elapsed_usec": result.elapsedUsec,
				"command_process_usec": result.commandUsec,
				"command_exclusive_phases": commandPhases,
				"command_navigation_metrics_nested": result.commandMetrics,
				"command_static_query_details": result.commandStaticQueryDetails,
				"movement_static_query_details": result.movementStaticQueryDetails,
				"command_portal_batch_details": result.commandPortalBatchDetails,
				"movement_portal_batch_details": result.movementPortalBatchDetails,
				"movement_loop_usec": result.movementUsec,
				"tick_times_usec": result.tickTimesUsec,
				"tick_statistics": _TimeStatistics(result.tickTimesUsec),
				"loop_and_diagnostic_overhead_usec": result.movementUsec - tickTotal if enableDiagnostics else null,
				"worst_tick": result.worstTick,
				"first_stalls": result.firstStalls,
				"unfinished_agents": result.unfinishedAgents,
				"tick_count": result.tickCount,
				"completed": result.completedUnitCount,
				"expected": result.expectedUnitCount,
				"average_agent_target_error": (
					result.targetErrorTotal / float(result.targetErrorSampleCount)
					if result.targetErrorSampleCount > 0
					else null
				),
				"succeeded": result.succeeded,
				"timed_out": result.timedOut,
				"error": result.errorMessage,
				"movement_navigation_metrics_nested": result.navigationMetrics,
				"movement_metrics_nested": result.movementMetrics,
			}
		)
	_AppendCaseReport(benchmarkCase, runs, warmupCount)


func _ValidateBenchmarkCase(benchmarkCase: NavigationBenchmarkCase) -> bool:
	match benchmarkCase.type:
		NavigationBenchmarkCase.Type.SINGLE_PATH:
			if not _navigationService.CanPlaceStatic(benchmarkCase.start, benchmarkCase.halfSize):
				push_error(
					"Invalid benchmark start: %s / %s"
					% [benchmarkCase.caseName, benchmarkCase.start]
				)
				return false

		NavigationBenchmarkCase.Type.GROUP_PATHS:
			if benchmarkCase.unitStarts.is_empty():
				push_error("Benchmark has no unit starts: %s" % benchmarkCase.caseName)
				return false

			var isValid: bool = true

			for unitStart: Vector2 in benchmarkCase.unitStarts:
				if _navigationService.CanPlaceStatic(unitStart, benchmarkCase.halfSize):
					continue

				push_error(
					"Invalid benchmark unit start: %s / %s" % [benchmarkCase.caseName, unitStart]
				)
				isValid = false

			if not _navigationService.CanPlaceStatic(benchmarkCase.target, benchmarkCase.halfSize):
				push_error(
					"Invalid benchmark group target: %s / %s"
					% [benchmarkCase.caseName, benchmarkCase.target]
				)
				isValid = false

			if not isValid:
				return false

	return true


func _RunPathFinding(benchmarkCase: NavigationBenchmarkCase) -> BenchmarkRunResult:
	# 동일 요청 반복으로 Anchor Connection Cache가 측정값을 가리지 않도록 요청 캐시만 제거한다.
	_navigationService.ClearBenchmarkRequestCache()

	var metrics: NavigationProfileMetrics = NavigationProfileMetrics.new()
	metrics.captureStaticQueryDetails = enableDiagnostics and enableStaticQueryDetails
	metrics.capturePortalBatchDetails = enableDiagnostics and enablePortalBatchDetails
	_navigationService.SetProfileMetrics(metrics)

	var result: BenchmarkRunResult = BenchmarkRunResult.new()

	var startTime: int = Time.get_ticks_usec()

	match benchmarkCase.type:
		NavigationBenchmarkCase.Type.SINGLE_PATH:
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

			result.elapsedUsec = Time.get_ticks_usec() - startTime

			result.pathSize = path.size()
			if path.is_empty():
				result.emptyPathCount = 1

		NavigationBenchmarkCase.Type.GROUP_PATHS:
			var paths: Array[PackedVector2Array] = _navigationService.BuildPaths(
				benchmarkCase.unitStarts,
				benchmarkCase.target,
				benchmarkCase.halfSize,
			)

			result.elapsedUsec = Time.get_ticks_usec() - startTime

			for index: int in range(paths.size()):
				var path: PackedVector2Array = paths[index]

				result.pathSize += path.size()
				result.pathLengthTotal += _GetPathLength(benchmarkCase.unitStarts[index], path)

				if path.is_empty():
					result.emptyPathCount += 1

			var overlapResult: PathOverlapResult = _MeasurePathOverlap(
				benchmarkCase.unitStarts,
				paths,
			)

			result.overlapCellCount = overlapResult.overlapCellCount
			result.comparedCellCount = overlapResult.comparedCellCount

	_navigationService.ClearProfileMetrics()

	result.metrics = metrics.ToDictionary()
	result.staticQueryDetails = metrics.GetStaticQueryDetails()
	result.portalBatchDetails = metrics.GetPortalBatchDetails()

	return result


func _RunMovement(benchmarkCase: NavigationBenchmarkCase) -> MovementRunResult:
	var result: MovementRunResult = MovementRunResult.new()
	result.expectedUnitCount = benchmarkCase.unitStarts.size()

	_navigationService.ClearBenchmarkRequestCache()

	var movementSimulator: MovementSimulator = MovementSimulator.new(_navigationService)
	var snapshot: StageSnapshot = StageSnapshot.new(maxi(1, benchmarkCase.unitStarts.size()))
	var movementMetrics: MovementProfileMetrics = MovementProfileMetrics.new()
	var agents: Array[MovementAgent] = []
	var unitIds: PackedInt32Array = []

	movementSimulator.SetProfileMetrics(movementMetrics)
	movementSimulator.captureDiagnostics = enableDiagnostics
	movementSimulator.enablePathRebuildRecovery = enablePathRebuildRecovery

	for index: int in range(benchmarkCase.unitStarts.size()):
		var agent: MovementAgent = MovementAgent.new(
			index,
			benchmarkCase.unitStarts[index],
			MOVEMENT_SPEED,
			benchmarkCase.halfSize,
		)

		if not movementSimulator.RegisterAgent(agent):
			result.errorMessage = "Failed to register movement agent %d" % index
			_ClearProfileMetrics(movementSimulator)
			return result

		snapshot.RegisterUnit(index, benchmarkCase.unitStarts[index], benchmarkCase.halfSize)
		if not snapshot.HasUnit(index):
			result.errorMessage = "Failed to register snapshot unit %d" % index
			_ClearProfileMetrics(movementSimulator)
			return result

		agents.append(agent)
		unitIds.append(index)

	var commandMetrics: NavigationProfileMetrics = NavigationProfileMetrics.new()
	commandMetrics.captureStaticQueryDetails = enableDiagnostics and enableStaticQueryDetails
	commandMetrics.capturePortalBatchDetails = enableDiagnostics and enablePortalBatchDetails
	_navigationService.SetProfileMetrics(commandMetrics)

	var commandProcessor: MoveCommandProcessor = MoveCommandProcessor.new(
		_navigationService,
		movementSimulator,
	)
	commandProcessor.profileMetrics = commandMetrics if enableDiagnostics else null
	var command: MoveCommand = MoveCommand.new(unitIds, benchmarkCase.target)

	var startTime: int = Time.get_ticks_usec()
	var commandSucceeded: bool = commandProcessor.Process(command, snapshot)
	result.commandUsec = Time.get_ticks_usec() - startTime

	if not commandSucceeded:
		result.commandMetrics = commandMetrics.ToDictionary()
		result.commandStaticQueryDetails = commandMetrics.GetStaticQueryDetails()
		result.commandPortalBatchDetails = commandMetrics.GetPortalBatchDetails()
		result.elapsedUsec = result.commandUsec
		result.errorMessage = "MoveCommandProcessor failed"
		if enableDiagnostics:
			result.unfinishedAgents = _CaptureAgentStates(
				movementSimulator,
				agents,
				benchmarkCase.target,
				true,
			)
		_ClearProfileMetrics(movementSimulator)
		return result

	var movementNavigationMetrics: NavigationProfileMetrics = NavigationProfileMetrics.new()
	movementNavigationMetrics.captureStaticQueryDetails = (
		enableDiagnostics and enableStaticQueryDetails
	)
	movementNavigationMetrics.capturePortalBatchDetails = (
		enableDiagnostics and enablePortalBatchDetails
	)
	_navigationService.SetProfileMetrics(movementNavigationMetrics)

	var noMovementTicks: PackedInt32Array = PackedInt32Array()
	noMovementTicks.resize(agents.size())
	noMovementTicks.fill(0)
	var rebuildBefore: int = 0
	var captureBefore: int = 0
	var collisionBefore: int = 0
	var commitBefore: int = 0
	var arrivalBefore: int = 0
	var tickStart: int = 0
	startTime = Time.get_ticks_usec()
	while result.tickCount < MOVEMENT_MAX_TICKS and not _AreAllAgentsSettled(agents):
		if movementNavigationMetrics.capturePortalBatchDetails:
			movementNavigationMetrics.portalBatchTick = result.tickCount + 1
		if movementNavigationMetrics.captureStaticQueryDetails:
			movementNavigationMetrics.staticQueryTick = result.tickCount + 1
		if enableDiagnostics:
			rebuildBefore = movementMetrics.pathRebuildUsec
			captureBefore = movementMetrics.captureTickUsec
			collisionBefore = movementMetrics.collisionResolveUsec
			commitBefore = movementMetrics.commitTickUsec
			arrivalBefore = movementMetrics.arrivalResolveUsec
			tickStart = Time.get_ticks_usec()
		var tickSucceeded: bool = movementSimulator.SimulateTick(snapshot, MOVEMENT_FIXED_DELTA)
		if enableDiagnostics:
			var tickUsec: int = Time.get_ticks_usec() - tickStart
			result.tickTimesUsec.append(tickUsec)
			if result.worstTick.is_empty() or tickUsec > int(result.worstTick["elapsed_usec"]):
				var rebuildUsec: int = movementMetrics.pathRebuildUsec - rebuildBefore
				var captureUsec: int = movementMetrics.captureTickUsec - captureBefore
				var collisionUsec: int = movementMetrics.collisionResolveUsec - collisionBefore
				var commitUsec: int = movementMetrics.commitTickUsec - commitBefore
				var arrivalUsec: int = movementMetrics.arrivalResolveUsec - arrivalBefore
				result.worstTick = {
					"tick": result.tickCount + 1,
					"elapsed_usec": tickUsec,
					"succeeded": tickSucceeded,
					"exclusive_phases": {
						"path_rebuild_usec": rebuildUsec,
						"capture_usec": captureUsec,
						"collision_resolve_usec": collisionUsec,
						"commit_usec": commitUsec,
						"arrival_resolve_usec": arrivalUsec,
						"other_usec": tickUsec - rebuildUsec - captureUsec
						- collisionUsec - commitUsec - arrivalUsec,
					},
					"agents_after_tick": _CaptureAgentStates(
						movementSimulator,
						agents,
						benchmarkCase.target,
					),
				}
			if tickSucceeded:
				_RecordFirstStalls(
					result,
					movementSimulator,
					agents,
					noMovementTicks,
					benchmarkCase.target,
				)
		if not tickSucceeded:
			result.errorMessage = movementSimulator.lastError
			break

		result.tickCount += 1

	result.movementUsec = Time.get_ticks_usec() - startTime
	result.elapsedUsec = result.commandUsec + result.movementUsec

	for agent: MovementAgent in agents:
		if agent.isSettled:
			result.completedUnitCount += 1
		result.targetErrorTotal += agent.position.distance_to(agent.moveTarget)
		result.targetErrorSampleCount += 1

	result.timedOut = (
		result.errorMessage.is_empty() and result.completedUnitCount < result.expectedUnitCount
		and result.tickCount >= MOVEMENT_MAX_TICKS
	)
	result.succeeded = (
		result.errorMessage.is_empty() and not result.timedOut
		and result.completedUnitCount == result.expectedUnitCount
	)

	if enableDiagnostics:
		result.unfinishedAgents = _CaptureAgentStates(
			movementSimulator,
			agents,
			benchmarkCase.target,
			true,
		)
	result.commandMetrics = commandMetrics.ToDictionary()
	result.commandStaticQueryDetails = commandMetrics.GetStaticQueryDetails()
	result.movementStaticQueryDetails = movementNavigationMetrics.GetStaticQueryDetails()
	result.commandPortalBatchDetails = commandMetrics.GetPortalBatchDetails()
	result.movementPortalBatchDetails = movementNavigationMetrics.GetPortalBatchDetails()
	result.navigationMetrics = movementNavigationMetrics.ToDictionary()
	result.movementMetrics = movementMetrics.ToDictionary()

	_ClearProfileMetrics(movementSimulator)

	return result


func _ClearProfileMetrics(movementSimulator: MovementSimulator) -> void:
	movementSimulator.ClearProfileMetrics()
	_navigationService.ClearProfileMetrics()


func _AreAllAgentsSettled(agents: Array[MovementAgent]) -> bool:
	if agents.is_empty():
		return false

	for agent: MovementAgent in agents:
		if not agent.isSettled:
			return false

	return true


#region Metrics

func _GetPathLength(start: Vector2, path: PackedVector2Array) -> int:
	if path.is_empty():
		return 0

	var totalLength: float = 0.0
	var previous: Vector2 = start
	for point: Vector2 in path:
		totalLength += previous.distance_to(point)
		previous = point

	return roundi(totalLength)


func _MeasurePathOverlap(
	unitStarts: PackedVector2Array,
	paths: Array[PackedVector2Array],
) -> PathOverlapResult:
	var result: PathOverlapResult = PathOverlapResult.new()
	if paths.size() != unitStarts.size():
		return result

	var pathCellsByUnit: Array[Dictionary] = []
	for index: int in range(paths.size()):
		var pathCells: Dictionary = { }
		_AppendPathCells(pathCells, unitStarts[index], paths[index])
		pathCellsByUnit.append(pathCells)

	for firstIndex: int in range(pathCellsByUnit.size()):
		for secondIndex: int in range(firstIndex + 1, pathCellsByUnit.size()):
			var firstCells: Dictionary = pathCellsByUnit[firstIndex]
			var secondCells: Dictionary = pathCellsByUnit[secondIndex]
			var comparableCellCount: int = mini(firstCells.size(), secondCells.size())
			if comparableCellCount <= 0:
				continue

			result.comparedCellCount += comparableCellCount
			result.overlapCellCount += _CountSharedCells(firstCells, secondCells)

	return result


func _AppendPathCells(pathCells: Dictionary, start: Vector2, path: PackedVector2Array) -> void:
	if path.is_empty():
		return

	var segmentStart: Vector2 = start
	for segmentEnd: Vector2 in path:
		_AppendSegmentCells(pathCells, segmentStart, segmentEnd)
		segmentStart = segmentEnd


func _AppendSegmentCells(pathCells: Dictionary, start: Vector2, end: Vector2) -> void:
	var startCell: Vector2i = _navigationService.WorldToCell(start)
	var endCell: Vector2i = _navigationService.WorldToCell(end)

	var x: int = startCell.x
	var y: int = startCell.y
	var deltaX: int = absi(endCell.x - startCell.x)
	var deltaY: int = -absi(endCell.y - startCell.y)
	var stepX: int = 1 if startCell.x < endCell.x else -1
	var stepY: int = 1 if startCell.y < endCell.y else -1
	var error: int = deltaX + deltaY

	while true:
		pathCells[Vector2i(x, y)] = true
		if x == endCell.x and y == endCell.y:
			break

		var doubleError: int = error * 2
		if doubleError >= deltaY:
			error += deltaY
			x += stepX
		if doubleError <= deltaX:
			error += deltaX
			y += stepY


func _CountSharedCells(firstCells: Dictionary, secondCells: Dictionary) -> int:
	var smallerCells: Dictionary = firstCells
	var largerCells: Dictionary = secondCells
	if firstCells.size() > secondCells.size():
		smallerCells = secondCells
		largerCells = firstCells

	var sharedCount: int = 0
	for cell: Vector2i in smallerCells:
		if largerCells.has(cell):
			sharedCount += 1

	return sharedCount


func _GetGroupCenter(unitStarts: PackedVector2Array) -> Vector2:
	var center: Vector2 = Vector2.ZERO
	for unitStart: Vector2 in unitStarts:
		center += unitStart

	return center / float(unitStarts.size())


func _GetGroupRadius(unitStarts: PackedVector2Array, center: Vector2) -> int:
	var maxDistanceSquared: float = 0.0
	for unitStart: Vector2 in unitStarts:
		maxDistanceSquared = maxf(maxDistanceSquared, center.distance_squared_to(unitStart))

	return roundi(sqrt(maxDistanceSquared))


func _GetAverageCenterDistance(unitStarts: PackedVector2Array, center: Vector2) -> int:
	var totalDistance: int = 0
	for unitStart: Vector2 in unitStarts:
		totalDistance += roundi(center.distance_to(unitStart))

	return Math.DivideInt(totalDistance, unitStarts.size())


func _AccumulateMetrics(totals: Dictionary, metrics: Dictionary) -> void:
	for key: String in metrics:
		totals[key] = int(totals.get(key, 0)) + int(metrics[key])

#endregion


func _ShowPathResult(
	benchmarkCase: NavigationBenchmarkCase,
	results: Array[BenchmarkRunResult],
) -> void:
	var elapsedTimes: Array[int] = []
	var metricTotals: Dictionary = { }

	var pathSizeTotal: int = 0
	var emptyPathCount: int = 0
	var overlapCellTotal: int = 0
	var comparedCellTotal: int = 0
	var pathLengthTotal: int = 0

	for result: BenchmarkRunResult in results:
		elapsedTimes.append(result.elapsedUsec)
		pathSizeTotal += result.pathSize
		emptyPathCount += result.emptyPathCount
		overlapCellTotal += result.overlapCellCount
		comparedCellTotal += result.comparedCellCount
		pathLengthTotal += result.pathLengthTotal

		_AccumulateMetrics(metricTotals, result.metrics)

	elapsedTimes.sort()

	var groupInput: Dictionary = _GetGroupInputMetrics(benchmarkCase)

	_benchmarkUI.ShowPathResult(
		benchmarkCase.caseName,
		elapsedTimes,
		metricTotals,
		pathSizeTotal,
		emptyPathCount,
		overlapCellTotal,
		comparedCellTotal,
		pathLengthTotal,
		results.size(),
		_GetWorstAnchorBatchMetrics(results),
		int(groupInput["radius"]),
		int(groupInput["averageCenterDistance"]),
		int(groupInput["targetDistance"]),
	)


func _ShowMovementResult(
	benchmarkCase: NavigationBenchmarkCase,
	results: Array[MovementRunResult],
) -> void:
	var elapsedTimes: Array[int] = []
	var commandTimes: Array[int] = []
	var movementTimes: Array[int] = []
	var navigationMetricTotals: Dictionary = { }
	var movementMetricTotals: Dictionary = { }
	var measuredTickTimes: Array[int] = []
	var slowestTick: Dictionary = { }
	var runNumber: int = 0

	var tickTotal: int = 0
	var completedUnitTotal: int = 0
	var expectedUnitTotal: int = 0
	var targetErrorTotal: float = 0.0
	var targetErrorSampleCount: int = 0
	var succeededRunCount: int = 0
	var timedOutRunCount: int = 0
	var failedRunCount: int = 0

	for result: MovementRunResult in results:
		runNumber += 1
		measuredTickTimes.append_array(result.tickTimesUsec)
		if not result.worstTick.is_empty():
			if (
				slowestTick.is_empty()
				or int(result.worstTick["elapsed_usec"]) > int(slowestTick["elapsed_usec"])
			):
				slowestTick = {
					"run": runNumber,
					"tick": result.worstTick["tick"],
					"elapsed_usec": result.worstTick["elapsed_usec"],
					"rebuild_usec": result.worstTick["exclusive_phases"].get("path_rebuild_usec", 0),
				}
		elapsedTimes.append(result.elapsedUsec)
		commandTimes.append(result.commandUsec)
		movementTimes.append(result.movementUsec)
		tickTotal += result.tickCount
		completedUnitTotal += result.completedUnitCount
		expectedUnitTotal += result.expectedUnitCount
		targetErrorTotal += result.targetErrorTotal
		targetErrorSampleCount += result.targetErrorSampleCount

		if result.succeeded:
			succeededRunCount += 1
		elif result.timedOut:
			timedOutRunCount += 1
		else:
			failedRunCount += 1

		_AccumulateMetrics(navigationMetricTotals, result.navigationMetrics)
		_AccumulateMetrics(movementMetricTotals, result.movementMetrics)

	elapsedTimes.sort()
	commandTimes.sort()
	movementTimes.sort()

	var groupInput: Dictionary = _GetGroupInputMetrics(benchmarkCase)
	var worstRun: MovementRunResult = _GetWorstMovementRun(results)
	var worstRunData: Dictionary = { }

	if worstRun != null:
		worstRunData = {
			"elapsedUsec": worstRun.elapsedUsec,
			"ticks": worstRun.tickCount,
			"completed": worstRun.completedUnitCount,
			"expected": worstRun.expectedUnitCount,
			"dynamicBlockedCandidates": int(
				worstRun.movementMetrics.get("dynamic_blocked_candidates", 0)
			),
		}

	_benchmarkUI.ShowMovementResult(
		benchmarkCase.caseName,
		{
			"elapsedTimes": elapsedTimes,
			"commandTimes": commandTimes,
			"movementTimes": movementTimes,
			"tickStatistics": _TimeStatistics(measuredTickTimes),
			"slowestTick": slowestTick,
			"navigationMetrics": navigationMetricTotals,
			"movementMetrics": movementMetricTotals,
			"tickTotal": tickTotal,
			"completedUnitTotal": completedUnitTotal,
			"expectedUnitTotal": expectedUnitTotal,
			"targetErrorTotal": targetErrorTotal,
			"targetErrorSampleCount": targetErrorSampleCount,
			"runCount": results.size(),
			"succeededRunCount": succeededRunCount,
			"timedOutRunCount": timedOutRunCount,
			"failedRunCount": failedRunCount,
			"worstRun": worstRunData,
			"groupRadius": int(groupInput["radius"]),
			"averageCenterDistance": int(groupInput["averageCenterDistance"]),
			"targetDistance": int(groupInput["targetDistance"]),
		},
	)


func _GetGroupInputMetrics(benchmarkCase: NavigationBenchmarkCase) -> Dictionary:
	if benchmarkCase.type != NavigationBenchmarkCase.Type.GROUP_PATHS:
		return { "radius": -1, "averageCenterDistance": -1, "targetDistance": -1 }

	var center: Vector2 = _GetGroupCenter(benchmarkCase.unitStarts)
	return {
		"radius": _GetGroupRadius(benchmarkCase.unitStarts, center),
		"averageCenterDistance": _GetAverageCenterDistance(benchmarkCase.unitStarts, center),
		"targetDistance": roundi(center.distance_to(benchmarkCase.target)),
	}


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


func _GetWorstMovementRun(results: Array[MovementRunResult]) -> MovementRunResult:
	var worstResult: MovementRunResult = null

	for result: MovementRunResult in results:
		if worstResult == null or result.elapsedUsec > worstResult.elapsedUsec:
			worstResult = result

	return worstResult


#region Observation only

func _CaptureAgentStates(
	simulator: MovementSimulator,
	agents: Array[MovementAgent],
	originalTarget: Vector2,
	onlyUnfinished: bool = false,
) -> Array[Dictionary]:
	var states: Array[Dictionary] = []
	for agent: MovementAgent in agents:
		if onlyUnfinished and agent.isSettled:
			continue
		var state: Dictionary = simulator.GetDiagnosticState(agent.unitId)
		state["original_command_target"] = [originalTarget.x, originalTarget.y]
		states.append(state)
	return states


func _RecordFirstStalls(
	result: MovementRunResult,
	simulator: MovementSimulator,
	agents: Array[MovementAgent],
	noMovementTicks: PackedInt32Array,
	originalTarget: Vector2,
) -> void:
	for index: int in range(agents.size()):
		var agent: MovementAgent = agents[index]
		if (
			agent.isSettled or agent.isPaused or agent.moveCommandId < 0 or agent.moveSpeed <= 0
			or agent.lastMoveDelta.length_squared() > DIAGNOSTIC_STALL_DISTANCE_SQUARED
		):
			noMovementTicks[index] = 0
			continue
		noMovementTicks[index] += 1
		if noMovementTicks[index] != DIAGNOSTIC_STALL_TICKS:
			continue
		var alreadyRecorded: bool = false
		for previous: Dictionary in result.firstStalls:
			if int(previous["unit_id"]) == agent.unitId:
				alreadyRecorded = true
				break
		if alreadyRecorded:
			continue
		var state: Dictionary = simulator.GetDiagnosticState(agent.unitId)
		state["original_command_target"] = [originalTarget.x, originalTarget.y]
		state["tick"] = result.tickCount + 1
		state["consecutive_no_displacement_ticks"] = noMovementTicks[index]
		result.firstStalls.append(state)


func _TimeStatistics(samples: Array[int]) -> Dictionary:
	if samples.is_empty():
		return { }
	var sorted: Array[int] = samples.duplicate()
	sorted.sort()
	var total: int = 0
	for value: int in sorted:
		total += value
	return {
		"count": sorted.size(),
		"average_usec": float(total) / float(sorted.size()),
		"p50_usec": Math.Percentile(sorted, 50),
		"p95_usec": Math.Percentile(sorted, 95),
		"max_usec": sorted.back(),
	}


func _BeginReport(mode: int, isRunAll: bool) -> void:
	_report = {
		"schema": DIAGNOSTICS_REVISION,
		"change_revision": "portal-weighted-v1",
		"portal_path_strategy": "목표별 개별 탐색. 복수 목표와 단일 목표 가중치 1.5. 기존 탐색 경계 유지. 경로 길이 증가를 허용하여 탐색량 감소.",
		"navigation_source_sha256": {
			"NavigationService.gd": FileAccess.get_sha256(
				"res://scripts/navigation/NavigationService.gd"
			),
			"NavigationGridPathfinder.gd": FileAccess.get_sha256(
				"res://scripts/navigation/NavigationGridPathfinder.gd"
			),
		},
		"heap_implementation": "IntHeap / 정수 배열 / 빈자리 이동 정렬 / 양방향 갱신",
		"heap_comparison": "f → 회전 비용 → h → 인덱스. 기존 EPSILON 비교 유지",
		"heap_source_sha256": {
			"IntHeap.gd": FileAccess.get_sha256("res://scripts/common/dataStructures/IntHeap.gd"),
			"NavigationPathHeap.gd": FileAccess.get_sha256(
				"res://scripts/navigation/NavigationPathHeap.gd"
			),
		},
		"report_language": "ko",
		"display_revision": "movement-display-ko-v2",
		"grid_batch_details_enabled": enableDiagnostics and enablePortalBatchDetails,
		"portal_batch_details_enabled": enableDiagnostics and enablePortalBatchDetails,
		"static_row_pruning_enabled": true,
		"static_query_details_enabled": enableDiagnostics and enableStaticQueryDetails,
		"path_rebuild_recovery_enabled": enablePathRebuildRecovery,
		"reached_waypoint_advance_enabled": true,
		"rebuild_policy": "이동 명령당 유닛별 개별 재탐색 1회, 틱당 새 요청 최대 1회. 기존 Agent 목표를 유지하며 목표 보정은 하지 않습니다.",
		"source": _ReadSourceCommit(),
		"working_tree_note": "changes(4).diff 기준. 검증한 목표별 개별 탐색을 Portal 연결의 기본 방식으로 적용했습니다. Git HEAD만으로 미커밋 변경을 식별할 수 없으므로 길찾기 소스 해시를 함께 기록합니다.",
		"timestamp": Time.get_datetime_string_from_system(),
		"mode": "Movement" if mode == NavigationBenchmarkUI.Mode.MOVEMENT else "PathBuild",
		"selection": "Run All" if isRunAll else "Run Selected",
		"expected_case_count": _cases.size() if isRunAll else 1,
		"diagnostics_enabled": enableDiagnostics,
		"existing_navigation_and_movement_profiling_enabled": true,
		"scene": "res://benchmark/NavigationBenchmark.tscn",
		"navigation_data": navigationData.resource_path,
		"navigation_data_sha256": FileAccess.get_sha256(navigationData.resource_path),
		"engine": Engine.get_version_info(),
		"os": OS.get_name(),
		"debug_build": OS.is_debug_build(),
		"processor": OS.get_processor_name(),
		"cache_condition": "모든 준비 실행과 측정 실행 직전에 정확한 위치 기반 요청 캐시를 초기화합니다. 사전 계산 그래프·유닛 크기 데이터·지연 생성 연결 캐시는 유지합니다. 한 실행 안의 캐시 적중은 가능하며 초기화 시간은 측정에서 제외합니다.",
		"movement_fixed_delta": MOVEMENT_FIXED_DELTA,
		"movement_speed_per_tick": MOVEMENT_SPEED,
		"movement_max_ticks": MOVEMENT_MAX_TICKS,
		"stall_observation": {
			"ticks": DIAGNOSTIC_STALL_TICKS,
			"max_displacement_squared_per_tick": DIAGNOSTIC_STALL_DISTANCE_SQUARED,
			"meaning": "관측 전용입니다. 이 관측 자체가 이동이나 재탐색을 변경하지 않습니다. 실행당 유닛별 첫 정체를 기록하며 작은 진동은 최종 미완료 상태에만 나타날 수 있습니다.",
		},
		"timing_notes": [
			"격자 내부 시간은 준비·초기화, 경로 복원을 제외한 탐색, 경로 복원으로 나뉩니다. 모두 grid_batch_usec 안에 포함되므로 상위 시간에 더하지 않습니다.",
			"추가 타이머는 일괄 탐색 경계와 경로 복원에서만 읽습니다. 탐색 시간에는 반복문 관리와 관측 비용이 포함됩니다. 외부 격자 시간에는 호출·반환과 마지막 계측 대입도 포함됩니다.",
			"최대 지연 일괄 탐색의 내부 시간은 동일한 호출을 나타냅니다. 별도로 고른 최대 격자 호출이 아닙니다. 기존 상세 계측 옵션을 사용합니다.",
			"Portal 일괄 탐색은 준비, 격자 탐색, 연결점 검사까지의 마무리로 나눕니다. 마무리 뒤의 계측 수집 비용은 제외합니다. 내부 시간을 상위 시간에 중복 합산하지 않습니다.",
			"grid_batch_usec는 준비·탐색·경로 복원을 포함합니다. 순수 힙 시간은 아닙니다. 최대 일괄 탐색과 최대 지연 틱은 따로 선택되며 틱 0은 명령 처리 또는 경로 생성입니다.",
			"Portal 상세 계측에는 관측 비용이 있습니다. 이번 힙 변경의 성능 비교는 동일한 계측 옵션에서 수행해야 합니다.",
			"정적 검사에서 행별 장애물 후보만 줄이며 최종 교차 판정은 유지합니다. broad_blocked_count는 원래 사각형 전체 후보 수, intersection_checks는 실제 검사 수입니다.",
			"정적 검사의 끝점 검사와 훑기 시간은 내부의 서로 겹치지 않는 구간입니다. 훑기에는 잘못된 시작점 복구가 포함됩니다. 구간 사이와 이후의 관리 비용은 제외합니다.",
			"정적 상세 계측은 내부 직접 호출과 가장 먼 통과점 탐색을 포함한 모든 구간 검사를 셉니다. 서비스 래퍼의 호출 수·시간과 측정 범위가 다릅니다.",
			"사각형 후보 수는 실제 검사 수가 아닙니다. 실제 검사는 조기 종료까지 집계합니다. 최대 지연 검사는 실행·단계별 1개이고 틱 0은 명령 처리 또는 경로 생성입니다.",
			"정적 상세 계측에는 타이머와 행 관리 비용이 있습니다. 상세 계측을 끈 결과와 직접 속도 개선율을 계산하지 않습니다. 캐시·준비 실행·이동 정책은 유지합니다.",
			"재탐색 시간은 계산과 경로 교체를 포함하는 이동 단계입니다. 그 내부 길찾기 시간은 추가 시간이 아닙니다.",
			"복구를 꺼도 도달한 경유점을 넘기는 처리는 유지됩니다. 복구 끄기는 최초 구현으로 되돌리는 기능이 아닙니다.",
			"시간 단위는 CPU 경과 마이크로초입니다. 시뮬레이션 이동 시간이나 렌더링 프레임 시간이 아닙니다.",
			"명령 처리 구간은 전체 명령 시간을 나눕니다. 그룹·유효성 검사·관리·계측 비용은 나머지 구간에 포함됩니다.",
			"길찾기와 이동 상세 시간은 상위 구간에 포함된 값이므로 서로 겹치지 않는 큰 구간에 다시 더하지 않습니다.",
			"틱 시간은 SimulateTick만 측정합니다. 전체 이동 반복 시간에는 반복문과 진단 상태 수집도 포함됩니다.",
			"최대 지연 틱의 세부 시간은 그 틱 하나만 나눕니다. 상태 수집·위치 반영에는 경로 추종이 포함되고 충돌 처리에서도 이동 방향을 조회할 수 있습니다.",
			"유닛 상태와 경유점은 틱 처리 후 값입니다. 희망 이동량은 충돌 조정 전 요청이고 실제 이동량은 최종 반영된 변위입니다.",
			"준비 실행은 수행하지만 측정 결과 배열에는 넣지 않습니다. 기존 준비 실행 횟수와 캐시 조건은 유지합니다.",
		],
		"cases": [],
	}


func _AppendCaseReport(
	benchmarkCase: NavigationBenchmarkCase,
	runs: Array[Dictionary],
	warmupCount: int,
) -> void:
	var starts: Array = []
	for point: Vector2 in benchmarkCase.unitStarts:
		starts.append([point.x, point.y])
	var elapsed: Array[int] = []
	var commandTimes: Array[int] = []
	var movementTimes: Array[int] = []
	for run: Dictionary in runs:
		elapsed.append(int(run["elapsed_usec"]))
		if run.has("command_process_usec"):
			commandTimes.append(int(run["command_process_usec"]))
			movementTimes.append(int(run["movement_loop_usec"]))
	var cases: Array = _report["cases"]
	cases.append(
		{
			"case_name": benchmarkCase.caseName,
			"case_display_name": NavigationBenchmarkUI.GetCaseDisplayName(benchmarkCase.caseName),
			"warmup_count": warmupCount,
			"measurement_count": runs.size(),
			"half_size": benchmarkCase.halfSize,
			"unit_starts": starts,
			"single_start": [benchmarkCase.start.x, benchmarkCase.start.y],
			"original_command_target": [benchmarkCase.target.x, benchmarkCase.target.y],
			"elapsed_statistics": _TimeStatistics(elapsed),
			"command_statistics": _TimeStatistics(commandTimes),
			"movement_loop_statistics": _TimeStatistics(movementTimes),
			"runs": runs,
		}
	)


func _ReadSourceCommit() -> Dictionary:
	if not sourceCommitOverride.is_empty():
		return { "commit": sourceCommitOverride.strip_edges(), "method": "inspector_override" }
	var gitDirectory: String = "res://.git"
	if FileAccess.file_exists(gitDirectory):
		var pointer: String = FileAccess.get_file_as_string(gitDirectory).strip_edges()
		if pointer.begins_with("gitdir: "):
			gitDirectory = pointer.trim_prefix("gitdir: ")
			if not gitDirectory.is_absolute_path():
				gitDirectory = ProjectSettings.globalize_path("res://").path_join(gitDirectory)
	var headPath: String = gitDirectory.path_join("HEAD")
	if not FileAccess.file_exists(headPath):
		return {
			"commit": "UNAVAILABLE",
			"method": "Set Source Commit Override to git rev-parse HEAD",
		}
	var head: String = FileAccess.get_file_as_string(headPath).strip_edges()
	if not head.begins_with("ref: "):
		return { "commit": head, "method": "git_head" }
	var reference: String = head.trim_prefix("ref: ")
	var referencePath: String = gitDirectory.path_join(reference)
	if FileAccess.file_exists(referencePath):
		return {
			"commit": FileAccess.get_file_as_string(referencePath).strip_edges(),
			"method": "git_ref",
		}
	var packedPath: String = gitDirectory.path_join("packed-refs")
	if FileAccess.file_exists(packedPath):
		for line: String in FileAccess.get_file_as_string(packedPath).split("\n"):
			if line.ends_with(" " + reference):
				return { "commit": line.get_slice(" ", 0), "method": "git_packed_ref" }
	return { "commit": "UNAVAILABLE", "method": "Set Source Commit Override to git rev-parse HEAD" }


func _SaveReport() -> void:
	# 모드 전체 측정 후 한 번만 저장한다. 측정 루프 안에서는 문자열 출력이나 I/O를 하지 않는다.
	var directory: String = "user://navigation_benchmark_reports"
	var error: Error = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(directory)
	)
	if error != OK:
		push_error("보고서 폴더 생성 실패: %s" % error_string(error))
		return
	var timestamp: String = str(_report["timestamp"]).replace(":", "").replace("-", "")
	var reportPath: String = "%s/%s_%s_%d.json" % [
		directory,
		timestamp,
		_report["mode"],
		Time.get_ticks_usec(),
	]
	var file: FileAccess = FileAccess.open(reportPath, FileAccess.WRITE)
	if file == null:
		push_error("보고서 저장 실패: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(_report, "\t"))
	file.flush()
	error = file.get_error()
	file.close()
	if error != OK:
		push_error("보고서 기록 실패: %s" % error_string(error))
		return
	print("벤치마크 JSON 저장: ", ProjectSettings.globalize_path(reportPath))

#endregion


func _RunPortalComparison(selectedIndex: int) -> void:
	if _isRunning:
		return
	if not _navigationService.IsReady():
		_benchmarkUI.SetPortalStatus("NavigationData 초기화를 확인하세요")
		return
	var comparisonCases: Array[Dictionary] = PORTAL_COMPARISON.CreateCases()
	if selectedIndex >= comparisonCases.size() or selectedIndex < -1:
		return
	var runAll: bool = selectedIndex == -1
	var warmups: int = PATH_WARMUP_COUNT if runAll else SELECTED_PATH_WARMUP_COUNT
	var repeats: int = PATH_MEASUREMENT_COUNT if runAll else SELECTED_PATH_MEASUREMENT_COUNT
	_isRunning = true
	_benchmarkUI.SetRunning(true, NavigationBenchmarkUI.Mode.PORTAL_COMPARISON, runAll)
	_report = {
		"schema": PORTAL_COMPARISON.REVISION,
		"change_revision": PORTAL_COMPARISON.REVISION,
		"source": _ReadSourceCommit(),
		"timestamp": Time.get_datetime_string_from_system(),
		"mode": "PortalComparison",
		"selection": "Run All" if runAll else "Run Selected",
		"warmup_pairs": warmups,
		"measurement_pairs": repeats,
		"expected_case_count": comparisonCases.size() if runAll else 1,
		"navigation_data": navigationData.resource_path,
		"navigation_data_sha256": FileAccess.get_sha256(navigationData.resource_path),
		"engine": Engine.get_version_info(),
		"os": OS.get_name(),
		"processor": OS.get_processor_name(),
		"debug_build": OS.is_debug_build(),
		"region": 0,
		"half_size": 16,
		"local_search_margin": _navigationService.localSearchMarginCells,
		"anchor_cache_capacity": _navigationService.anchorConnectionCacheCapacity,
		"cache_condition": "각 방식 직전에 요청 캐시 초기화. 사전 계산·연결 구조 유지. 검증 후에도 요청 캐시 초기화.",
		"order": "준비 실행부터 A/B의 선행 순서를 교대로 변경",
		"scope": "로그의 반올림 좌표에서 시작 Region 0의 연결을 재현. 전체 경로나 실제 Movement 측정은 아님.",
		"comparison": (
			"현재 개별 탐색 1.0 대 후보 개별 탐색 1.5. 동일 경계. 원래 단일 목표는 양쪽 1.5 유지."
			if comparePortalHeuristicWeights
			else "기존 Batch 대 개별 탐색. 복수 목표 양쪽 1.0, 동일 경계. 원래 단일 목표는 양쪽 1.5 유지."
		),
		"weight_comparison": comparePortalHeuristicWeights,
		"variants": {
			"batch": "현재 개별 / 복수 목표 1.0" if comparePortalHeuristicWeights else "기존 Batch",
			"individual": "후보 개별 / 복수 목표 1.5" if comparePortalHeuristicWeights else "개별 / 복수 목표 1.0",
		},
		"length_tolerance_pixels": PORTAL_COMPARISON.LENGTH_TOLERANCE,
		"profiling": { "portal_batch_details": true, "static_query_details": false },
		"source_sha256": { },
		"cases": [],
	}
	for sourcePath: String in [
		"res://benchmark/NavigationPortalComparison.gd",
		"res://benchmark/NavigationBenchmark.gd",
		"res://benchmark/NavigationBenchmarkUI.gd",
		"res://scripts/navigation/NavigationService.gd",
		"res://scripts/navigation/NavigationGridPathfinder.gd",
		"res://scripts/navigation/NavigationPathHeap.gd",
		"res://scripts/common/dataStructures/IntHeap.gd",
	]:
		_report["source_sha256"][sourcePath] = FileAccess.get_sha256(sourcePath)
	for caseIndex: int in range(comparisonCases.size()):
		if not runAll and caseIndex != selectedIndex:
			continue
		var caseData: Dictionary = comparisonCases[caseIndex]
		var runs: Array[Dictionary] = []
		var error: String = ""
		for iteration: int in range(warmups + repeats):
			_benchmarkUI.SetPortalStatus(
				"%s / %s %d/%d"
				% [
					caseData["label"],
					"준비" if iteration < warmups else "측정",
					iteration + 1 if iteration < warmups else iteration - warmups + 1,
					warmups if iteration < warmups else repeats,
				],
			)
			await get_tree().process_frame
			var pair: Dictionary = PORTAL_COMPARISON.RunPair(
				_navigationService,
				caseData["start"],
				iteration % 2 == 1,
				comparePortalHeuristicWeights,
			)
			if pair.has("error"):
				error = pair["error"]
				break
			if iteration >= warmups:
				runs.append(pair)
		var summary: Dictionary = PORTAL_COMPARISON.Summarize(caseData, runs, warmups, error)
		summary["source_commit"] = _report["source"]["commit"]
		_report["cases"].append(summary)
		_benchmarkUI.ShowPortalResult(summary)
	_benchmarkUI.SetRunning(false, NavigationBenchmarkUI.Mode.PORTAL_COMPARISON, false)
	_SaveReport()
	_isRunning = false
