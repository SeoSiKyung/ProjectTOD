class_name MovementSimulator
extends RefCounted

const INVALID_INDEX: int = -1
const MAX_INT32_VALUE: int = 2147483647
const AVOIDANCE_ITERATION_COUNT: int = 4
const SAME_DIRECTION_DOT: float = 0.8
const FOLLOW_SPEED_SCALE: float = 0.5
const COLLISION_MARGIN: float = 0.001
const AVOIDANCE_DISTANCE_RATIOS: Array[float] = [1.0, 0.75, 0.5, 0.25]

var _navigationService: NavigationService
var _agents: Array[MovementAgent] = []
var _agentIndexByUnitId: Dictionary[int, int] = {}

var _startPositions: PackedVector2Array = []
var _desiredPositions: PackedVector2Array = []
var _workingPositions: PackedVector2Array = []
var _nextPositions: PackedVector2Array = []
var _avoidanceDirections: PackedVector2Array = []
var _avoidanceSpeedScales: PackedFloat32Array = []

var _collisionFlags: PackedByteArray = []
var _hardStopFlags: PackedByteArray = []
var _neighborQueryStamps: PackedInt32Array = []

var _collisionFirstAgentIndices: PackedInt32Array = []
var _collisionSecondAgentIndices: PackedInt32Array = []
var _sweptAgentIndicesByCell: Dictionary[Vector2i, PackedInt32Array] = {}
var _queryStamp: int = 0


func _init(navigationService: NavigationService) -> void:
	SetNavigationService(navigationService)


func SetNavigationService(navigationService: NavigationService) -> void:
	_navigationService = navigationService
	PathFollower.SetNavigationService(navigationService)


func RegisterAgent(agent: MovementAgent) -> bool:
	if not is_instance_valid(agent):
		push_error("유효하지 않은 MovementAgent는 등록할 수 없습니다.")
		return false

	if agent.unitId < 0 or agent.unitId > MAX_INT32_VALUE:
		push_error("MovementAgent의 unitId가 유효하지 않습니다.")
		return false

	if agent.moveSpeed < 0:
		push_error("MovementAgent의 moveSpeed는 0 이상이어야 합니다.")
		return false

	if agent.halfSize < 0 or agent.halfSize > MAX_INT32_VALUE:
		push_error("MovementAgent의 halfSize가 PackedInt32Array 범위를 벗어났습니다.")
		return false

	if _agentIndexByUnitId.has(agent.unitId):
		push_error("MovementSimulator에 unitId %d가 이미 등록되어 있습니다." % agent.unitId)
		return false

	if _agents.has(agent):
		push_error("같은 MovementAgent가 이미 등록되어 있습니다.")
		return false

	if is_instance_valid(_navigationService) and not _navigationService.CanPlaceStatic(agent.position, agent.halfSize):
		push_error("정적 장애물과 겹치는 위치에는 MovementAgent를 등록할 수 없습니다.")
		return false

	if _wouldOverlapAgent(agent.position, agent.halfSize, agent.unitId):
		push_error("다른 MovementAgent와 겹치는 위치에는 등록할 수 없습니다.")
		return false

	_agentIndexByUnitId[agent.unitId] = _agents.size()
	_agents.append(agent)
	return true


func UnregisterAgent(unitId: int) -> MovementAgent:
	var index: int = _agentIndexByUnitId.get(unitId, INVALID_INDEX)

	if index == INVALID_INDEX:
		return null

	var removedAgent: MovementAgent = _agents[index]
	var lastIndex: int = _agents.size() - 1

	if index != lastIndex:
		var lastAgent: MovementAgent = _agents[lastIndex]

		_agents[index] = lastAgent
		_agentIndexByUnitId[lastAgent.unitId] = index

	_agents.pop_back()
	_agentIndexByUnitId.erase(unitId)
	return removedAgent


func SetPath(unitId: int, path: PackedVector2Array) -> bool:
	var agent: MovementAgent = _getAgent(unitId)

	if agent == null:
		return false

	agent.SetPath(path)
	return true


