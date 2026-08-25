class_name MovementSimulator
extends Node

const EPSILON: float = 0.00001
const COLLISION_EPSILON: float = 0.0001
const PAIR_MEMORY_TICKS: int = 90
const AVOID_PRIMARY_ANGLE: float = 0.78539816339
const AVOID_SMALL_ANGLE: float = 0.3490658504
const AVOID_MEDIUM_ANGLE: float = 0.5235987756
const AVOID_LARGE_ANGLE: float = 1.0471975512
const AVOID_WIDE_ANGLE: float = 1.308996939
const AVOID_SIDE_ANGLE: float = 1.57079632679
const AVOID_REAR_SOFT_ANGLE: float = 2.09439510239
const AVOID_REAR_MEDIUM_ANGLE: float = 2.35619449019
const AVOID_REAR_WIDE_ANGLE: float = 2.61799387799
const AVOID_REVERSE_ANGLE: float = 3.14159265359
const ARRIVAL_MAX_AVOID_ANGLE: float = 1.0471975512
const STATIC_BLOCKER_STEP_THRESHOLD: float = 0.25
const NEIGHBOR_MARGIN: float = 8.0
const REPATH_RETRY_TICKS: int = 4
const REPATH_GOAL_TOLERANCE: float = 2.0
const MOTION_BLOCKED: int = 0
const MOTION_RESOLVED: int = 1
const MOTION_MAP_BLOCKED: int = 2

@export var navigationService: NavigationService

@export_range(30, 240, 1)
var fixedTickRate: int = 60

@export var simulationQuantum: float = 1.0 / 1024.0
@export var candidateSpatialCellSize: float = 64.0
@export_range(0.8, 1.0, 0.1) var minAvoidSpeedRatio: float = 0.8
@export_range(0.0, 1.0, 0.05) var avoidPreviousVelocityWeight: float = 0.45
@export_range(0.0, 1.0, 0.05) var avoidSideChangePenalty: float = 0.2

var simulationTick: int = 0

var _units: Dictionary[int, Unit] = { }
var _sortedUnitIds: Array[int] = []
var _orders: Dictionary[int, MoveOrder] = { }
var _avoidanceByUnit: Dictionary[int, AvoidancePlan] = { }
var _pairMemory: Dictionary[Vector2i, PairMemory] = { }
var _nextRepathTickByUnit: Dictionary[int, int] = { }

var _cachedAvoidSpeedRatios: Array[float] = []
var _cachedMinAvoidSpeedRatio: float = -1.0


class Snapshot:
	var unitId: int = -1
	var position: Vector2 = Vector2.ZERO
	var halfSize: Vector2 = Vector2.ZERO


class AvoidancePlan:
	var otherId: int = -1
	var side: int = 1
	var selectedAngle: float = 0.78539816339


class PairMemory:
	var lowId: int = -1
	var highId: int = -1
	var lowSide: int = 1
	var highSide: int = 1
	var lastTick: int = 0


func _ready() -> void:
	Engine.physics_ticks_per_second = fixedTickRate

	if navigationService == null:
		var parent: Node = get_parent()

		if parent != null:
			var node: Node = parent.get_node_or_null("NavigationService")

			if node is NavigationService:
				navigationService = node as NavigationService

	call_deferred("_RegisterSceneUnits")


func _physics_process(delta: float) -> void:
	if navigationService == null:
		return

	if not navigationService.IsReady():
		return

	var dt: float = 1.0 / float(fixedTickRate)
	simulationTick += 1
	_CleanupPairMemory()

	var orderIds: Array[int] = []

	for orderId: int in _orders:
		orderIds.append(orderId)

	orderIds.sort()

	var candidates: Array[MoveOrder.MovementCandidate] = []

	for orderId: int in orderIds:
		if not _orders.has(orderId):
			continue

		var order: MoveOrder = _orders[orderId]

		if simulationTick < order.issuedTick:
			continue

		var orderCandidates: Array[MoveOrder.MovementCandidate] = order.Simulate(dt, _units)

		for candidate: MoveOrder.MovementCandidate in orderCandidates:
			candidates.append(candidate)

	_ResolveCandidates(candidates, dt)
	_CommitCandidates(candidates)
	_CleanupFinishedOrders()


func AddMoveOrder(order: MoveOrder) -> void:
	if order == null:
		return

	if _orders.has(order.orderId):
		push_error("중복 MoveOrder ID: %d" % order.orderId)
		return

	for unitId: int in order.memberIds:
		if not _units.has(unitId):
			continue

		_avoidanceByUnit.erase(unitId)
		_nextRepathTickByUnit.erase(unitId)
		var unit: Unit = _units[unitId]

		if unit.movement.activeMoveOrder != null:
			unit.movement.Stop()

	_orders[order.orderId] = order
	order.Start(_units)


func StopUnits(unitIds: Array[int]) -> void:
	for unitId: int in unitIds:
		if not _units.has(unitId):
			continue

		_avoidanceByUnit.erase(unitId)
		_nextRepathTickByUnit.erase(unitId)
		_units[unitId].movement.Stop()

	_CleanupFinishedOrders()


func RegisterUnit(unit: Unit) -> void:
	if unit == null:
		return

	if _units.has(unit.unitId):
		var existing: Unit = _units[unit.unitId]

		if existing == unit:
			return

		push_error("중복 unitId: %d" % unit.unitId)
		return

	if unit.movement == null:
		push_error("Unit %d에 MovementComponent가 없습니다." % unit.unitId)
		return

	_units[unit.unitId] = unit
	unit.movement.BindUnit(unit)
	_RebuildSortedUnitIds()


