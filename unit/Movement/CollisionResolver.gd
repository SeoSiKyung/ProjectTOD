class_name CollisionResolver
extends RefCounted


const EPSILON: float = 0.00001
const MIN_SPEED_RATIO: float = 0.1
const SLOW_STEP_COUNT: int = 10
const SAME_DIRECTION_DOT: float = 0.7

const AXIS_X: int = 0
const AXIS_Y: int = 1

const MODE_KEEP: int = 0
const MODE_SLOW: int = 1
const MODE_AXIS: int = 2
const MODE_SLIDE: int = 3
const MODE_STOP: int = 4


class Candidate:
	var position: Vector2
	var mode: int
	var speedRatio: float
	var directionLoss: float
	var keepSlide: bool


var _navigationService: NavigationService
var _group: CollisionGroup
var _fixedDelta: float


func _init(navigationService: NavigationService) -> void:
	_navigationService = navigationService


func Resolve(group: CollisionGroup, fixedDelta: float) -> bool:
	_group = group
	_fixedDelta = fixedDelta

	_updateIdleRelations()

	for pair: Vector2i in _group.collisions:
		var first: CollisionGroup.AgentData = _FindAgent(pair.x)
		var second: CollisionGroup.AgentData = _FindAgent(pair.y)

		if first == null or second == null:
			continue

		if not _Overlap(first.nextPosition, first.halfSize, second.nextPosition, second.halfSize):
			continue

		var result: Array = _resolvePair(first, second)

		if result.is_empty():
			continue

		first.nextPosition = result[0].position
		second.nextPosition = result[1].position

		_ApplySlideState(first, result[0])
		_ApplySlideState(second, result[1])

		return true

	return false


func _resolvePair(first: CollisionGroup.AgentData, second: CollisionGroup.AgentData) -> Array:
	if first.idle and second.idle:
		return []

	if first.idle:
		return _ReverseResult(_resolveMovingIdle(second, first))

	if second.idle:
		return _resolveMovingIdle(first, second)

	if _HasPersistentSlide(first) and not _HasNewIdle(first):
		return _resolvePersistentSlide(first, second)

	if _HasPersistentSlide(second) and not _HasNewIdle(second):
		return _ReverseResult(_resolvePersistentSlide(second, first))

	var rearFront: Array = _GetRearFront(first, second)

	if not rearFront.is_empty():
		return _resolveRearCollision(rearFront[0], rearFront[1], first, second)

	return _resolveGeneralCollision(first, second)


func _resolveMovingIdle(moving: CollisionGroup.AgentData, idle: CollisionGroup.AgentData) -> Array:
	var candidates: Array = _buildCandidates(moving, idle)

	for candidate: Candidate in candidates:
		if not _PairClear(moving, candidate.position, idle, idle.nextPosition):
			continue

		return [candidate, _idleCandidate(idle)]

	return []


func _resolvePersistentSlide(sliding: CollisionGroup.AgentData, other: CollisionGroup.AgentData) -> Array:
	var directions: Array = _GetPersistentSlideDirections(sliding.slideDirection)

	for direction: Vector2 in directions:
		var slideCandidate: Candidate = _slideCandidate(sliding, direction, true)

		if not _StaticClear(sliding, slideCandidate.position):
			continue

		if _PairClear(sliding, slideCandidate.position, other, other.nextPosition):
			return [slideCandidate, _keepCandidate(other)]

	var otherCandidates: Array = _buildCandidatesWithoutPersistentSlide(other)

	for direction: Vector2 in directions:
		var slideCandidate: Candidate = _slideCandidate(sliding, direction, true)

		if not _StaticClear(sliding, slideCandidate.position):
			continue

		for candidate: Candidate in otherCandidates:
			if _PairClear(sliding, slideCandidate.position, other, candidate.position):
				return [slideCandidate, candidate]

	return []


func _resolveRearCollision(rear: CollisionGroup.AgentData, front: CollisionGroup.AgentData, originalFirst: CollisionGroup.AgentData, originalSecond: CollisionGroup.AgentData) -> Array:
	var candidates: Array = _buildCandidates(rear, front)

	for candidate: Candidate in candidates:
		if not _PairClear(rear, candidate.position, front, front.nextPosition):
			continue

		var result: Array = [candidate, _keepCandidate(front)]

		if originalFirst == rear:
			return result

		return [result[1], result[0]]

	return []


func _resolveGeneralCollision(first: CollisionGroup.AgentData, second: CollisionGroup.AgentData) -> Array:
	var firstCandidates: Array = _buildCandidates(first, second)
	var secondCandidates: Array = _buildCandidates(second, first)

	return _findBestPair(first, firstCandidates, second, secondCandidates)