func StopUnit(unitId: int) -> bool:
	var agent: MovementAgent = _getAgent(unitId)

	if agent == null:
		return false

	agent.Stop()
	return true


func TeleportUnit(unitId: int, position: Vector2, snapshot: StageSnapshot) -> bool:
	if not is_instance_valid(snapshot):
		push_error("TeleportUnit에 StageSnapshot이 없습니다.")
		return false

	var agent: MovementAgent = _getAgent(unitId)

	if agent == null or not snapshot.HasUnit(unitId):
		return false

	if is_instance_valid(_navigationService) and not _navigationService.CanPlaceStatic(position, agent.halfSize):
		push_error("정적 장애물과 겹치는 위치로 순간이동할 수 없습니다.")
		return false

	if _wouldOverlapAgent(position, agent.halfSize, unitId):
		push_error("다른 MovementAgent와 겹치는 위치로 순간이동할 수 없습니다.")
		return false

	agent.Teleport(position)
	snapshot.UpdatePosition(unitId, position)
	return true


func SimulateTick(snapshot: StageSnapshot, fixedDelta: float) -> bool:
	if not is_instance_valid(snapshot):
		push_error("MovementSimulator에 StageSnapshot이 없습니다.")
		return false

	if fixedDelta <= Math.EPSILON:
		push_error("fixedDelta는 0보다 커야 합니다.")
		return false

	if not _validateSnapshot(snapshot):
		return false

	_prepareTickBuffers()
	_calculateDesiredPositions(fixedDelta)

	# desiredPosition은 PathFollower가 만든 원래 경로의 결과로 유지한다.
	# 회피 반복은 workingPosition만 바꾸므로 다음 틱에는 다시 원래 path를 따른다.
	for iteration: int in range(AVOIDANCE_ITERATION_COUNT):
		_rebuildSweptSpatialIndex()

		if _collectCollisionPairs() == 0:
			break

		_applyCollisionAvoidance(iteration)

	if not _applyHardCollisionFallback():
		return false

	_commitTick(snapshot, fixedDelta)
	return true


func Clear() -> void:
	_agents.clear()
	_agentIndexByUnitId.clear()
	_startPositions.clear()
	_desiredPositions.clear()
	_workingPositions.clear()
	_nextPositions.clear()
	_avoidanceDirections.clear()
	_avoidanceSpeedScales.clear()
	_collisionFlags.clear()
	_hardStopFlags.clear()
	_neighborQueryStamps.clear()
	_collisionFirstAgentIndices.clear()
	_collisionSecondAgentIndices.clear()
	_sweptAgentIndicesByCell.clear()
	_queryStamp = 0


func _getAgent(unitId: int) -> MovementAgent:
	var index: int = _agentIndexByUnitId.get(unitId, INVALID_INDEX)

	if index == INVALID_INDEX:
		return null

	return _agents[index]


func _wouldOverlapAgent(position: Vector2, halfSize: int, ignoredUnitId: int) -> bool:
	for otherAgent: MovementAgent in _agents:
		if otherAgent.unitId == ignoredUnitId:
			continue

		var combinedHalfSize: float = maxf(0.0, float(halfSize + otherAgent.halfSize) - COLLISION_MARGIN)

		if absf(position.x - otherAgent.position.x) < combinedHalfSize and absf(position.y - otherAgent.position.y) < combinedHalfSize:
			return true

	return false


func _validateSnapshot(snapshot: StageSnapshot) -> bool:
	if snapshot.GetUnitCount() != _agents.size():
		push_error("StageSnapshot과 MovementSimulator의 유닛 수가 일치하지 않습니다.")
		return false

	for agent: MovementAgent in _agents:
		if not snapshot.HasUnit(agent.unitId):
			push_error("StageSnapshot에 unitId %d가 없습니다." % agent.unitId)
			return false

		if not agent.position.is_equal_approx(snapshot.GetPosition(agent.unitId)):
			push_error("MovementAgent와 StageSnapshot의 위치가 일치하지 않습니다.")
			return false

		if agent.halfSize != snapshot.GetHalfSize(agent.unitId):
			push_error("MovementAgent와 StageSnapshot의 halfSize가 일치하지 않습니다.")
			return false

	return true


