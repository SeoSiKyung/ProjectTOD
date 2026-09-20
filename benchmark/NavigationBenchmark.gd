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


class PathOverlapResult:
	var overlapCellCount: int = 0
	var comparedCellCount: int = 0


func _ready() -> void:
	_navigationService = NavigationService.new()
	_navigationService.navigationData = navigationData
	_navigationService.Ready()

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
	_isRunning = false


func _RunSelectedBenchmark(mode: int, caseIndex: int) -> void:
	if _isRunning:
		return

	if caseIndex < 0 or caseIndex >= _cases.size():
		return

	_isRunning = true
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
	var command: MoveCommand = MoveCommand.new(unitIds, benchmarkCase.target)

	var startTime: int = Time.get_ticks_usec()
	var commandSucceeded: bool = commandProcessor.Process(command, snapshot)
	result.commandUsec = Time.get_ticks_usec() - startTime

	if not commandSucceeded:
		result.elapsedUsec = result.commandUsec
		result.errorMessage = "MoveCommandProcessor failed"
		_ClearProfileMetrics(movementSimulator)
		return result

	var movementNavigationMetrics: NavigationProfileMetrics = NavigationProfileMetrics.new()
	_navigationService.SetProfileMetrics(movementNavigationMetrics)

	startTime = Time.get_ticks_usec()
	while result.tickCount < MOVEMENT_MAX_TICKS and not _AreAllAgentsSettled(agents):
		if not movementSimulator.SimulateTick(snapshot, MOVEMENT_FIXED_DELTA):
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