func UnregisterUnit(unit: Unit) -> void:
	if unit == null:
		return

	if not _units.has(unit.unitId):
		return

	if _units[unit.unitId] != unit:
		return

	_units.erase(unit.unitId)
	_avoidanceByUnit.erase(unit.unitId)
	_nextRepathTickByUnit.erase(unit.unitId)
	_RebuildSortedUnitIds()


func GetUnit(unitId: int) -> Unit:
	if not _units.has(unitId):
		return null

	return _units[unitId]


func _RegisterSceneUnits() -> void:
	var nodes: Array[Node] = get_tree().get_nodes_in_group("unit")

	for node: Node in nodes:
		if node is Unit:
			RegisterUnit(node as Unit)


func _RebuildSortedUnitIds() -> void:
	_sortedUnitIds.clear()

	for unitId: int in _units:
		_sortedUnitIds.append(unitId)

	_sortedUnitIds.sort()


func _CleanupFinishedOrders() -> void:
	var removeIds: Array[int] = []

	for orderId: int in _orders:
		var order: MoveOrder = _orders[orderId]

		if order.IsFinished(_units):
			removeIds.append(orderId)

	for orderId: int in removeIds:
		_orders.erase(orderId)


func _ResolveCandidates(candidates: Array[MoveOrder.MovementCandidate], dt: float) -> void:
	if candidates.is_empty():
		return

	var candidateById: Dictionary[int, MoveOrder.MovementCandidate] = { }

	for candidate: MoveOrder.MovementCandidate in candidates:
		candidateById[candidate.unitId] = candidate
		candidate.desiredPosition = _QuantizeVec(candidate.desiredPosition)
		candidate.position = candidate.desiredPosition
		candidate.velocity = (candidate.position - candidate.startPosition) / maxf(dt, EPSILON)

	var maxMoveDistance: float = 0.0
	var maxHalf: Vector2 = Vector2.ZERO

	for unitId: int in _sortedUnitIds:
		var unit: Unit = _units[unitId]
		maxMoveDistance = maxf(maxMoveDistance, unit.movement.moveSpeed * dt)
		var halfSize: Vector2 = unit.GetHalfSize()
		maxHalf.x = maxf(maxHalf.x, halfSize.x)
		maxHalf.y = maxf(maxHalf.y, halfSize.y)

	var spatial: Dictionary = _BuildStartSpatialHash()
	var neighborsById: Dictionary[int, Array] = { }

	for candidate: MoveOrder.MovementCandidate in candidates:
		var ownMove: float = maxf(candidate.maxStepDistance, candidate.desiredStepDistance)
		var extent: Vector2 = Vector2(
			candidate.halfSize.x + maxHalf.x + ownMove + maxMoveDistance + NEIGHBOR_MARGIN,
			candidate.halfSize.y + maxHalf.y + ownMove + maxMoveDistance + NEIGHBOR_MARGIN,
		)
		neighborsById[candidate.unitId] = _QueryStartSpatial(
			spatial,
			candidate.startPosition,
			extent,
			candidate.unitId,
		)

	var freedomById: Dictionary[int, int] = { }
	var targetDistanceById: Dictionary[int, float] = { }

	for candidate: MoveOrder.MovementCandidate in candidates:
		freedomById[candidate.unitId] = _ReservationMapFreedom(candidate, dt)
		targetDistanceById[candidate.unitId] = _ReservationTargetDistance(candidate)

	var sortedCandidates: Array[MoveOrder.MovementCandidate] = candidates.duplicate()
	sortedCandidates.sort_custom(
		func(a: MoveOrder.MovementCandidate, b: MoveOrder.MovementCandidate) -> bool:
			var aFreedom: int = freedomById[a.unitId]
			var bFreedom: int = freedomById[b.unitId]

			if aFreedom != bFreedom:
				return aFreedom < bFreedom

			var aDistance: float = targetDistanceById[a.unitId]
			var bDistance: float = targetDistanceById[b.unitId]

			if absf(aDistance - bDistance) > EPSILON:
				return aDistance < bDistance

			if a.priority != b.priority:
				return a.priority < b.priority

			return a.unitId < b.unitId,
	)

	var workingSnapshots: Dictionary[int, Snapshot] = _BuildCurrentSnapshots()

	for candidate: MoveOrder.MovementCandidate in sortedCandidates:
		var neighbors: Array = neighborsById[candidate.unitId]
		var directMapClear: bool = _MapSegmentClear(candidate, candidate.desiredPosition)
		var blockerId: int = _FirstUnitBlocker(
			candidate,
			candidate.desiredPosition,
			workingSnapshots,
			neighbors,
		)

		if directMapClear and blockerId < 0:
			_avoidanceByUnit.erase(candidate.unitId)
			_ApplyPosition(candidate, candidate.desiredPosition, dt, candidate.finishOrder)
			_UpdateSnapshot(workingSnapshots, candidate)
			continue

		if (
			directMapClear and _TryApplyStraightSlowdown(candidate, workingSnapshots, neighbors, dt)
		):
			_avoidanceByUnit.erase(candidate.unitId)
			_UpdateSnapshot(workingSnapshots, candidate)
			continue

		_PrepareReservationPlan(candidate, blockerId, candidateById, dt)

		var nearArrival: bool = _CandidateNearArrival(candidate)
		var restrictArrivalAvoidance: bool = nearArrival and directMapClear
		var resolution: int = _ResolveUnitMotion(
			candidate,
			workingSnapshots,
			neighbors,
			dt,
			restrictArrivalAvoidance,
		)

		if resolution == MOTION_MAP_BLOCKED:
			_avoidanceByUnit.erase(candidate.unitId)
			_HandleMapBlockedCandidate(candidate, dt)
			_StopCandidate(candidate, dt)
		elif resolution != MOTION_RESOLVED:
			_StopCandidate(candidate, dt)

		_UpdateSnapshot(workingSnapshots, candidate)