func _prepareTickBuffers() -> void:
	var agentCount: int = _agents.size()

	_startPositions.resize(agentCount)
	_desiredPositions.resize(agentCount)
	_workingPositions.resize(agentCount)
	_nextPositions.resize(agentCount)
	_avoidanceDirections.resize(agentCount)
	_avoidanceSpeedScales.resize(agentCount)
	_collisionFlags.resize(agentCount)
	_hardStopFlags.resize(agentCount)
	_neighborQueryStamps.resize(agentCount)

	_avoidanceDirections.fill(Vector2.ZERO)
	_avoidanceSpeedScales.fill(1.0)
	_collisionFlags.fill(0)
	_hardStopFlags.fill(0)
	_neighborQueryStamps.fill(0)
	_collisionFirstAgentIndices.clear()
	_collisionSecondAgentIndices.clear()
	_sweptAgentIndicesByCell.clear()


func _calculateDesiredPositions(fixedDelta: float) -> void:
	for agentIndex: int in range(_agents.size()):
		var agent: MovementAgent = _agents[agentIndex]
		var startPosition: Vector2 = agent.position
		var desiredPosition: Vector2 = agent.GetDesiredPosition(fixedDelta)

		if not _isStaticSegmentClear(agentIndex, startPosition, desiredPosition):
			desiredPosition = startPosition

		_startPositions[agentIndex] = startPosition
		_desiredPositions[agentIndex] = desiredPosition
		_workingPositions[agentIndex] = desiredPosition
		_nextPositions[agentIndex] = desiredPosition


func _applyCollisionAvoidance(iteration: int) -> void:
	_collisionFlags.fill(0)

	for pairIndex: int in range(_collisionFirstAgentIndices.size()):
		var firstAgentIndex: int = _collisionFirstAgentIndices[pairIndex]
		var secondAgentIndex: int = _collisionSecondAgentIndices[pairIndex]

		_accumulatePairAvoidance(firstAgentIndex, secondAgentIndex)

	for agentIndex: int in range(_agents.size()):
		_nextPositions[agentIndex] = _workingPositions[agentIndex]

		if _collisionFlags[agentIndex] == 0:
			continue

		_nextPositions[agentIndex] = _findAvoidancePosition(agentIndex, iteration)

	for agentIndex: int in range(_agents.size()):
		_workingPositions[agentIndex] = _nextPositions[agentIndex]


