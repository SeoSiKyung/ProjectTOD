extends Node2D

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
@export var sourceCommitOverride: String = ""

const DIAGNOSTICS_REVISION: String = "comparison-observability-v3"
const DIAGNOSTIC_STALL_TICKS: int = 30
const DIAGNOSTIC_STALL_DISTANCE_SQUARED: float = 0.000001
var _report: Dictionary = { }

@export var navigationData: NavigationData
var _navigationService: NavigationService
var _isRunning: bool = false

@onready var _benchmarkUI: NavigationBenchmarkUI = $CanvasLayer/BenchmarkUI
@onready var _runBenchmarkButton: Button = $CanvasLayer/RunBenchmarkButton

var _cases: Array[NavigationBenchmarkCase] = NavigationBenchmarkCase.CreateCases()


class BenchmarkRunResult:
	var elapsedUsec: int = 0
	var pathSize: int = 0
	var pathLengthTotal: int = 0
	var emptyPathCount: int = 0
	var staticCheckedPathCount: int = 0
	var initialBlockedPathCount: int = 0
	var initialBlockedSegmentCount: int = 0
	var overlapCellCount: int = 0
	var comparedCellCount: int = 0
	var metrics: Dictionary = { }


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

	_benchmarkUI.SetImplementationLabel("Before")
	_benchmarkUI.SetCases(_cases)
	_benchmarkUI.RunAllRequested.connect(_RunAllBenchmarks)
	_benchmarkUI.RunSelectedRequested.connect(_RunSelectedBenchmark)
	_runBenchmarkButton.pressed.connect(_OnRunBenchmarkButtonPressed)