func _ReservationMapFreedom(candidate: MoveOrder.MovementCandidate, dt: float) -> int:
	var baseDirection: Vector2 = _CandidateBaseDirection(candidate)

	if baseDirection == Vector2.ZERO:
		return 0

	var stepDistance: float = candidate.maxStepDistance

	if candidate.finalTick:
		stepDistance = candidate.desiredStepDistance

	if stepDistance <= EPSILON:
		return 0

	var angles: Array[float] = [
		0.0,
		AVOID_MEDIUM_ANGLE,
		-AVOID_MEDIUM_ANGLE,
		AVOID_PRIMARY_ANGLE,
		-AVOID_PRIMARY_ANGLE,
		AVOID_SIDE_ANGLE,
		-AVOID_SIDE_ANGLE,
	]
	var count: int = 0

	for angle: float in angles:
		var position: Vector2 = _QuantizeVec(
			candidate.startPosition + baseDirection.rotated(angle) * stepDistance
		)

		if _MapSegmentClear(candidate, position):
			count += 1

	return count


func _ReservationTargetDistance(candidate: MoveOrder.MovementCandidate) -> float:
	var target: Vector2 = candidate.targetPosition

	if target == Vector2.ZERO:
		target = candidate.desiredPosition

	return candidate.startPosition.distance_squared_to(target)


func _FirstUnitBlocker(
	candidate: MoveOrder.MovementCandidate,
	position: Vector2,
	snapshots: Dictionary[int, Snapshot],
	neighbors: Array,
) -> int:
	var blockerId: int = -1
	var bestDistance: float = 1.0e30

	for value: Variant in neighbors:
		var otherId: int = int(value)

		if not snapshots.has(otherId):
			continue

		var other: Snapshot = snapshots[otherId]

		if not _RectanglesOverlapStrict(
			position,
			candidate.halfSize,
			other.position,
			other.halfSize,
		):
			continue

		var distance: float = position.distance_squared_to(other.position)

		if distance >= bestDistance:
			continue

		bestDistance = distance
		blockerId = otherId

	return blockerId


func _PrepareReservationPlan(
	candidate: MoveOrder.MovementCandidate,
	blockerId: int,
	candidateById: Dictionary[int, MoveOrder.MovementCandidate],
	dt: float,
) -> void:
	if blockerId < 0:
		_avoidanceByUnit.erase(candidate.unitId)
		return

	var side: int = _ReservationPreferredSide(candidate, blockerId, candidateById, dt)

	if _avoidanceByUnit.has(candidate.unitId):
		var existing: AvoidancePlan = _avoidanceByUnit[candidate.unitId]

		if existing.otherId == blockerId:
			existing.side = side

			if (
				absf(existing.selectedAngle) <= EPSILON
				or existing.selectedAngle * float(side) < 0.0
			):
				existing.selectedAngle = AVOID_PRIMARY_ANGLE * float(side)

			return

	var plan: AvoidancePlan = AvoidancePlan.new()
	plan.otherId = blockerId
	plan.side = side
	plan.selectedAngle = AVOID_PRIMARY_ANGLE * float(side)
	_avoidanceByUnit[candidate.unitId] = plan


func _ReservationPreferredSide(
	candidate: MoveOrder.MovementCandidate,
	blockerId: int,
	candidateById: Dictionary[int, MoveOrder.MovementCandidate],
	dt: float,
) -> int:
	var baseDirection: Vector2 = _CandidateBaseDirection(candidate)

	if baseDirection == Vector2.ZERO:
		return 1 if candidate.unitId % 2 == 0 else -1

	var right: Vector2 = Vector2(-baseDirection.y, baseDirection.x)

	if _units.has(candidate.unitId):
		var movement: MovementComponent = _units[candidate.unitId].movement
		var previousVelocity: Vector2 = movement.simVelocity
		var lateralSpeed: float = previousVelocity.dot(right)
		var lateralThreshold: float = maxf(1.0, movement.moveSpeed * 0.08)

		if absf(lateralSpeed) >= lateralThreshold:
			var previousSide: int = 1 if lateralSpeed > 0.0 else -1

			if _ReservationSideHasMapMotion(candidate, baseDirection, previousSide, dt):
				return previousSide

	if _avoidanceByUnit.has(candidate.unitId):
		var existing: AvoidancePlan = _avoidanceByUnit[candidate.unitId]

		if existing.otherId == blockerId:
			var existingSide: int = 1 if existing.side >= 0 else -1

			if _ReservationSideHasMapMotion(candidate, baseDirection, existingSide, dt):
				return existingSide

	var memory: PairMemory = _GetPairMemory(candidate.unitId, blockerId, candidateById)
	var memorySide: int = memory.lowSide if candidate.unitId == memory.lowId else memory.highSide

	if _ReservationSideHasMapMotion(candidate, baseDirection, memorySide, dt):
		return memorySide

	var oppositeSide: int = -memorySide

	if _ReservationSideHasMapMotion(candidate, baseDirection, oppositeSide, dt):
		return oppositeSide

	return memorySide