func _accumulatePairAvoidance(firstAgentIndex: int, secondAgentIndex: int) -> void:
	var firstMovementDelta: Vector2 = _workingPositions[firstAgentIndex] - _startPositions[firstAgentIndex]
	var secondMovementDelta: Vector2 = _workingPositions[secondAgentIndex] - _startPositions[secondAgentIndex]
	var firstMoves: bool = firstMovementDelta.length_squared() > Math.EPSILON
	var secondMoves: bool = secondMovementDelta.length_squared() > Math.EPSILON

	if not firstMoves and not secondMoves:
		return

	if firstMoves and secondMoves and _moveInSameDirection(firstMovementDelta, secondMovementDelta):
		var travelDirection: Vector2 = (firstMovementDelta.normalized() + secondMovementDelta.normalized()).normalized()
		var firstProgress: float = _startPositions[firstAgentIndex].dot(travelDirection)
		var secondProgress: float = _startPositions[secondAgentIndex].dot(travelDirection)

		if firstProgress < secondProgress - Math.EPSILON:
			var firstSide: float = _getSideAwayFromBlocker(firstAgentIndex, secondAgentIndex, firstMovementDelta)

			_addAvoidance(firstAgentIndex, _getSideDirection(firstMovementDelta, firstSide), FOLLOW_SPEED_SCALE)
			return

		if secondProgress < firstProgress - Math.EPSILON:
			var secondSide: float = _getSideAwayFromBlocker(secondAgentIndex, firstAgentIndex, secondMovementDelta)

			_addAvoidance(secondAgentIndex, _getSideDirection(secondMovementDelta, secondSide), FOLLOW_SPEED_SCALE)
			return

	if firstMoves and secondMoves:
		var pairSide: float = _getPairRotationSide(firstAgentIndex, secondAgentIndex, firstMovementDelta, secondMovementDelta)

		_addAvoidance(firstAgentIndex, _getSideDirection(firstMovementDelta, pairSide), 1.0)
		_addAvoidance(secondAgentIndex, _getSideDirection(secondMovementDelta, pairSide), 1.0)
		return

	if firstMoves:
		var firstSide: float = _getSideAwayFromBlocker(firstAgentIndex, secondAgentIndex, firstMovementDelta)

		_addAvoidance(firstAgentIndex, _getSideDirection(firstMovementDelta, firstSide), 1.0)
		return

	var secondSide: float = _getSideAwayFromBlocker(secondAgentIndex, firstAgentIndex, secondMovementDelta)

	_addAvoidance(secondAgentIndex, _getSideDirection(secondMovementDelta, secondSide), 1.0)


func _addAvoidance(agentIndex: int, direction: Vector2, speedScale: float) -> void:
	_avoidanceDirections[agentIndex] += direction
	_avoidanceSpeedScales[agentIndex] = minf(_avoidanceSpeedScales[agentIndex], speedScale)
	_collisionFlags[agentIndex] = 1


func _moveInSameDirection(firstDelta: Vector2, secondDelta: Vector2) -> bool:
	return firstDelta.normalized().dot(secondDelta.normalized()) >= SAME_DIRECTION_DOT


func _getPairRotationSide(firstAgentIndex: int, secondAgentIndex: int, firstDesiredDelta: Vector2, secondDesiredDelta: Vector2) -> float:
	var defaultSide: float = _getDeterministicPairSide(firstAgentIndex, secondAgentIndex)
	var firstPositiveEnd: Vector2 = _getSteeredEnd(firstAgentIndex, firstDesiredDelta, 1.0)
	var secondPositiveEnd: Vector2 = _getSteeredEnd(secondAgentIndex, secondDesiredDelta, 1.0)
	var firstNegativeEnd: Vector2 = _getSteeredEnd(firstAgentIndex, firstDesiredDelta, -1.0)
	var secondNegativeEnd: Vector2 = _getSteeredEnd(secondAgentIndex, secondDesiredDelta, -1.0)
	var combinedHalfSize: int = _agents[firstAgentIndex].halfSize + _agents[secondAgentIndex].halfSize
	var positiveCollides: bool = _movementsIntersect(_startPositions[firstAgentIndex], firstPositiveEnd, _startPositions[secondAgentIndex], secondPositiveEnd, combinedHalfSize)
	var negativeCollides: bool = _movementsIntersect(_startPositions[firstAgentIndex], firstNegativeEnd, _startPositions[secondAgentIndex], secondNegativeEnd, combinedHalfSize)

	if not positiveCollides and negativeCollides:
		return 1.0

	if positiveCollides and not negativeCollides:
		return -1.0

	return defaultSide


func _getSteeredEnd(agentIndex: int, desiredDelta: Vector2, side: float) -> Vector2:
	var stepDistance: float = desiredDelta.length()

	if stepDistance <= Math.EPSILON:
		return _startPositions[agentIndex]

	var desiredDirection: Vector2 = desiredDelta / stepDistance
	var sideDirection: Vector2 = _getSideDirection(desiredDelta, side)
	var steeredDirection: Vector2 = (desiredDirection + sideDirection).normalized()
	return _startPositions[agentIndex] + steeredDirection * stepDistance


