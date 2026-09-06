class_name CollisionResolver
extends RefCounted


const EPSILON: float = 0.00001
const MIN_SPEED_RATIO: float = 0.01


class Candidate:
	var position: Vector2
	var keepSlide: bool


var _navigationService: NavigationService
var _group: CollisionGroup
var _priorityByUnitId: Dictionary = {}
var _reservationOrder: Array[int] = []
var _snapshots: Dictionary = {}


func _init(
	navigationService: NavigationService
) -> void:
	_navigationService = navigationService


func Resolve(
	group: CollisionGroup,
) -> bool:
	_group = group
	_priorityByUnitId.clear()
	_reservationOrder.clear()
	_snapshots.clear()

	var orderedAgents: Array = group.agents.duplicate()

	orderedAgents.sort_custom(
		func(
			first: CollisionGroup.AgentData,
			second: CollisionGroup.AgentData
		) -> bool:
			return _ComparePriority(
				first,
				second
			)
	)

	for index: int in range(
		orderedAgents.size()
	):
		var data: CollisionGroup.AgentData = (
			orderedAgents[index]
		)

		_priorityByUnitId[
			data.agent.unitId
		] = index

	_InitializeIdleRelations()

	var states: Dictionary = {}
	var reservedPositions: Dictionary = {}
	var pendingPositions: Dictionary = {}

	for data: CollisionGroup.AgentData in orderedAgents:
		states[data.agent.unitId] = 0

	for data: CollisionGroup.AgentData in orderedAgents:
		if not _ReserveAgent(
			data,
			states,
			reservedPositions,
			pendingPositions
		):
			_ReserveStopAgent(
				data,
				states,
				reservedPositions
			)

	return true


func _ReserveAgent(
	data: CollisionGroup.AgentData,
	states: Dictionary,
	reservedPositions: Dictionary,
	pendingPositions: Dictionary
) -> bool:
	var unitId: int = data.agent.unitId
	var state: int = int(
		states.get(
			unitId,
			0
		)
	)

	if state == 2:
		return true

	if state == 1:
		return false

	states[unitId] = 1
	_CaptureSnapshot(data)

	if data.idle:
		data.nextPosition = data.startPosition
		reservedPositions[unitId] = data.nextPosition
		_reservationOrder.append(unitId)
		states[unitId] = 2
		return true

	var candidates: Array[Candidate] = _BuildCandidates(
		data,
		reservedPositions,
		pendingPositions
	)

	for candidate: Candidate in candidates:
		var reservationCount: int = (
			_reservationOrder.size()
		)

		pendingPositions[unitId] = candidate.position

		if not _ReserveBlockers(
			data,
			candidate.position,
			states,
			reservedPositions,
			pendingPositions
		):
			pendingPositions.erase(unitId)

			_RollbackReservations(
				reservationCount,
				states,
				reservedPositions
			)
			continue

		pendingPositions.erase(unitId)

		if not _CandidateClear(
			data,
			candidate.position,
			reservedPositions,
			pendingPositions
		):
			_RollbackReservations(
				reservationCount,
				states,
				reservedPositions
			)
			continue

		data.nextPosition = candidate.position

		_ApplyCandidateState(
			data,
			candidate
		)

		reservedPositions[unitId] = data.nextPosition
		_reservationOrder.append(unitId)
		states[unitId] = 2
		return true

	pendingPositions.erase(unitId)

	_RestoreSnapshot(
		data,
		states
	)

	return false


func _ReserveStopAgent(
	data: CollisionGroup.AgentData,
	states: Dictionary,
	reservedPositions: Dictionary
) -> void:
	var unitId: int = data.agent.unitId

	data.nextPosition = data.startPosition

	_ApplyCandidateState(
		data,
		_StopCandidate(data)
	)

	reservedPositions[unitId] = data.nextPosition
	_reservationOrder.append(unitId)
	states[unitId] = 2


func _ReserveBlockers(
	data: CollisionGroup.AgentData,
	position: Vector2,
	states: Dictionary,
	reservedPositions: Dictionary,
	pendingPositions: Dictionary
) -> bool:
	var blockers: Array = _FindBlockers(
		data,
		position,
		states,
		reservedPositions
	)

	for blocker: CollisionGroup.AgentData in blockers:
		var blockerId: int = blocker.agent.unitId

		if reservedPositions.has(blockerId):
			return false

		if int(
			states.get(
				blockerId,
				0
			)
		) == 1:
			continue

		if not _ReserveAgent(
			blocker,
			states,
			reservedPositions,
			pendingPositions
		):
			return false

	return true