func _ReservationSideHasMapMotion(
	candidate: MoveOrder.MovementCandidate,
	baseDirection: Vector2,
	side: int,
	dt: float,
) -> bool:
	var stepDistance: float = candidate.maxStepDistance

	if candidate.finalTick:
		stepDistance = candidate.desiredStepDistance

	if stepDistance <= EPSILON:
		return false

	var sideValue: float = 1.0 if side >= 0 else -1.0
	var angles: Array[float] = [
		AVOID_SMALL_ANGLE,
		AVOID_MEDIUM_ANGLE,
		AVOID_PRIMARY_ANGLE,
		AVOID_LARGE_ANGLE,
		AVOID_WIDE_ANGLE,
		AVOID_SIDE_ANGLE,
		AVOID_REAR_SOFT_ANGLE,
	]

	for angle: float in angles:
		for speedRatio: float in _AvoidSpeedRatios():
			var position: Vector2 = _QuantizeVec(
				candidate.startPosition
				+ baseDirection.rotated(angle * sideValue) * stepDistance * speedRatio
			)

			if _MapSegmentClear(candidate, position):
				return true

	return false


func _BuildCurrentSnapshots() -> Dictionary:
	var result: Dictionary[int, Snapshot] = { }

	for unitId: int in _sortedUnitIds:
		var unit: Unit = _units[unitId]
		var snapshot: Snapshot = Snapshot.new()
		snapshot.unitId = unitId
		snapshot.position = unit.position
		snapshot.halfSize = unit.GetHalfSize()
		result[unitId] = snapshot

	return result


func _HandleMapBlockedCandidate(candidate: MoveOrder.MovementCandidate, dt: float) -> void:
	_RepathCandidate(candidate, dt)


func _RepathCandidate(candidate: MoveOrder.MovementCandidate, dt: float) -> bool:
	if not _units.has(candidate.unitId):
		return false

	if _nextRepathTickByUnit.has(candidate.unitId):
		if simulationTick < _nextRepathTickByUnit[candidate.unitId]:
			return false

	var unit: Unit = _units[candidate.unitId]
	var movement: MovementComponent = unit.movement

	if movement == null or movement.activeMoveOrder == null:
		return false

	if movement.activeMoveOrder.orderId != candidate.orderId:
		return false

	var goal: Vector2 = movement.GetEffectiveGoal()

	if candidate.arrivalActive:
		goal = candidate.arrivalSlot

	var path: PackedVector2Array = navigationService.FindPath(
		candidate.startPosition,
		goal,
		candidate.halfSize,
	)

	if path.is_empty():
		_nextRepathTickByUnit[candidate.unitId] = simulationTick + REPATH_RETRY_TICKS
		return false

	var pathGoal: Vector2 = path[path.size() - 1]

	if pathGoal.distance_to(goal) > REPATH_GOAL_TOLERANCE:
		_nextRepathTickByUnit[candidate.unitId] = simulationTick + REPATH_RETRY_TICKS
		return false

	if not movement.ReplacePath(path, goal):
		_nextRepathTickByUnit[candidate.unitId] = simulationTick + REPATH_RETRY_TICKS
		return false

	movement.ResetSimVelocity()
	movement.SyncPathProgress(movement.moveSpeed * dt, navigationService)
	_avoidanceByUnit.erase(candidate.unitId)
	_nextRepathTickByUnit.erase(candidate.unitId)
	_RefreshCandidateFromMovement(candidate, movement, dt)
	return _MapSegmentClear(candidate, candidate.desiredPosition)


func _RefreshCandidateFromMovement(
	candidate: MoveOrder.MovementCandidate,
	movement: MovementComponent,
	dt: float,
) -> void:
	var desiredVelocity: Vector2 = movement.GetDesiredVelocity(dt)
	var desiredPosition: Vector2 = candidate.startPosition + desiredVelocity * dt
	var finalTick: bool = movement.WantsFinalTick(dt)

	if finalTick:
		desiredPosition = movement.GetEffectiveGoal()

		if dt > EPSILON:
			desiredVelocity = (desiredPosition - candidate.startPosition) / dt

	candidate.desiredVelocity = desiredVelocity
	candidate.desiredPosition = _QuantizeVec(desiredPosition)
	candidate.position = candidate.desiredPosition
	candidate.velocity = (candidate.position - candidate.startPosition) / dt
	candidate.targetPosition = movement.GetCurrentWaypoint()
	candidate.desiredStepDistance = candidate.startPosition.distance_to(candidate.desiredPosition)
	candidate.finalTick = finalTick
	candidate.finishOrder = finalTick
	candidate.arrivalDistance = candidate.startPosition.distance_to(candidate.arrivalSlot)


func _StopCandidate(candidate: MoveOrder.MovementCandidate, dt: float) -> void:
	_ApplyPosition(candidate, candidate.startPosition, dt, false)


func _CandidateActivelyMoving(
	unitId: int,
	candidateById: Dictionary[int, MoveOrder.MovementCandidate],
) -> bool:
	if not candidateById.has(unitId):
		return false

	var candidate: MoveOrder.MovementCandidate = candidateById[unitId]

	if candidate.desiredStepDistance > STATIC_BLOCKER_STEP_THRESHOLD:
		return true

	return candidate.desiredVelocity.length() > STATIC_BLOCKER_STEP_THRESHOLD


func _GetPairMemory(
	aId: int,
	bId: int,
	candidateById: Dictionary[int, MoveOrder.MovementCandidate],
) -> PairMemory:
	var lowId: int = mini(aId, bId)
	var highId: int = maxi(aId, bId)
	var key: Vector2i = _PairKey(lowId, highId)

	if _pairMemory.has(key):
		var existing: PairMemory = _pairMemory[key]
		existing.lastTick = simulationTick
		return existing

	var memory: PairMemory = PairMemory.new()
	memory.lowId = lowId
	memory.highId = highId
	memory.lastTick = simulationTick

	var sides: Vector2i = _ChoosePairSides(lowId, highId, candidateById)
	memory.lowSide = sides.x
	memory.highSide = sides.y

	_pairMemory[key] = memory
	return memory