func _getSideAwayFromBlocker(movingAgentIndex: int, blockerAgentIndex: int, movementDelta: Vector2) -> float:
	var sideDirection: Vector2 = _getSideDirection(movementDelta, 1.0)
	var separation: float = (_startPositions[movingAgentIndex] - _startPositions[blockerAgentIndex]).dot(sideDirection)

	if absf(separation) <= Math.EPSILON:
		separation = (_workingPositions[movingAgentIndex] - _workingPositions[blockerAgentIndex]).dot(sideDirection)

	if separation > Math.EPSILON:
		return 1.0

	if separation < -Math.EPSILON:
		return -1.0

	return _getDeterministicPairSide(movingAgentIndex, blockerAgentIndex)


func _getSideDirection(movementDelta: Vector2, side: float) -> Vector2:
	var movementDirection: Vector2 = movementDelta.normalized()
	return Vector2(-movementDirection.y, movementDirection.x) * side


func _getDeterministicPairSide(firstAgentIndex: int, secondAgentIndex: int) -> float:
	var firstUnitId: int = _agents[firstAgentIndex].unitId
	var secondUnitId: int = _agents[secondAgentIndex].unitId
	var lowUnitId: int = mini(firstUnitId, secondUnitId)
	var highUnitId: int = maxi(firstUnitId, secondUnitId)

	if ((lowUnitId + highUnitId) & 1) != 0:
		return -1.0

	return 1.0


func _findAvoidancePosition(agentIndex: int, iteration: int) -> Vector2:
	var startPosition: Vector2 = _startPositions[agentIndex]
	var desiredDelta: Vector2 = _desiredPositions[agentIndex] - startPosition
	var stepDistance: float = desiredDelta.length()

	if stepDistance <= Math.EPSILON:
		return startPosition

	stepDistance *= _avoidanceSpeedScales[agentIndex]
	var desiredDirection: Vector2 = desiredDelta.normalized()

	var avoidanceDirection: Vector2 = _avoidanceDirections[agentIndex]
	avoidanceDirection -= desiredDirection * avoidanceDirection.dot(desiredDirection)

	if avoidanceDirection.length_squared() <= Math.EPSILON:
		avoidanceDirection = Vector2(-desiredDirection.y, desiredDirection.x)

		if (_agents[agentIndex].unitId & 1) != 0:
			avoidanceDirection = -avoidanceDirection
	else:
		avoidanceDirection = avoidanceDirection.normalized()

	var oppositeAvoidanceDirection: Vector2 = -avoidanceDirection
	var primaryDirection: Vector2
	var oppositeDirection: Vector2

	if iteration >= AVOIDANCE_ITERATION_COUNT - 1:
		primaryDirection = avoidanceDirection
		oppositeDirection = oppositeAvoidanceDirection
	else:
		var avoidanceStrength: float = _getAvoidanceStrength(iteration)

		primaryDirection = (desiredDirection + avoidanceDirection * avoidanceStrength).normalized()
		oppositeDirection = (desiredDirection + oppositeAvoidanceDirection * avoidanceStrength).normalized()

	var candidatePosition: Vector2 = _findFarthestStaticClearPosition(agentIndex, primaryDirection, stepDistance)

	if not candidatePosition.is_equal_approx(startPosition):
		return candidatePosition

	candidatePosition = _findFarthestStaticClearPosition(agentIndex, oppositeDirection, stepDistance)

	if not candidatePosition.is_equal_approx(startPosition):
		return candidatePosition

	if iteration < AVOIDANCE_ITERATION_COUNT - 1:
		candidatePosition = _findFarthestStaticClearPosition(agentIndex, avoidanceDirection, stepDistance)

		if not candidatePosition.is_equal_approx(startPosition):
			return candidatePosition

		candidatePosition = _findFarthestStaticClearPosition(agentIndex, oppositeAvoidanceDirection, stepDistance)

		if not candidatePosition.is_equal_approx(startPosition):
			return candidatePosition

	return startPosition