func _FindBlockers(
	data: CollisionGroup.AgentData,
	position: Vector2,
	states: Dictionary,
	reservedPositions: Dictionary
) -> Array:
	var blockers: Array = []

	for other: CollisionGroup.AgentData in _group.agents:
		var otherId: int = other.agent.unitId
		var otherState: int = int(
			states.get(
				otherId,
				0
			)
		)

		if otherId == data.agent.unitId:
			continue

		if otherState == 1:
			continue

		var referencePosition: Vector2

		if reservedPositions.has(otherId):
			referencePosition = reservedPositions[otherId]
		else:
			referencePosition = other.startPosition

		if not _Overlap(
			position,
			data.halfSize,
			referencePosition,
			other.halfSize
		):
			continue

		blockers.append(other)

	blockers.sort_custom(
		func(
			first: CollisionGroup.AgentData,
			second: CollisionGroup.AgentData
		) -> bool:
			return int(
				_priorityByUnitId[
					first.agent.unitId
				]
			) < int(
				_priorityByUnitId[
					second.agent.unitId
				]
			)
	)

	return blockers


func _BuildCandidates(
	data: CollisionGroup.AgentData,
	reservedPositions: Dictionary,
	pendingPositions: Dictionary
) -> Array[Candidate]:
	if data.currentIdleIds.is_empty():
		return _BuildGeneralCandidates(
			data,
			reservedPositions,
			pendingPositions
		)

	if (
		_HasPersistentSlide(data)
		and not _HasNewIdle(data)
	):
		var persistentCandidates: Array[Candidate] = (
			_BuildPersistentCandidates(
				data,
				reservedPositions,
				pendingPositions
			)
		)

		if not persistentCandidates.is_empty():
			return persistentCandidates

	return _BuildGeneralCandidates(
		data,
		reservedPositions,
		pendingPositions
	)


func _BuildGeneralCandidates(
	data: CollisionGroup.AgentData,
	reservedPositions: Dictionary,
	pendingPositions: Dictionary
) -> Array[Candidate]:
	var result: Array[Candidate] = []

	result.append(
		_KeepCandidate(data)
	)

	var desiredDirection: Vector2 = (
		data.desiredDelta.normalized()
	)

	if desiredDirection.length_squared() > EPSILON:
		var slowCandidate: Candidate = (
			_BuildSlowCandidate(
				data,
				desiredDirection,
				data.desiredDelta.length(),
				false,
				reservedPositions,
				pendingPositions
			)
		)

		if slowCandidate != null:
			result.append(slowCandidate)

	var directions: Array[Vector2] = [
		Vector2.UP,
		Vector2.DOWN,
		Vector2.LEFT,
		Vector2.RIGHT
	]

	directions.sort_custom(
		func(
			first: Vector2,
			second: Vector2
		) -> bool:
			return _DirectionLoss(
				data,
				first
			) < _DirectionLoss(
				data,
				second
			)
	)

	var keepSlide: bool = (
		not data.currentIdleIds.is_empty()
	)

	for direction: Vector2 in directions:
		result.append(
			_BuildMoveCandidate(
				data,
				direction,
				data.speed,
				keepSlide
			)
		)

	result.append(
		_StopCandidate(data)
	)

	return result


func _BuildPersistentCandidates(
	data: CollisionGroup.AgentData,
	reservedPositions: Dictionary,
	pendingPositions: Dictionary
) -> Array[Candidate]:
	var result: Array[Candidate] = []

	if data.slideDirection.length_squared() <= EPSILON:
		return result

	var persistentCandidate: Candidate = (
		_BuildPersistentCandidate(data)
	)

	if persistentCandidate != null:
		result.append(
			persistentCandidate
		)

	var slowCandidate: Candidate = (
		_BuildSlowCandidate(
			data,
			data.slideDirection,
			data.speed,
			true,
			reservedPositions,
			pendingPositions
		)
	)

	if slowCandidate != null:
		if (
			result.is_empty()
			or not is_equal_approx(
				slowCandidate.position.x,
				result[0].position.x
			)
			or not is_equal_approx(
				slowCandidate.position.y,
				result[0].position.y
			)
		):
			result.append(slowCandidate)

	return result


func _BuildPersistentCandidate(
	data: CollisionGroup.AgentData
) -> Candidate:
	if data.slideDirection.length_squared() <= EPSILON:
		return null

	return _BuildMoveCandidate(
		data,
		data.slideDirection,
		data.speed,
		true
	)