func _ChoosePairSides(
	lowId: int,
	highId: int,
	candidateById: Dictionary[int, MoveOrder.MovementCandidate],
) -> Vector2i:
	var lowMoving: bool = _CandidateActivelyMoving(lowId, candidateById)
	var highMoving: bool = _CandidateActivelyMoving(highId, candidateById)

	if lowMoving and not highMoving:
		return Vector2i(_SideAwayFromUnit(candidateById[lowId], highId), 1)

	if highMoving and not lowMoving:
		return Vector2i(1, _SideAwayFromUnit(candidateById[highId], lowId))

	if not lowMoving or not highMoving:
		return Vector2i(1, 1)

	var a: MoveOrder.MovementCandidate = candidateById[lowId]
	var b: MoveOrder.MovementCandidate = candidateById[highId]

	var aDir: Vector2 = _CandidateBaseDirection(a)
	var bDir: Vector2 = _CandidateBaseDirection(b)

	if aDir == Vector2.ZERO or bDir == Vector2.ZERO:
		return Vector2i(1, -1)

	var combinations: Array[Vector2i] = [
		Vector2i(1, 1),
		Vector2i(1, -1),
		Vector2i(-1, 1),
		Vector2i(-1, -1),
	]

	var best: Vector2i = combinations[0]
	var bestScore: float = -1.0e30
	var aStep: float = maxf(a.maxStepDistance, a.desiredStepDistance)
	var bStep: float = maxf(b.maxStepDistance, b.desiredStepDistance)
	var aMapClear: Dictionary[int, bool] = { }
	var bMapClear: Dictionary[int, bool] = { }

	for side: int in [-1, 1]:
		var aTest: Vector2 = (
			a.startPosition + aDir.rotated(AVOID_PRIMARY_ANGLE * float(side)) * aStep
		)
		var bTest: Vector2 = (
			b.startPosition + bDir.rotated(AVOID_PRIMARY_ANGLE * float(side)) * bStep
		)

		aMapClear[side] = navigationService.SegmentClear(a.startPosition, aTest, a.halfSize)
		bMapClear[side] = navigationService.SegmentClear(b.startPosition, bTest, b.halfSize)

	for combination: Vector2i in combinations:
		var aEnd: Vector2 = (
			a.startPosition + aDir.rotated(AVOID_PRIMARY_ANGLE * float(combination.x)) * aStep
		)
		var bEnd: Vector2 = (
			b.startPosition + bDir.rotated(AVOID_PRIMARY_ANGLE * float(combination.y)) * bStep
		)

		var dx: float = (absf(aEnd.x - bEnd.x) / maxf(a.halfSize.x + b.halfSize.x, EPSILON))
		var dy: float = (absf(aEnd.y - bEnd.y) / maxf(a.halfSize.y + b.halfSize.y, EPSILON))
		var score: float = maxf(dx, dy) * 10.0 + minf(dx, dy)

		if not aMapClear[combination.x]:
			score -= 1000000.0

		if not bMapClear[combination.y]:
			score -= 1000000.0

		if combination.x == combination.y:
			score += 0.01

		if score > bestScore + EPSILON:
			bestScore = score
			best = combination

	return best


func _SideAwayFromUnit(candidate: MoveOrder.MovementCandidate, otherId: int) -> int:
	if not _units.has(otherId):
		return 1

	var direction: Vector2 = _CandidateBaseDirection(candidate)

	if direction == Vector2.ZERO:
		return 1 if candidate.unitId < otherId else -1

	var right: Vector2 = Vector2(-direction.y, direction.x)
	var lateral: float = (_units[otherId].position - candidate.startPosition).dot(right)

	var preferred: int = 1

	if absf(lateral) <= 0.25:
		preferred = 1 if candidate.unitId < otherId else -1
	else:
		preferred = -1 if lateral > 0.0 else 1

	var stepDistance: float = maxf(candidate.maxStepDistance, candidate.desiredStepDistance)
	var preferredEnd: Vector2 = (
		candidate.startPosition
		+ direction.rotated(AVOID_PRIMARY_ANGLE * float(preferred)) * stepDistance
	)

	if navigationService.SegmentClear(candidate.startPosition, preferredEnd, candidate.halfSize):
		return preferred

	var opposite: int = -preferred
	var oppositeEnd: Vector2 = (
		candidate.startPosition
		+ direction.rotated(AVOID_PRIMARY_ANGLE * float(opposite)) * stepDistance
	)

	if navigationService.SegmentClear(candidate.startPosition, oppositeEnd, candidate.halfSize):
		return opposite

	return preferred