func _getAvoidanceStrength(iteration: int) -> float:
	if iteration <= 0:
		return 0.75

	if iteration == 1:
		return 1.5

	return 3.0


func _findFarthestStaticClearPosition(agentIndex: int, direction: Vector2, stepDistance: float) -> Vector2:
	var startPosition: Vector2 = _startPositions[agentIndex]

	if direction.length_squared() <= Math.EPSILON or stepDistance <= Math.EPSILON:
		return startPosition

	var normalizedDirection: Vector2 = direction.normalized()

	for ratio: float in AVOIDANCE_DISTANCE_RATIOS:
		var candidatePosition: Vector2 = startPosition + normalizedDirection * stepDistance * ratio

		if _isStaticSegmentClear(agentIndex, startPosition, candidatePosition):
			return candidatePosition

	return startPosition


func _isStaticSegmentClear(agentIndex: int, startPosition: Vector2, endPosition: Vector2) -> bool:
	if startPosition.is_equal_approx(endPosition):
		return true

	if not is_instance_valid(_navigationService):
		return true

	return _navigationService.SegmentClear(startPosition, endPosition, _agents[agentIndex].halfSize)


func _applyHardCollisionFallback() -> bool:
	_rebuildSweptSpatialIndex()

	if _collectCollisionPairs() == 0:
		return true

	_hardStopFlags.fill(0)
	var stoppedAgentIndices: Array[int] = []

	for pairIndex: int in range(_collisionFirstAgentIndices.size()):
		var firstAgentIndex: int = _collisionFirstAgentIndices[pairIndex]
		var secondAgentIndex: int = _collisionSecondAgentIndices[pairIndex]
		var firstMoves: bool = not _workingPositions[firstAgentIndex].is_equal_approx(_startPositions[firstAgentIndex])
		var secondMoves: bool = not _workingPositions[secondAgentIndex].is_equal_approx(_startPositions[secondAgentIndex])

		if not firstMoves and not secondMoves:
			push_error("MovementSimulator에 시작 시점부터 겹쳐 있고 분리되지 않는 Agent가 있습니다.")
			return false

		if firstMoves:
			_markHardStop(firstAgentIndex, stoppedAgentIndices)

		if secondMoves:
			_markHardStop(secondAgentIndex, stoppedAgentIndices)

	_propagateHardStops(stoppedAgentIndices)

	for agentIndex: int in range(_agents.size()):
		if _hardStopFlags[agentIndex] != 0:
			_workingPositions[agentIndex] = _startPositions[agentIndex]

	_rebuildSweptSpatialIndex()

	if _collectCollisionPairs() == 0:
		return true

	for agentIndex: int in range(_agents.size()):
		_workingPositions[agentIndex] = _startPositions[agentIndex]

	_rebuildSweptSpatialIndex()

	if _collectCollisionPairs() == 0:
		return true

	push_error("MovementSimulator가 시작 시점의 Agent 겹침을 해결하지 못했습니다.")
	return false


func _markHardStop(agentIndex: int, stoppedAgentIndices: Array[int]) -> void:
	if _hardStopFlags[agentIndex] != 0:
		return

	_hardStopFlags[agentIndex] = 1
	stoppedAgentIndices.append(agentIndex)


