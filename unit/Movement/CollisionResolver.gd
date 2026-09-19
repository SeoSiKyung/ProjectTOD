class_name CollisionResolver
extends RefCounted

const MIN_SPEED_RATIO: float = 0.10
const EPSILON: float = 0.00001
const INVALID_UNIT_ID: int = -1

enum VisitState { UNVISITED, VISITING, DONE }


class MoveCandidate:
	var direction: Vector2
	var distance: float
	var staticDistance: float = -1.0


class ResolveFrame:
	var data: CollisionGroup.AgentData
	var candidates: Array[MoveCandidate] = []
	var candidateIndex: int = 0


var lastError: String = ""
var _query: MovementCollisionQuery
var _group: CollisionGroup
var _states: Dictionary[int, int] = {}
var _stack: Array[ResolveFrame] = []
var _occupancy: StageSnapshot
var _occupancyCellSize: float = 0.0
var _profileMetrics: MovementProfileMetrics


func _init(navigationService: NavigationService) -> void:
	_query = MovementCollisionQuery.new(navigationService)


func SetProfileMetrics(metrics: MovementProfileMetrics) -> void:
	_profileMetrics = metrics


func Resolve(group: CollisionGroup) -> bool:
	lastError = ""
	_group = group
	_states.clear()
	_stack.clear()
	_ResetOccupancy()
	if not _InitializeReservations():
		return false
	for data: CollisionGroup.AgentData in group.agents:
		if _states[data.unitId] == VisitState.DONE:
			continue
		_PushAgent(data)
		_ResolveStack()
	return true


func _ResetOccupancy() -> void:
	var cellSize: float = _ChooseSpatialCellSize()
	if _occupancy == null or cellSize != _occupancyCellSize:
		_occupancy = StageSnapshot.new(_group.agents.size(), cellSize)
		_occupancyCellSize = cellSize
	else:
		_occupancy.Clear()


func _ChooseSpatialCellSize() -> float:
	var counts: Dictionary[int, int] = {}
	var mostCommonSize: int = 16
	var highestCount: int = 0
	for data: CollisionGroup.AgentData in _group.agents:
		var count: int = counts.get(data.halfSize, 0) + 1
		counts[data.halfSize] = count
		if count > highestCount or (count == highestCount and data.halfSize < mostCommonSize):
			highestCount = count
			mostCommonSize = data.halfSize
	return maxf(1.0, float(mostCommonSize) * 2.0)


func _InitializeReservations() -> bool:
	for data: CollisionGroup.AgentData in _group.agents:
		if not _query.IsPositionClear(data.startPosition, data.halfSize, data.unitId, _occupancy):
			lastError = "틱 시작부터 유닛이 겹쳐 있습니다: unitId %d" % data.unitId
			return false
		_occupancy.RegisterUnit(data.unitId, data.startPosition, data.halfSize)
		_states[data.unitId] = VisitState.UNVISITED
	return true


func _ResolveStack() -> void:
	while not _stack.is_empty():
		var frame: ResolveFrame = _stack.back()
		if frame.candidateIndex >= frame.candidates.size():
			if _profileMetrics != null and frame.data.desiredPosition != frame.data.startPosition:
				_profileMetrics.stalledAgentTicks += 1
			_ReservePosition(frame.data, frame.data.startPosition)
			_stack.pop_back()
			continue
		var candidate: MoveCandidate = frame.candidates[frame.candidateIndex]
		_PrepareStaticDistance(frame.data, candidate)
		if _profileMetrics != null:
			_profileMetrics.collisionCandidateQueries += 1
			if frame.candidateIndex > 0:
				_profileMetrics.alternateCandidateQueries += 1
		var travel: MovementCollisionQuery.TravelQuery = _query.QueryTravel(
			frame.data, candidate.direction, candidate.staticDistance, _occupancy,
		)
		if (
			_profileMetrics != null
			and not travel.blockerIds.is_empty()
			and travel.distance + EPSILON < candidate.staticDistance
		):
			_profileMetrics.dynamicBlockedCandidates += 1
		var blockerId: int = _FindUnvisitedBlocker(travel.blockerIds)
		if blockerId != INVALID_UNIT_ID:
			_PushAgent(_group.GetAgent(blockerId))
			continue
		if _TryReserveCandidate(frame.data, candidate, travel.distance):
			_stack.pop_back()
		else:
			frame.candidateIndex += 1


func _PushAgent(data: CollisionGroup.AgentData) -> void:
	_states[data.unitId] = VisitState.VISITING
	var frame: ResolveFrame = ResolveFrame.new()
	frame.data = data
	frame.candidates = _BuildCandidates(data)
	_stack.append(frame)


func _BuildCandidates(data: CollisionGroup.AgentData) -> Array[MoveCandidate]:
	var result: Array[MoveCandidate] = []
	var desiredDelta: Vector2 = data.desiredPosition - data.startPosition
	var distance: float = desiredDelta.length()
	if distance <= EPSILON or data.maxStepDistance <= EPSILON:
		return result
	_AddCandidate(result, desiredDelta.normalized(), minf(distance, data.maxStepDistance))
	var xDirection: Vector2 = Vector2(signf(desiredDelta.x), 0.0)
	var yDirection: Vector2 = Vector2(0.0, signf(desiredDelta.y))
	if absf(desiredDelta.x) >= absf(desiredDelta.y):
		_AddCandidate(result, xDirection, data.maxStepDistance)
		_AddCandidate(result, yDirection, data.maxStepDistance)
	else:
		_AddCandidate(result, yDirection, data.maxStepDistance)
		_AddCandidate(result, xDirection, data.maxStepDistance)
	return result


func _AddCandidate(result: Array[MoveCandidate], direction: Vector2, distance: float) -> void:
	if direction == Vector2.ZERO:
		return
	for existing: MoveCandidate in result:
		if existing.direction == direction:
			return
	var candidate: MoveCandidate = MoveCandidate.new()
	candidate.direction = direction
	candidate.distance = distance
	result.append(candidate)


func _PrepareStaticDistance(data: CollisionGroup.AgentData, candidate: MoveCandidate) -> void:
	if candidate.staticDistance < 0.0:
		candidate.staticDistance = _query.GetStaticTravelDistance(
			data, candidate.direction, candidate.distance,
		)


func _FindUnvisitedBlocker(blockerIds: Array[int]) -> int:
	for blockerId: int in blockerIds:
		if _states[blockerId] == VisitState.UNVISITED:
			return blockerId
			
	return INVALID_UNIT_ID


func _TryReserveCandidate(
	data: CollisionGroup.AgentData,
	candidate: MoveCandidate,
	distance: float,
) -> bool:
	var endpoint: Vector2 = _query.GetSafeEndpoint(data, candidate.direction, distance, _occupancy)
	var actualDistance: float = data.startPosition.distance_to(endpoint)
	if actualDistance <= EPSILON:
		return false
	var shortened: bool = actualDistance + EPSILON < candidate.distance
	if shortened and actualDistance + EPSILON < data.maxStepDistance * MIN_SPEED_RATIO:
		return false
	_ReservePosition(data, endpoint)
	return true


func _ReservePosition(data: CollisionGroup.AgentData, position: Vector2) -> void:
	data.nextPosition = position
	_occupancy.UpdatePosition(data.unitId, position)
	_states[data.unitId] = VisitState.DONE