func _ResolveUnitMotion(
	candidate: MoveOrder.MovementCandidate,
	workingSnapshots: Dictionary[int, Snapshot],
	neighbors: Array,
	dt: float,
	nearArrival: bool,
) -> int:
	var plan: AvoidancePlan = null

	if _avoidanceByUnit.has(candidate.unitId):
		plan = _avoidanceByUnit[candidate.unitId]

	var baseDirection: Vector2 = _CandidateBaseDirection(candidate)

	if baseDirection == Vector2.ZERO:
		return MOTION_BLOCKED

	var stepDistance: float = candidate.maxStepDistance

	if candidate.finalTick and nearArrival:
		stepDistance = candidate.desiredStepDistance

	if stepDistance <= EPSILON:
		return MOTION_BLOCKED

	var angleSets: Array = []

	if plan != null:
		angleSets.append(_AnglesForPlan(plan, nearArrival))
		angleSets.append(_AnglesForSide(-plan.side, nearArrival))
	else:
		angleSets.append(_AnglesWithoutPlan(candidate.unitId, nearArrival))

	var speedRatios: Array[float] = _AvoidSpeedRatios()
	var preferredSpeed: float = stepDistance / maxf(dt, EPSILON)
	var preferredVelocity: Vector2 = baseDirection * preferredSpeed
	var previousVelocity: Vector2 = Vector2.ZERO

	if _units.has(candidate.unitId):
		previousVelocity = _units[candidate.unitId].movement.simVelocity

	var mapBlockedCandidateFound: bool = false
	var mapClearCandidateFound: bool = false
	var bestPosition: Vector2 = candidate.startPosition
	var bestAngle: float = 0.0
	var bestRatio: float = 0.0
	var bestFinish: bool = false

	for setIndex: int in range(angleSets.size()):
		var angles: Array = angleSets[setIndex]
		var setBestScore: float = 1.0e30
		var setBestPosition: Vector2 = candidate.startPosition
		var setBestAngle: float = 0.0
		var setBestRatio: float = 0.0
		var setBestFinish: bool = false

		for angleValue: Variant in angles:
			var angle: float = float(angleValue)
			var direction: Vector2 = baseDirection.rotated(angle)

			for speedRatio: float in speedRatios:
				var position: Vector2 = _QuantizeVec(
					candidate.startPosition + direction * stepDistance * speedRatio
				)

				if nearArrival and not _MakesArrivalProgress(candidate, position):
					continue

				if not _MapSegmentClear(candidate, position):
					mapBlockedCandidateFound = true
					continue

				mapClearCandidateFound = true

				if not _PositionClearOfUnits(candidate, position, workingSnapshots, neighbors):
					continue

				var velocity: Vector2 = ((position - candidate.startPosition) / maxf(dt, EPSILON))
				var score: float = _VelocityCandidateScore(
					candidate,
					velocity,
					preferredVelocity,
					previousVelocity,
					angle,
					speedRatio,
					plan,
				)

				if score >= setBestScore - EPSILON:
					continue

				setBestScore = score
				setBestPosition = position
				setBestAngle = angle
				setBestRatio = speedRatio
				setBestFinish = (
					candidate.finishOrder and absf(angle) <= EPSILON and speedRatio >= 1.0 - EPSILON
					and position.distance_squared_to(candidate.desiredPosition) <= EPSILON
				)

		if setBestRatio > EPSILON:
			bestPosition = setBestPosition
			bestAngle = setBestAngle
			bestRatio = setBestRatio
			bestFinish = setBestFinish
			break

	if bestRatio <= EPSILON:
		if mapClearCandidateFound:
			return MOTION_BLOCKED

		if mapBlockedCandidateFound:
			return MOTION_MAP_BLOCKED

		return MOTION_BLOCKED

	_ApplyPosition(candidate, bestPosition, dt, bestFinish)

	if plan != null and absf(bestAngle) > EPSILON:
		var chosenSide: int = 1 if bestAngle > 0.0 else -1

		if chosenSide != plan.side:
			plan.side = chosenSide
			_SetPairMemorySide(candidate.unitId, plan.otherId, plan.side)

		plan.selectedAngle = bestAngle

	return MOTION_RESOLVED


func _TryApplyStraightSlowdown(
	candidate: MoveOrder.MovementCandidate,
	workingSnapshots: Dictionary[int, Snapshot],
	neighbors: Array,
	dt: float,
) -> bool:
	var baseDirection: Vector2 = _CandidateBaseDirection(candidate)

	if baseDirection == Vector2.ZERO:
		return false

	var stepDistance: float = candidate.maxStepDistance

	if candidate.finalTick:
		stepDistance = candidate.desiredStepDistance

	if stepDistance <= EPSILON:
		return false

	for speedRatio: float in _AvoidSpeedRatios():
		if speedRatio >= 1.0 - EPSILON:
			continue

		var position: Vector2 = _QuantizeVec(
			candidate.startPosition + baseDirection * stepDistance * speedRatio
		)

		if not _PositionClearOfUnits(candidate, position, workingSnapshots, neighbors):
			continue

		_ApplyPosition(candidate, position, dt, false)
		return true

	return false


func _AnglesForPlan(plan: AvoidancePlan, nearArrival: bool) -> Array[float]:
	var result: Array[float] = []
	var used: Dictionary[int, bool] = { }
	var side: float = 1.0 if plan.side >= 0 else -1.0
	var selected: float = plan.selectedAngle

	if absf(selected) <= EPSILON or selected * side <= 0.0:
		selected = AVOID_PRIMARY_ANGLE * side

	_AppendAngle(result, used, selected, nearArrival)
	_AppendAngle(result, used, AVOID_SMALL_ANGLE * side, nearArrival)
	_AppendAngle(result, used, AVOID_MEDIUM_ANGLE * side, nearArrival)
	_AppendAngle(result, used, AVOID_PRIMARY_ANGLE * side, nearArrival)
	_AppendAngle(result, used, AVOID_LARGE_ANGLE * side, nearArrival)
	_AppendAngle(result, used, AVOID_WIDE_ANGLE * side, nearArrival)
	_AppendAngle(result, used, AVOID_SIDE_ANGLE * side, nearArrival)
	_AppendAngle(result, used, AVOID_REAR_SOFT_ANGLE * side, nearArrival)
	_AppendAngle(result, used, AVOID_REAR_MEDIUM_ANGLE * side, nearArrival)
	_AppendAngle(result, used, AVOID_REAR_WIDE_ANGLE * side, nearArrival)
	_AppendAngle(result, used, AVOID_REVERSE_ANGLE, nearArrival)

	return result