func _BuildSlowCandidate(
	data: CollisionGroup.AgentData,
	direction: Vector2,
	distance: float,
	keepSlide: bool,
	reservedPositions: Dictionary,
	pendingPositions: Dictionary
) -> Candidate:
	if direction.length_squared() <= EPSILON:
		return null

	if distance <= EPSILON:
		return null

	var moveDirection: Vector2 = (
		direction.normalized()
	)

	var maxDistance: float = distance

	for other: CollisionGroup.AgentData in _group.agents:
		var otherId: int = other.agent.unitId

		if otherId == data.agent.unitId:
			continue

		var referencePosition: Vector2

		if reservedPositions.has(otherId):
			referencePosition = reservedPositions[otherId]

		elif pendingPositions.has(otherId):
			referencePosition = pendingPositions[otherId]

		else:
			continue

		var hitDistance: float = (
			_RayHitDistance(
				data.startPosition,
				moveDirection,
				referencePosition,
				float(
					data.halfSize
					+ other.halfSize
				)
			)
		)

		if is_inf(hitDistance):
			continue

		if hitDistance <= EPSILON:
			return null

		maxDistance = minf(
			maxDistance,
			hitDistance
		)

	if maxDistance < (
		distance * MIN_SPEED_RATIO
	):
		return null

	return _BuildMoveCandidate(
		data,
		moveDirection,
		maxDistance,
		keepSlide
	)


func _BuildMoveCandidate(
	data: CollisionGroup.AgentData,
	direction: Vector2,
	distance: float,
	keepSlide: bool
) -> Candidate:
	if direction.length_squared() <= EPSILON:
		return null

	if distance <= EPSILON:
		return null

	var candidate: Candidate = Candidate.new()

	candidate.position = (
		data.startPosition
		+ direction.normalized()
		* distance
	)

	candidate.keepSlide = keepSlide

	return candidate


func _KeepCandidate(
	data: CollisionGroup.AgentData
) -> Candidate:
	var candidate: Candidate = Candidate.new()

	candidate.position = data.desiredPosition
	candidate.keepSlide = (
		data.slideDirection.length_squared()
		> EPSILON
	)

	return candidate


func _StopCandidate(
	data: CollisionGroup.AgentData
) -> Candidate:
	var candidate: Candidate = Candidate.new()

	candidate.position = data.startPosition
	candidate.keepSlide = false

	return candidate


func _ApplyCandidateState(
	data: CollisionGroup.AgentData,
	candidate: Candidate
) -> void:
	if not candidate.keepSlide:
		if data.currentIdleIds.is_empty():
			data.slideDirection = Vector2.ZERO

		return

	var delta: Vector2 = (
		candidate.position
		- data.startPosition
	)

	if delta.length_squared() <= EPSILON:
		return

	data.slideDirection = delta.normalized()


func _InitializeIdleRelations() -> void:
	for data: CollisionGroup.AgentData in _group.agents:
		data.currentIdleIds.clear()

	for pair: Vector2i in _group.collisions:
		var first: CollisionGroup.AgentData = (
			_FindAgent(pair.x)
		)

		var second: CollisionGroup.AgentData = (
			_FindAgent(pair.y)
		)

		if first == null or second == null:
			continue

		if first.idle and not second.idle:
			second.currentIdleIds.append(
				first.agent.unitId
			)

		elif second.idle and not first.idle:
			first.currentIdleIds.append(
				second.agent.unitId
			)


func _HasPersistentSlide(
	data: CollisionGroup.AgentData
) -> bool:
	return (
		data.slideDirection.length_squared()
		> EPSILON
	)


func _HasNewIdle(
	data: CollisionGroup.AgentData
) -> bool:
	for idleId in data.currentIdleIds:
		if not data.slideIdleIds.has(idleId):
			return true

	return false


func _CandidateClear(
	data: CollisionGroup.AgentData,
	position: Vector2,
	reservedPositions: Dictionary,
	pendingPositions: Dictionary
) -> bool:
	if not _StaticClear(
		data,
		position
	):
		return false

	for other: CollisionGroup.AgentData in _group.agents:
		var otherId: int = other.agent.unitId

		if otherId == data.agent.unitId:
			continue

		var referencePosition: Vector2

		if reservedPositions.has(otherId):
			referencePosition = reservedPositions[otherId]

		elif pendingPositions.has(otherId):
			referencePosition = pendingPositions[otherId]

		else:
			continue

		if _Overlap(
			position,
			data.halfSize,
			referencePosition,
			other.halfSize
		):
			return false

	return true


func _CaptureSnapshot(
	data: CollisionGroup.AgentData
) -> void:
	var unitId: int = data.agent.unitId

	if _snapshots.has(unitId):
		return

	_snapshots[unitId] = {
		"nextPosition": data.nextPosition,
		"slideDirection": data.slideDirection,
		"currentIdleIds": data.currentIdleIds.duplicate()
	}