func _propagateHardStops(stoppedAgentIndices: Array[int]) -> void:
	var queueIndex: int = 0

	while queueIndex < stoppedAgentIndices.size():
		var blockerAgentIndex: int = stoppedAgentIndices[queueIndex]
		var blockerAgent: MovementAgent = _agents[blockerAgentIndex]
		var blockerPosition: Vector2 = _startPositions[blockerAgentIndex]
		var minCell: Vector2i = _getSweptMinCell(blockerPosition, blockerPosition, blockerAgent.halfSize)
		var maxCell: Vector2i = _getSweptMaxCell(blockerPosition, blockerPosition, blockerAgent.halfSize)
		var queryStamp: int = _beginNeighborQuery()

		queueIndex += 1

		for cellX: int in range(minCell.x, maxCell.x + 1):
			for cellY: int in range(minCell.y, maxCell.y + 1):
				var cell: Vector2i = Vector2i(cellX, cellY)

				if not _sweptAgentIndicesByCell.has(cell):
					continue

				var cellAgentIndices: PackedInt32Array = _sweptAgentIndicesByCell[cell]

				for movingAgentIndex: int in cellAgentIndices:
					if movingAgentIndex == blockerAgentIndex or _hardStopFlags[movingAgentIndex] != 0:
						continue

					if _neighborQueryStamps[movingAgentIndex] == queryStamp:
						continue

					_neighborQueryStamps[movingAgentIndex] = queryStamp

					if _workingPositions[movingAgentIndex].is_equal_approx(_startPositions[movingAgentIndex]):
						continue

					var combinedHalfSize: int = _agents[movingAgentIndex].halfSize + blockerAgent.halfSize

					if _movementsIntersect(_startPositions[movingAgentIndex], _workingPositions[movingAgentIndex], blockerPosition, blockerPosition, combinedHalfSize):
						_markHardStop(movingAgentIndex, stoppedAgentIndices)


func _rebuildSweptSpatialIndex() -> void:
	_sweptAgentIndicesByCell.clear()

	for agentIndex: int in range(_agents.size()):
		var agent: MovementAgent = _agents[agentIndex]
		var minCell: Vector2i = _getSweptMinCell(_startPositions[agentIndex], _workingPositions[agentIndex], agent.halfSize)
		var maxCell: Vector2i = _getSweptMaxCell(_startPositions[agentIndex], _workingPositions[agentIndex], agent.halfSize)

		for cellX: int in range(minCell.x, maxCell.x + 1):
			for cellY: int in range(minCell.y, maxCell.y + 1):
				var cell: Vector2i = Vector2i(cellX, cellY)
				var cellAgentIndices: PackedInt32Array = _sweptAgentIndicesByCell.get(cell, PackedInt32Array())

				cellAgentIndices.append(agentIndex)
				_sweptAgentIndicesByCell[cell] = cellAgentIndices


func _collectCollisionPairs() -> int:
	_collisionFirstAgentIndices.clear()
	_collisionSecondAgentIndices.clear()

	for firstAgentIndex: int in range(_agents.size()):
		var firstAgent: MovementAgent = _agents[firstAgentIndex]
		var minCell: Vector2i = _getSweptMinCell(_startPositions[firstAgentIndex], _workingPositions[firstAgentIndex], firstAgent.halfSize)
		var maxCell: Vector2i = _getSweptMaxCell(_startPositions[firstAgentIndex], _workingPositions[firstAgentIndex], firstAgent.halfSize)
		var queryStamp: int = _beginNeighborQuery()

		for cellX: int in range(minCell.x, maxCell.x + 1):
			for cellY: int in range(minCell.y, maxCell.y + 1):
				var cell: Vector2i = Vector2i(cellX, cellY)

				if not _sweptAgentIndicesByCell.has(cell):
					continue

				var cellAgentIndices: PackedInt32Array = _sweptAgentIndicesByCell[cell]

				for secondAgentIndex: int in cellAgentIndices:
					if secondAgentIndex <= firstAgentIndex:
						continue

					if _neighborQueryStamps[secondAgentIndex] == queryStamp:
						continue

					_neighborQueryStamps[secondAgentIndex] = queryStamp
					var combinedHalfSize: int = firstAgent.halfSize + _agents[secondAgentIndex].halfSize

					if not _movementsIntersect(_startPositions[firstAgentIndex], _workingPositions[firstAgentIndex], _startPositions[secondAgentIndex], _workingPositions[secondAgentIndex], combinedHalfSize):
						continue

					_collisionFirstAgentIndices.append(firstAgentIndex)
					_collisionSecondAgentIndices.append(secondAgentIndex)

	return _collisionFirstAgentIndices.size()