func _AnglesForSide(sideValue: int, nearArrival: bool) -> Array[float]:
	var result: Array[float] = []
	var used: Dictionary[int, bool] = { }
	var side: float = 1.0 if sideValue >= 0 else -1.0

	_AppendAngle(result, used, AVOID_PRIMARY_ANGLE * side, nearArrival)
	_AppendAngle(result, used, AVOID_LARGE_ANGLE * side, nearArrival)
	_AppendAngle(result, used, AVOID_MEDIUM_ANGLE * side, nearArrival)
	_AppendAngle(result, used, AVOID_WIDE_ANGLE * side, nearArrival)
	_AppendAngle(result, used, AVOID_SMALL_ANGLE * side, nearArrival)
	_AppendAngle(result, used, AVOID_SIDE_ANGLE * side, nearArrival)
	_AppendAngle(result, used, AVOID_REAR_SOFT_ANGLE * side, nearArrival)
	_AppendAngle(result, used, AVOID_REAR_MEDIUM_ANGLE * side, nearArrival)
	_AppendAngle(result, used, AVOID_REAR_WIDE_ANGLE * side, nearArrival)
	_AppendAngle(result, used, AVOID_REVERSE_ANGLE, nearArrival)

	return result


func _AnglesWithoutPlan(unitId: int, nearArrival: bool) -> Array[float]:
	var result: Array[float] = []
	var used: Dictionary[int, bool] = { }
	var side: float = 1.0 if unitId % 2 == 0 else -1.0

	_AppendAngle(result, used, 0.0, nearArrival)
	_AppendAngle(result, used, AVOID_MEDIUM_ANGLE * side, nearArrival)
	_AppendAngle(result, used, -AVOID_MEDIUM_ANGLE * side, nearArrival)
	_AppendAngle(result, used, AVOID_PRIMARY_ANGLE * side, nearArrival)
	_AppendAngle(result, used, -AVOID_PRIMARY_ANGLE * side, nearArrival)
	_AppendAngle(result, used, AVOID_LARGE_ANGLE * side, nearArrival)
	_AppendAngle(result, used, -AVOID_LARGE_ANGLE * side, nearArrival)
	_AppendAngle(result, used, AVOID_SIDE_ANGLE * side, nearArrival)
	_AppendAngle(result, used, -AVOID_SIDE_ANGLE * side, nearArrival)
	_AppendAngle(result, used, AVOID_REAR_SOFT_ANGLE * side, nearArrival)
	_AppendAngle(result, used, -AVOID_REAR_SOFT_ANGLE * side, nearArrival)
	_AppendAngle(result, used, AVOID_REAR_MEDIUM_ANGLE * side, nearArrival)
	_AppendAngle(result, used, -AVOID_REAR_MEDIUM_ANGLE * side, nearArrival)
	_AppendAngle(result, used, AVOID_REAR_WIDE_ANGLE * side, nearArrival)
	_AppendAngle(result, used, -AVOID_REAR_WIDE_ANGLE * side, nearArrival)
	_AppendAngle(result, used, AVOID_REVERSE_ANGLE, nearArrival)

	return result


func _AppendAngle(
	result: Array[float],
	used: Dictionary[int, bool],
	angle: float,
	nearArrival: bool,
) -> void:
	if nearArrival and absf(angle) > ARRIVAL_MAX_AVOID_ANGLE + EPSILON:
		return

	var key: int = roundi(angle * 1000000.0)

	if used.has(key):
		return

	used[key] = true
	result.append(angle)


func _AvoidSpeedRatios() -> Array[float]:
	var minimum: float = clampf(minAvoidSpeedRatio, 0.8, 1.0)

	if (
		not _cachedAvoidSpeedRatios.is_empty()
		and absf(minimum - _cachedMinAvoidSpeedRatio) <= EPSILON
	):
		return _cachedAvoidSpeedRatios

	_cachedMinAvoidSpeedRatio = minimum
	_cachedAvoidSpeedRatios.clear()

	var step: float = 0.1
	var ratio: float = 1.0

	while ratio > minimum + EPSILON:
		_cachedAvoidSpeedRatios.append(ratio)
		ratio -= step

	if (
		_cachedAvoidSpeedRatios.is_empty()
		or absf(_cachedAvoidSpeedRatios[_cachedAvoidSpeedRatios.size() - 1] - minimum) > EPSILON
	):
		_cachedAvoidSpeedRatios.append(minimum)

	return _cachedAvoidSpeedRatios


func _VelocityCandidateScore(
	candidate: MoveOrder.MovementCandidate,
	velocity: Vector2,
	preferredVelocity: Vector2,
	previousVelocity: Vector2,
	angle: float,
	speedRatio: float,
	plan: AvoidancePlan,
) -> float:
	var speedScale: float = maxf(
		(
			_units[candidate.unitId].movement.moveSpeed
			if _units.has(candidate.unitId)
			else preferredVelocity.length()
		),
		1.0,
	)
	var score: float = ((velocity - preferredVelocity).length() / speedScale)

	if previousVelocity.length_squared() > EPSILON:
		score += ((velocity - previousVelocity).length() / speedScale * avoidPreviousVelocityWeight)

	score += absf(angle) / PI * 0.08
	score += (1.0 - speedRatio) * 0.03

	if plan != null and absf(angle) > EPSILON:
		var side: int = 1 if angle > 0.0 else -1

		if side != plan.side:
			score += avoidSideChangePenalty

	return score


func _CandidateBaseDirection(candidate: MoveOrder.MovementCandidate) -> Vector2:
	if candidate.desiredVelocity.length_squared() > EPSILON:
		return candidate.desiredVelocity.normalized()

	var delta: Vector2 = (candidate.targetPosition - candidate.startPosition)

	if delta.length_squared() > EPSILON:
		return delta.normalized()

	return Vector2.ZERO


func _CandidateNearArrival(candidate: MoveOrder.MovementCandidate) -> bool:
	var fullSize: float = maxf(candidate.halfSize.x * 2.0, candidate.halfSize.y * 2.0)

	return candidate.arrivalDistance <= maxf(fullSize * 1.75, 16.0)