func _buildCandidates(data: CollisionGroup.AgentData, blocker: CollisionGroup.AgentData) -> Array:
	var result: Array = []

	if data.idle:
		result.append(_idleCandidate(data))
		return result

	if _HasPersistentSlide(data) and not _HasNewIdle(data):
		result.append(_slideCandidate(data, data.slideDirection, true))
		return result

	result.append(_keepCandidate(data))

	var slowCandidates: Array = _buildSlowCandidates(data)

	for candidate: Candidate in slowCandidates:
		result.append(candidate)

	var axisCandidates: Array = _buildAxisCandidates(data, blocker)

	for candidate: Candidate in axisCandidates:
		result.append(candidate)

	var alternateCandidates: Array = _buildAlternateCandidates(data)

	for candidate: Candidate in alternateCandidates:
		result.append(candidate)

	result.append(_stopCandidate(data))

	return result


func _buildCandidatesWithoutPersistentSlide(data: CollisionGroup.AgentData) -> Array:
	var result: Array = []

	if data.idle:
		result.append(_idleCandidate(data))
		return result

	result.append(_keepCandidate(data))

	var slowCandidates: Array = _buildSlowCandidates(data)

	for candidate: Candidate in slowCandidates:
		result.append(candidate)

	var axisCandidates: Array = _buildAxisCandidatesWithoutBlocker(data)

	for candidate: Candidate in axisCandidates:
		result.append(candidate)

	var alternateCandidates: Array = _buildAlternateCandidates(data)

	for candidate: Candidate in alternateCandidates:
		result.append(candidate)

	result.append(_stopCandidate(data))

	return result


func _buildSlowCandidates(data: CollisionGroup.AgentData) -> Array:
	var result: Array = []

	if data.desiredDelta.length_squared() <= EPSILON:
		return result

	var direction: Vector2 = data.desiredDelta.normalized()
	var distance: float = data.desiredDelta.length()

	for step: int in range(SLOW_STEP_COUNT - 1, 0, -1):
		var ratio: float = float(step) / float(SLOW_STEP_COUNT)
		ratio = maxf(ratio, MIN_SPEED_RATIO)

		var candidate: Candidate = Candidate.new()

		candidate.position = data.startPosition + direction * distance * ratio
		candidate.mode = MODE_SLOW
		candidate.speedRatio = ratio
		candidate.directionLoss = 0.0
		candidate.keepSlide = false

		result.append(candidate)

	return result


func _buildAxisCandidates(data: CollisionGroup.AgentData, blocker: CollisionGroup.AgentData) -> Array:
	var result: Array = []
	var blockedAxis: int = _GetBlockedAxis(data, blocker)
	var freeAxis: int = AXIS_Y if blockedAxis == AXIS_X else AXIS_X

	var direction: Vector2 = _getFreeAxisDirection(data, freeAxis)

	if direction.length_squared() <= EPSILON:
		return result

	var first: Candidate = _axisCandidate(data, direction)
	var second: Candidate = _axisCandidate(data, -direction)

	if _StaticClear(data, first.position):
		result.append(first)

	if _StaticClear(data, second.position):
		result.append(second)

	return result


func _buildAxisCandidatesWithoutBlocker(data: CollisionGroup.AgentData) -> Array:
	var result: Array = []

	if data.desiredDelta.length_squared() <= EPSILON:
		return result

	var firstDirection: Vector2

	if absf(data.desiredDelta.x) >= absf(data.desiredDelta.y):
		firstDirection = Vector2(0.0, signf(data.desiredDelta.y))

		if firstDirection.length_squared() <= EPSILON:
			firstDirection = Vector2.UP
	else:
		firstDirection = Vector2(signf(data.desiredDelta.x), 0.0)

	if firstDirection.length_squared() <= EPSILON:
		return result

	var first: Candidate = _axisCandidate(data, firstDirection)
	var second: Candidate = _axisCandidate(data, -firstDirection)

	result.append(first)
	result.append(second)

	return result


func _buildAlternateCandidates(data: CollisionGroup.AgentData) -> Array[Candidate]:
	var result: Array[Candidate] = []
	var directions: Array[Vector2] = [
		Vector2.RIGHT,
		Vector2.LEFT,
		Vector2.UP,
		Vector2.DOWN
	]

	directions.sort_custom(func(first: Vector2, second: Vector2) -> bool:
		return _DirectionLoss(data, first) < _DirectionLoss(data, second)
	)

	var keepSlide: bool = not data.currentIdleIds.is_empty()

	for direction: Vector2 in directions:
		result.append(_slideCandidate(data, direction, keepSlide))

	return result