func _RestoreSnapshot(
	data: CollisionGroup.AgentData,
	states: Dictionary
) -> void:
	var unitId: int = data.agent.unitId

	var snapshot: Dictionary = _snapshots.get(
		unitId,
		{}
	)

	if snapshot.has("nextPosition"):
		data.nextPosition = snapshot["nextPosition"]

	if snapshot.has("slideDirection"):
		data.slideDirection = snapshot["slideDirection"]

	if snapshot.has("currentIdleIds"):
		data.currentIdleIds = (
			snapshot["currentIdleIds"].duplicate()
		)

	states[unitId] = 0


func _RollbackReservations(
	reservationCount: int,
	states: Dictionary,
	reservedPositions: Dictionary
) -> void:
	while _reservationOrder.size() > reservationCount:
		var unitId: int = _reservationOrder.pop_back()

		reservedPositions.erase(unitId)

		var data: CollisionGroup.AgentData = (
			_FindAgent(unitId)
		)

		if data == null:
			continue

		var snapshot: Dictionary = _snapshots.get(
			unitId,
			{}
		)

		if snapshot.has("nextPosition"):
			data.nextPosition = snapshot["nextPosition"]

		if snapshot.has("slideDirection"):
			data.slideDirection = snapshot["slideDirection"]

		if snapshot.has("currentIdleIds"):
			data.currentIdleIds = (
				snapshot["currentIdleIds"].duplicate()
			)

		states[unitId] = 0


func _ComparePriority(
	first: CollisionGroup.AgentData,
	second: CollisionGroup.AgentData
) -> bool:
	if first.idle != second.idle:
		return first.idle

	var firstDistance: float = (
		first.startPosition.distance_squared_to(
			first.agent.moveTarget
		)
	)

	var secondDistance: float = (
		second.startPosition.distance_squared_to(
			second.agent.moveTarget
		)
	)

	if not is_equal_approx(
		firstDistance,
		secondDistance
	):
		return firstDistance < secondDistance

	return (
		first.agent.unitId
		< second.agent.unitId
	)


func _StaticClear(
	data: CollisionGroup.AgentData,
	position: Vector2
) -> bool:
	if _navigationService == null:
		return true

	return _navigationService.SegmentClear(
		data.startPosition,
		position,
		data.halfSize
	)


func _RayHitDistance(
	origin: Vector2,
	direction: Vector2,
	center: Vector2,
	halfSize: float
) -> float:
	var relative: Vector2 = center - origin
	var enter: float = -INF
	var exit: float = INF

	if absf(direction.x) <= EPSILON:
		if absf(relative.x) > halfSize:
			return INF
	else:
		var tx1: float = (
			relative.x - halfSize
		) / direction.x
		var tx2: float = (
			relative.x + halfSize
		) / direction.x

		var tempX: float

		if tx1 > tx2:
			tempX = tx1
			tx1 = tx2
			tx2 = tempX

		enter = maxf(
			enter,
			tx1
		)

		exit = minf(
			exit,
			tx2
		)

	if absf(direction.y) <= EPSILON:
		if absf(relative.y) > halfSize:
			return INF
	else:
		var ty1: float = (
			relative.y - halfSize
		) / direction.y
		var ty2: float = (
			relative.y + halfSize
		) / direction.y

		var tempY: float

		if ty1 > ty2:
			tempY = ty2
			ty2 = ty1
			ty1 = tempY

		enter = maxf(
			enter,
			ty1
		)

		exit = minf(
			exit,
			ty2
		)

	if enter > exit:
		return INF

	if exit < 0.0:
		return INF

	return maxf(
		enter,
		0.0
	)


func _DirectionLoss(
	data: CollisionGroup.AgentData,
	direction: Vector2
) -> float:
	if data.desiredDelta.length_squared() <= EPSILON:
		return 1.0

	return 1.0 - data.desiredDelta.normalized().dot(
		direction.normalized()
	)


func _FindAgent(
	unitId: int
) -> CollisionGroup.AgentData:
	for data: CollisionGroup.AgentData in _group.agents:
		if data.agent.unitId == unitId:
			return data

	return null


func _Overlap(
	firstPosition: Vector2,
	firstHalfSize: int,
	secondPosition: Vector2,
	secondHalfSize: int
) -> bool:
	var size: float = float(
		firstHalfSize
		+ secondHalfSize
	)

	return (
		absf(
			firstPosition.x
			- secondPosition.x
		) < size
		and absf(
			firstPosition.y
			- secondPosition.y
		) < size
	)