func _OnRunBenchmarkButtonPressed() -> void:
	_RunAllBenchmarks(_benchmarkUI.GetSelectedMode())


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
	if _isRunning:
		return

	_isRunning = true
	_BeginReport(mode, true)
	_runBenchmarkButton.hide()
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
	if _isRunning:
		return

	if caseIndex < 0 or caseIndex >= _cases.size():
		return

	_isRunning = true
	_BeginReport(mode, false)
	_runBenchmarkButton.hide()
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
		_RunPathFinding(benchmarkCase, false)

	var results: Array[BenchmarkRunResult] = []
	for i: int in range(measurementCount):
		results.append(_RunPathFinding(benchmarkCase, true))

	_ShowPathResult(benchmarkCase, results)
	var runs: Array[Dictionary] = []
	for result: BenchmarkRunResult in results:
		runs.append(
			{
				"elapsed_usec": result.elapsedUsec,
				"path_size": result.pathSize,
				"path_length_total": result.pathLengthTotal,
				"empty_path_count": result.emptyPathCount,
				"static_checked_path_count": result.staticCheckedPathCount,
				"initial_blocked_path_count": result.initialBlockedPathCount,
				"initial_blocked_segment_count": result.initialBlockedSegmentCount,
				"overlap_cell_count": result.overlapCellCount,
				"compared_cell_count": result.comparedCellCount,
				"navigation_metrics_nested": result.metrics,
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


func _RunPathFinding(
	benchmarkCase: NavigationBenchmarkCase,
	measureInitialStaticBlockage: bool,
) -> BenchmarkRunResult:
	_navigationService.ClearBenchmarkRequestCache()

	var metrics: NavigationProfileMetrics = NavigationProfileMetrics.new()
	_navigationService.SetProfileMetrics(metrics)

	var result: BenchmarkRunResult = BenchmarkRunResult.new()
	var validationStarts: PackedVector2Array = PackedVector2Array()
	var validationPaths: Array[PackedVector2Array] = []

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
			result.pathLengthTotal = _GetPathLength(benchmarkCase.start, path)
			if path.is_empty():
				result.emptyPathCount = 1

			validationStarts.append(benchmarkCase.start)
			validationPaths.append(path)

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
			validationStarts = benchmarkCase.unitStarts
			validationPaths = paths

	_navigationService.ClearProfileMetrics()

	if measureInitialStaticBlockage:
		_MeasureInitialStaticBlockage(
			validationStarts,
			validationPaths,
			benchmarkCase.halfSize,
			result,
		)

	result.metrics = metrics.ToDictionary()

	return result


func _MeasureInitialStaticBlockage(
	starts: PackedVector2Array,
	paths: Array[PackedVector2Array],
	halfSize: int,
	result: BenchmarkRunResult,
) -> void:
	var count: int = mini(starts.size(), paths.size())
	for index: int in range(count):
		var path: PackedVector2Array = paths[index]
		if path.is_empty():
			continue

		result.staticCheckedPathCount += 1
		var pathClear: bool = true
		var previous: Vector2 = starts[index]
		for waypoint: Vector2 in path:
			if not _navigationService.SegmentClear(previous, waypoint, halfSize):
				result.initialBlockedSegmentCount += 1
				pathClear = false
			previous = waypoint

		if not pathClear:
			result.initialBlockedPathCount += 1


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
	_navigationService.SetProfileMetrics(movementNavigationMetrics)

	var noMovementTicks: PackedInt32Array = PackedInt32Array()
	noMovementTicks.resize(agents.size())
	noMovementTicks.fill(0)
	var captureBefore: int = 0
	var collisionBefore: int = 0
	var commitBefore: int = 0
	var arrivalBefore: int = 0
	var tickStart: int = 0
	startTime = Time.get_ticks_usec()
	while result.tickCount < MOVEMENT_MAX_TICKS and not _AreAllAgentsSettled(agents):
		if enableDiagnostics:
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
				var captureUsec: int = movementMetrics.captureTickUsec - captureBefore
				var collisionUsec: int = movementMetrics.collisionResolveUsec - collisionBefore
				var commitUsec: int = movementMetrics.commitTickUsec - commitBefore
				var arrivalUsec: int = movementMetrics.arrivalResolveUsec - arrivalBefore
				result.worstTick = {
					"tick": result.tickCount + 1,
					"elapsed_usec": tickUsec,
					"succeeded": tickSucceeded,
					"exclusive_phases": {
						"capture_usec": captureUsec,
						"collision_resolve_usec": collisionUsec,
						"commit_usec": commitUsec,
						"arrival_resolve_usec": arrivalUsec,
						"other_usec": tickUsec - captureUsec - collisionUsec
						- commitUsec - arrivalUsec,
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
	var staticCheckedPathCount: int = 0
	var initialBlockedPathCount: int = 0
	var initialBlockedSegmentCount: int = 0
	var overlapCellTotal: int = 0
	var comparedCellTotal: int = 0
	var pathLengthTotal: int = 0

	for result: BenchmarkRunResult in results:
		elapsedTimes.append(result.elapsedUsec)
		pathSizeTotal += result.pathSize
		emptyPathCount += result.emptyPathCount
		staticCheckedPathCount += result.staticCheckedPathCount
		initialBlockedPathCount += result.initialBlockedPathCount
		initialBlockedSegmentCount += result.initialBlockedSegmentCount
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
		staticCheckedPathCount,
		initialBlockedPathCount,
		initialBlockedSegmentCount,
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

	var tickTotal: int = 0
	var completedUnitTotal: int = 0
	var expectedUnitTotal: int = 0
	var targetErrorTotal: float = 0.0
	var targetErrorSampleCount: int = 0
	var succeededRunCount: int = 0
	var timedOutRunCount: int = 0
	var failedRunCount: int = 0

	for result: MovementRunResult in results:
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
		"comparison_role": "Before",
		"source": _ReadSourceCommit(),
		"source_sha256": {
			"benchmark/NavigationBenchmark.gd": FileAccess.get_sha256(
				"res://benchmark/NavigationBenchmark.gd"
			),
			"benchmark/NavigationBenchmarkUI.gd": FileAccess.get_sha256(
				"res://benchmark/NavigationBenchmarkUI.gd"
			),
			"benchmark/NavigationBenchmarkCase.gd": FileAccess.get_sha256(
				"res://benchmark/NavigationBenchmarkCase.gd"
			),
			"scripts/navigation/NavigationService.gd": FileAccess.get_sha256(
				"res://scripts/navigation/NavigationService.gd"
			),
			"maps/navigation/debug/NavigationProfileMetrics.gd": FileAccess.get_sha256(
				"res://maps/navigation/debug/NavigationProfileMetrics.gd"
			),
		},
		"working_tree_note": "Before 기준 커밋에 비교용 관측 패치를 적용한 상태입니다. Git HEAD와 함께 source_sha256으로 실제 측정 소스를 식별합니다.",
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
		"cache_condition": "Exact-position request cache cleared before EVERY warmup and measured run; baked graph, footprint data and lazy topology cache retained. Intra-run hits remain possible. Initialization is outside timed runs.",
		"movement_fixed_delta": MOVEMENT_FIXED_DELTA,
		"movement_speed_per_tick": MOVEMENT_SPEED,
		"movement_max_ticks": MOVEMENT_MAX_TICKS,
		"stall_observation": {
			"ticks": DIAGNOSTIC_STALL_TICKS,
			"max_displacement_squared_per_tick": DIAGNOSTIC_STALL_DISTANCE_SQUARED,
			"meaning": "Observation only; no repath or movement change. First event per unit per run. Small oscillations may only appear in final unfinished states.",
		},
		"timing_notes": [
			"Initial static-blockage scanning runs after timed path generation with navigation profiling detached, so it is not included in elapsed_usec or navigation phase metrics.",
			"Initial static-blockage scanning checks adjacent segments of the raw generated path only. A blocked raw segment is not the same as final movement failure because shortcutting, avoidance, and runtime path recovery when available can change execution. Empty paths are counted separately.",
			"All times are CPU elapsed microseconds, not simulated travel time or rendered frame time.",
			"command_exclusive_phases partition command_process_usec. Group/validation/bookkeeping/probe overhead is the residual.",
			"Navigation metrics and movement metrics are NESTED views; do not add them to the exclusive phases.",
			"Tick samples time SimulateTick only; movement_loop_usec also includes loop and diagnostic snapshot overhead.",
			"Worst-tick phases partition that tick only. Capture/commit include path-follow work; collision can also query steering. They are not pure PathFollower timings.",
			"Agent state and waypoint are AFTER the tick; desired_delta is the stored path request from that tick, before collision adjustment. actual_delta is committed displacement.",
			"Warmups are executed but not included in the runs array. Current warmup and cache policy are unchanged.",
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
		push_error("Failed to create benchmark report directory: %s" % error_string(error))
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
		push_error(
			"Failed to save benchmark report: %s" % error_string(FileAccess.get_open_error())
		)
		return
	file.store_string(JSON.stringify(_report, "\t"))
	file.flush()
	error = file.get_error()
	file.close()
	if error != OK:
		push_error("Failed to write benchmark report: %s" % error_string(error))
		return
	print("Benchmark report saved: ", ProjectSettings.globalize_path(reportPath))

#endregion