func _axisCandidate(data: CollisionGroup.AgentData, direction: Vector2) -> Candidate:
	var candidate: Candidate = Candidate.new()

	candidate.position = data.startPosition + direction.normalized() * data.speed * _fixedDelta
	candidate.mode = MODE_AXIS
	candidate.speedRatio = 1.0
	candidate.directionLoss = _DirectionLoss(data, direction)
	candidate.keepSlide = not data.currentIdleIds.is_empty()

	return candidate


func _slideCandidate(data: CollisionGroup.AgentData, direction: Vector2, keepSlide: bool) -> Candidate:
	var candidate: Candidate = Candidate.new()

	candidate.position = data.startPosition + direction.normalized() * data.speed * _fixedDelta
	candidate.mode = MODE_SLIDE
	candidate.speedRatio = 1.0
	candidate.directionLoss = _DirectionLoss(data, direction)
	candidate.keepSlide = keepSlide

	return candidate


func _keepCandidate(data: CollisionGroup.AgentData) -> Candidate:
	var candidate: Candidate = Candidate.new()

	candidate.position = data.desiredPosition
	candidate.mode = MODE_KEEP
	candidate.speedRatio = _SpeedRatio(data, candidate.position)
	candidate.directionLoss = 0.0
	candidate.keepSlide = data.slideDirection.length_squared() > EPSILON

	return candidate


func _idleCandidate(data: CollisionGroup.AgentData) -> Candidate:
	var candidate: Candidate = Candidate.new()

	candidate.position = data.nextPosition
	candidate.mode = MODE_KEEP
	candidate.speedRatio = 0.0
	candidate.directionLoss = 0.0
	candidate.keepSlide = false

	return candidate


func _stopCandidate(data: CollisionGroup.AgentData) -> Candidate:
	var candidate: Candidate = Candidate.new()

	candidate.position = data.startPosition
	candidate.mode = MODE_STOP
	candidate.speedRatio = 0.0
	candidate.directionLoss = 1.0
	candidate.keepSlide = false

	return candidate


func _findBestPair(first: CollisionGroup.AgentData, firstCandidates: Array, second: CollisionGroup.AgentData, secondCandidates: Array) -> Array:
	var best: Array = []
	var bestCost: int = 999
	var bestSpeed: float = -1.0
	var bestLoss: float = INF

	for firstCandidate: Candidate in firstCandidates:
		for secondCandidate: Candidate in secondCandidates:
			if not _PairClear(first, firstCandidate.position, second, secondCandidate.position):
				continue

			var cost: int = firstCandidate.mode + secondCandidate.mode
			var speed: float = firstCandidate.speedRatio + secondCandidate.speedRatio
			var loss: float = firstCandidate.directionLoss + secondCandidate.directionLoss

			if cost < bestCost:
				best = [firstCandidate, secondCandidate]
				bestCost = cost
				bestSpeed = speed
				bestLoss = loss
				continue

			if cost > bestCost:
				continue

			if speed > bestSpeed:
				best = [firstCandidate, secondCandidate]
				bestSpeed = speed
				bestLoss = loss
				continue

			if is_equal_approx(speed, bestSpeed) and loss < bestLoss:
				best = [firstCandidate, secondCandidate]
				bestLoss = loss

	return best


func _PairClear(first: CollisionGroup.AgentData, firstPosition: Vector2, second: CollisionGroup.AgentData, secondPosition: Vector2) -> bool:
	if not _StaticClear(first, firstPosition):
		return false

	if not _StaticClear(second, secondPosition):
		return false

	if _Overlap(firstPosition, first.halfSize, secondPosition, second.halfSize):
		return false

	for other: CollisionGroup.AgentData in _group.agents:
		if other == first or other == second:
			continue

		if _Overlap(firstPosition, first.halfSize, other.nextPosition, other.halfSize):
			return false

		if _Overlap(secondPosition, second.halfSize, other.nextPosition, other.halfSize):
			return false

	return true


func _StaticClear(data: CollisionGroup.AgentData, position: Vector2) -> bool:
	if _navigationService == null:
		return true

	return _navigationService.SegmentClear(
		data.startPosition,
		position,
		data.halfSize
	)