func _MakesArrivalProgress(candidate: MoveOrder.MovementCandidate, position: Vector2) -> bool:
	return (
		position.distance_to(candidate.arrivalSlot) < candidate.startPosition.distance_to(
			candidate.arrivalSlot
		) - EPSILON
	)


func _PositionClearOfUnits(
	candidate: MoveOrder.MovementCandidate,
	position: Vector2,
	snapshots: Dictionary[int, Snapshot],
	neighbors: Array,
) -> bool:
	for value: Variant in neighbors:
		var otherId: int = int(value)

		if not snapshots.has(otherId):
			continue

		var other: Snapshot = snapshots[otherId]

		if _RectanglesOverlapStrict(position, candidate.halfSize, other.position, other.halfSize):
			return false

	return true


func _MapSegmentClear(candidate: MoveOrder.MovementCandidate, position: Vector2) -> bool:
	return navigationService.SegmentClear(candidate.startPosition, position, candidate.halfSize)


func _ApplyPosition(
	candidate: MoveOrder.MovementCandidate,
	position: Vector2,
	dt: float,
	finishOrder: bool,
) -> void:
	candidate.position = _QuantizeVec(position)
	candidate.velocity = ((candidate.position - candidate.startPosition) / dt)
	candidate.finishOrder = finishOrder


func _UpdateSnapshot(
	snapshots: Dictionary[int, Snapshot],
	candidate: MoveOrder.MovementCandidate,
) -> void:
	if not snapshots.has(candidate.unitId):
		var snapshot: Snapshot = Snapshot.new()
		snapshot.unitId = candidate.unitId
		snapshot.halfSize = candidate.halfSize
		snapshots[candidate.unitId] = snapshot

	snapshots[candidate.unitId].position = candidate.position
	snapshots[candidate.unitId].halfSize = candidate.halfSize


func _RectanglesOverlapStrict(
	aPosition: Vector2,
	aHalf: Vector2,
	bPosition: Vector2,
	bHalf: Vector2,
) -> bool:
	return (
		absf(aPosition.x - bPosition.x) < aHalf.x + bHalf.x - COLLISION_EPSILON
		and absf(aPosition.y - bPosition.y) < aHalf.y + bHalf.y - COLLISION_EPSILON
	)


func _PairKey(aId: int, bId: int) -> Vector2i:
	return Vector2i(mini(aId, bId), maxi(aId, bId))


func _SetPairMemorySide(unitId: int, otherId: int, side: int) -> void:
	var key: Vector2i = _PairKey(unitId, otherId)

	if not _pairMemory.has(key):
		return

	var memory: PairMemory = _pairMemory[key]

	if unitId == memory.lowId:
		memory.lowSide = side
	elif unitId == memory.highId:
		memory.highSide = side

	memory.lastTick = simulationTick


func _CleanupPairMemory() -> void:
	var removeKeys: Array[Vector2i] = []

	for key: Vector2i in _pairMemory:
		if (simulationTick - _pairMemory[key].lastTick > PAIR_MEMORY_TICKS):
			removeKeys.append(key)

	for key: Vector2i in removeKeys:
		_pairMemory.erase(key)


func _BuildStartSpatialHash() -> Dictionary:
	var spatial: Dictionary = { }

	for unitId: int in _sortedUnitIds:
		var unit: Unit = _units[unitId]
		var cell: Vector2i = _SpatialCell(unit.position)

		if not spatial.has(cell):
			spatial[cell] = []

		var bucket: Array = spatial[cell]
		bucket.append(unitId)

	return spatial


func _QueryStartSpatial(
	spatial: Dictionary,
	position: Vector2,
	extent: Vector2,
	excludeId: int,
) -> Array:
	var result: Array = []
	var seen: Dictionary[int, bool] = { }
	var minCell: Vector2i = _SpatialCell(position - extent)
	var maxCell: Vector2i = _SpatialCell(position + extent)

	for y: int in range(minCell.y, maxCell.y + 1):
		for x: int in range(minCell.x, maxCell.x + 1):
			var key: Vector2i = Vector2i(x, y)

			if not spatial.has(key):
				continue

			var bucket: Array = spatial[key]

			for value: Variant in bucket:
				var unitId: int = int(value)

				if unitId == excludeId or seen.has(unitId):
					continue

				seen[unitId] = true
				result.append(unitId)

	result.sort()
	return result


func _SpatialCell(position: Vector2) -> Vector2i:
	return Vector2i(
		floori(position.x / candidateSpatialCellSize),
		floori(position.y / candidateSpatialCellSize),
	)


func _CommitCandidates(candidates: Array[MoveOrder.MovementCandidate]) -> void:
	candidates.sort_custom(
		func(a: MoveOrder.MovementCandidate, b: MoveOrder.MovementCandidate) -> bool:
			return a.unitId < b.unitId,
	)

	for candidate: MoveOrder.MovementCandidate in candidates:
		if not _units.has(candidate.unitId):
			continue

		var unit: Unit = _units[candidate.unitId]
		var movement: MovementComponent = unit.movement

		if movement.activeMoveOrder == null:
			continue

		if movement.activeMoveOrder.orderId != candidate.orderId:
			continue

		movement.CommitSimulation(candidate.position, candidate.velocity, candidate.finishOrder)

		if candidate.finishOrder:
			_avoidanceByUnit.erase(candidate.unitId)


func _QuantizeVec(value: Vector2) -> Vector2:
	if simulationQuantum <= 0.0:
		return value

	return Vector2(
		round(value.x / simulationQuantum) * simulationQuantum,
		round(value.y / simulationQuantum) * simulationQuantum,
	)