func _beginNeighborQuery() -> int:
	if _queryStamp >= MAX_INT32_VALUE:
		_neighborQueryStamps.fill(0)
		_queryStamp = 1
	else:
		_queryStamp += 1

	return _queryStamp


func _commitTick(snapshot: StageSnapshot, fixedDelta: float) -> void:
	# 모든 결과가 확정된 뒤 한 번만 커밋한다.
	# 이때 MovementAgent가 PathFollower.OnMovementCommitted()를 호출해 index를 갱신한다.
	for agentIndex: int in range(_agents.size()):
		_agents[agentIndex].CommitMovement(_workingPositions[agentIndex], fixedDelta)

	for agentIndex: int in range(_agents.size()):
		snapshot.UpdatePosition(_agents[agentIndex].unitId, _workingPositions[agentIndex])


func _movementsIntersect(firstStart: Vector2, firstEnd: Vector2, secondStart: Vector2, secondEnd: Vector2, combinedHalfSize: int) -> bool:
	var collisionHalfSize: float = maxf(0.0, float(combinedHalfSize) - COLLISION_MARGIN)

	if collisionHalfSize <= Math.EPSILON:
		return false

	var relativeStart: Vector2 = firstStart - secondStart
	var relativeEnd: Vector2 = firstEnd - secondEnd
	var startsOverlapping: bool = absf(relativeStart.x) < collisionHalfSize and absf(relativeStart.y) < collisionHalfSize

	if startsOverlapping:
		return true

	return _segmentIntersectsCenteredRect(relativeStart, relativeEnd, collisionHalfSize)


func _segmentIntersectsCenteredRect(startPosition: Vector2, endPosition: Vector2, halfSize: float) -> bool:
	var movementDelta: Vector2 = endPosition - startPosition
	var minimumTime: float = 0.0
	var maximumTime: float = 1.0

	if absf(movementDelta.x) <= Math.EPSILON:
		if absf(startPosition.x) >= halfSize:
			return false
	else:
		var firstXTime: float = (-halfSize - startPosition.x) / movementDelta.x
		var secondXTime: float = (halfSize - startPosition.x) / movementDelta.x

		if firstXTime > secondXTime:
			var swappedXTime: float = firstXTime
			firstXTime = secondXTime
			secondXTime = swappedXTime

		minimumTime = maxf(minimumTime, firstXTime)
		maximumTime = minf(maximumTime, secondXTime)

		if minimumTime >= maximumTime:
			return false

	if absf(movementDelta.y) <= Math.EPSILON:
		if absf(startPosition.y) >= halfSize:
			return false
	else:
		var firstYTime: float = (-halfSize - startPosition.y) / movementDelta.y
		var secondYTime: float = (halfSize - startPosition.y) / movementDelta.y

		if firstYTime > secondYTime:
			var swappedYTime: float = firstYTime
			firstYTime = secondYTime
			secondYTime = swappedYTime

		minimumTime = maxf(minimumTime, firstYTime)
		maximumTime = minf(maximumTime, secondYTime)

		if minimumTime >= maximumTime:
			return false

	return maximumTime > 0.0 and minimumTime < 1.0


func _getSweptMinCell(startPosition: Vector2, endPosition: Vector2, halfSize: int) -> Vector2i:
	var minimumPosition: Vector2 = Vector2(minf(startPosition.x, endPosition.x) - float(halfSize), minf(startPosition.y, endPosition.y) - float(halfSize))
	return _getCell(minimumPosition)


func _getSweptMaxCell(startPosition: Vector2, endPosition: Vector2, halfSize: int) -> Vector2i:
	var maximumPosition: Vector2 = Vector2(maxf(startPosition.x, endPosition.x) + float(halfSize), maxf(startPosition.y, endPosition.y) + float(halfSize))
	return _getCell(maximumPosition)


func _getCell(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / StageSnapshot.SPATIAL_CELL_SIZE), floori(position.y / StageSnapshot.SPATIAL_CELL_SIZE))