func _GetBlockedAxis(data: CollisionGroup.AgentData, blocker: CollisionGroup.AgentData) -> int:
	var relative: Vector2 = blocker.nextPosition - data.nextPosition

	if absf(relative.x) > absf(relative.y):
		return AXIS_X

	if absf(relative.y) > absf(relative.x):
		return AXIS_Y

	if absf(data.desiredDelta.x) >= absf(data.desiredDelta.y):
		return AXIS_X

	return AXIS_Y


func _getFreeAxisDirection(data: CollisionGroup.AgentData, axis: int) -> Vector2:
	if axis == AXIS_X:
		if absf(data.desiredDelta.x) > EPSILON:
			return Vector2(signf(data.desiredDelta.x), 0.0)

		return Vector2.RIGHT

	if absf(data.desiredDelta.y) > EPSILON:
		return Vector2(0.0, signf(data.desiredDelta.y))

	return Vector2.DOWN


func _GetRearFront(first: CollisionGroup.AgentData, second: CollisionGroup.AgentData) -> Array:
	if first.desiredDelta.length_squared() <= EPSILON:
		return []

	if second.desiredDelta.length_squared() <= EPSILON:
		return []

	var firstDirection: Vector2 = first.desiredDelta.normalized()
	var secondDirection: Vector2 = second.desiredDelta.normalized()

	if firstDirection.dot(secondDirection) < SAME_DIRECTION_DOT:
		return []

	var direction: Vector2 = (
		firstDirection + secondDirection
	).normalized()

	if direction.length_squared() <= EPSILON:
		direction = firstDirection

	var relative: Vector2 = second.nextPosition - first.nextPosition
	var forward: float = relative.dot(direction)
	var lateral: float = absf(relative.cross(direction))

	if absf(forward) <= EPSILON:
		return []

	if lateral >= absf(forward):
		return []

	if forward > 0.0:
		return [first, second]

	return [second, first]


func _HasPersistentSlide(data: CollisionGroup.AgentData) -> bool:
	return data.slideDirection.length_squared() > EPSILON


func _HasNewIdle(data: CollisionGroup.AgentData) -> bool:
	for idleId in data.currentIdleIds:
		if not data.slideIdleIds.has(idleId):
			return true

	return false


func _ApplySlideState(data: CollisionGroup.AgentData, candidate: Candidate) -> void:
	if not candidate.keepSlide:
		if data.currentIdleIds.is_empty():
			data.slideDirection = Vector2.ZERO

		return

	var delta: Vector2 = candidate.position - data.startPosition

	if delta.length_squared() <= EPSILON:
		return

	data.slideDirection = delta.normalized()


func _SpeedRatio(data: CollisionGroup.AgentData, position: Vector2) -> float:
	var desiredDistance: float = data.desiredDelta.length()

	if desiredDistance <= EPSILON:
		return 0.0

	return clampf(
		position.distance_to(data.startPosition) / desiredDistance,
		0.0,
		1.0
	)


func _DirectionLoss(data: CollisionGroup.AgentData, direction: Vector2) -> float:
	if data.desiredDelta.length_squared() <= EPSILON:
		return 1.0

	return 1.0 - data.desiredDelta.normalized().dot(direction.normalized())


func _updateIdleRelations() -> void:
	for data: CollisionGroup.AgentData in _group.agents:
		data.currentIdleIds.clear()

	for pair: Vector2i in _group.collisions:
		var first: CollisionGroup.AgentData = _FindAgent(pair.x)
		var second: CollisionGroup.AgentData = _FindAgent(pair.y)

		if first == null or second == null:
			continue

		if first.idle and not second.idle:
			second.currentIdleIds.append(first.agent.unitId)

		elif second.idle and not first.idle:
			first.currentIdleIds.append(second.agent.unitId)


func _ReverseResult(result: Array) -> Array:
	if result.is_empty():
		return []

	return [result[1], result[0]]


func _FindAgent(unitId: int) -> CollisionGroup.AgentData:
	for data: CollisionGroup.AgentData in _group.agents:
		if data.agent.unitId == unitId:
			return data

	return null


func _Overlap(firstPosition: Vector2, firstHalfSize: int, secondPosition: Vector2, secondHalfSize: int) -> bool:
	var size: float = float(firstHalfSize + secondHalfSize)

	return (
		absf(firstPosition.x - secondPosition.x) < size
		and absf(firstPosition.y - secondPosition.y) < size
	)

func _GetPersistentSlideDirections(currentDirection: Vector2) -> Array:
	if currentDirection.length_squared() <= EPSILON:
		return []

	var direction: Vector2 = currentDirection.normalized()

	return [
		direction,
		-direction,
		Vector2(-direction.y, direction.x),
		Vector2(direction.y, -direction.x)
	]
