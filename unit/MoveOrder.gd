class_name MoveOrder
extends RefCounted

const EPSILON: float = 0.00001
const FORMATION_GAP: float = 1.0
const MIN_GRID_STEP: float = 8.0
const FORMATION_CANDIDATE_MULTIPLIER: int = 64
const MIN_FORMATION_CANDIDATES: int = 512
const MAX_FORMATION_CANDIDATES: int = 8192
const MAX_SLOT_LOCAL_CHECKS: int = 32
const SLOT_DEPTH_WEIGHT: float = 2.0
const SLOT_LATERAL_WEIGHT: float = 0.7
const SLOT_RADIUS_WEIGHT: float = 0.15

var orderId: int = 0
var issuedTick: int = 0
var targetWorld: Vector2 = Vector2.ZERO
var memberIds: Array[int] = []

var _navigationService: NavigationService
var _arrivalCenter: Vector2 = Vector2.ZERO
var _groupStartCenter: Vector2 = Vector2.ZERO
var _approachDirection: Vector2 = Vector2.RIGHT
var _approachRight: Vector2 = Vector2.DOWN
var _slotByUnit: Dictionary[int, Vector2] = { }
var _priorityByUnit: Dictionary[int, int] = { }
var _claimedSlots: Array[ClaimedSlot] = []
var _gridStep: float = MIN_GRID_STEP
var _formationSpan: float = 32.0


class ClaimedSlot:
	var unitId: int = -1
	var position: Vector2 = Vector2.ZERO
	var halfSize: Vector2 = Vector2.ZERO


class UnitOrderInfo:
	var unitId: int = -1
	var front: float = 0.0
	var lateral: float = 0.0
	var distanceToTarget: float = 0.0


class MovementCandidate:
	var orderId: int = -1
	var unitId: int = -1
	var startPosition: Vector2 = Vector2.ZERO
	var desiredPosition: Vector2 = Vector2.ZERO
	var position: Vector2 = Vector2.ZERO
	var desiredVelocity: Vector2 = Vector2.ZERO
	var velocity: Vector2 = Vector2.ZERO
	var targetPosition: Vector2 = Vector2.ZERO
	var halfSize: Vector2 = Vector2.ZERO
	var maxStepDistance: float = 0.0
	var desiredStepDistance: float = 0.0
	var finalTick: bool = false
	var finishOrder: bool = false
	var arrivalActive: bool = false
	var arrivalSlot: Vector2 = Vector2.ZERO
	var arrivalDistance: float = 0.0
	var priority: int = 2147483647


func _init(
	pOrderId: int,
	pIssuedTick: int,
	pTargetWorld: Vector2,
	pMemberIds: Array[int],
	pNavigationService: NavigationService,
) -> void:
	orderId = pOrderId
	issuedTick = pIssuedTick
	targetWorld = pTargetWorld
	memberIds = pMemberIds.duplicate()
	memberIds.sort()
	_navigationService = pNavigationService


func Start(units: Dictionary[int, Unit]) -> void:
	if _navigationService == null:
		push_error("MoveOrder에 NavigationService가 없습니다.")
		return

	_groupStartCenter = _AverageMemberPosition(units)
	var largestHalf: Vector2 = _LargestMemberHalfSize(units)
	var anchorPath: PackedVector2Array = _navigationService.FindPath(
		_groupStartCenter,
		targetWorld,
		largestHalf,
	)

	if not anchorPath.is_empty():
		_arrivalCenter = anchorPath[anchorPath.size() - 1]
	else:
		_arrivalCenter = _navigationService.NearestPlaceablePoint(
			targetWorld,
			largestHalf,
			_groupStartCenter,
		)

	var approachDelta: Vector2 = _arrivalCenter - _groupStartCenter

	if anchorPath.size() >= 2:
		approachDelta = anchorPath[anchorPath.size() - 1] - anchorPath[anchorPath.size() - 2]

	if approachDelta.length_squared() > EPSILON:
		_approachDirection = approachDelta.normalized()
	else:
		_approachDirection = Vector2.RIGHT

	_approachRight = Vector2(-_approachDirection.y, _approachDirection.x)

	_PrepareFormationMetrics(units)
	_AssignSlots(units)

	for unitId: int in memberIds:
		if not units.has(unitId):
			continue

		var unit: Unit = units[unitId]
		var slot: Vector2 = _slotByUnit.get(unitId, _arrivalCenter)
		var path: PackedVector2Array = _navigationService.FindPath(
			unit.position,
			slot,
			unit.GetHalfSize(),
		)

		if path.is_empty():
			var fallback: Vector2 = _navigationService.NearestPlaceablePoint(
				slot,
				unit.GetHalfSize(),
				unit.position,
			)

			path = _navigationService.FindPath(unit.position, fallback, unit.GetHalfSize())

			if not path.is_empty():
				_slotByUnit[unitId] = path[path.size() - 1]

		if path.is_empty():
			path.append(unit.position)

		unit.movement.BeginMoveOrder(self, path)


func Simulate(dt: float, allUnits: Dictionary[int, Unit]) -> Array[MovementCandidate]:
	var result: Array[MovementCandidate] = []

	for unitId: int in memberIds:
		if not allUnits.has(unitId):
			continue

		var unit: Unit = allUnits[unitId]
		var movement: MovementComponent = unit.movement

		if not _OwnsMovement(movement):
			continue

		if movement.IsPaused():
			movement.ResetSimVelocity()
			continue

		movement.SyncPathProgress(movement.moveSpeed * dt, _navigationService)

		result.append(_MakeCandidate(unit, movement, dt))

	return result


func IsFinished(allUnits: Dictionary[int, Unit]) -> bool:
	for unitId: int in memberIds:
		if not allUnits.has(unitId):
			continue

		if _OwnsMovement(allUnits[unitId].movement):
			return false

	return true


func GetUnitPriority(unitId: int) -> int:
	return _priorityByUnit.get(unitId, 2147483647)


func _MakeCandidate(unit: Unit, movement: MovementComponent, dt: float) -> MovementCandidate:
	var candidate: MovementCandidate = MovementCandidate.new()
	var slot: Vector2 = _slotByUnit.get(unit.unitId, movement.GetEffectiveGoal())
	var desiredVelocity: Vector2 = movement.GetDesiredVelocity(dt)
	var desiredPosition: Vector2 = unit.position + desiredVelocity * dt
	var finalTick: bool = movement.WantsFinalTick(dt)

	if finalTick:
		desiredPosition = movement.GetEffectiveGoal()

		if dt > EPSILON:
			desiredVelocity = (desiredPosition - unit.position) / dt

	candidate.orderId = orderId
	candidate.unitId = unit.unitId
	candidate.startPosition = unit.position
	candidate.desiredPosition = desiredPosition
	candidate.position = desiredPosition
	candidate.desiredVelocity = desiredVelocity
	candidate.velocity = desiredVelocity
	candidate.targetPosition = movement.GetCurrentWaypoint()
	candidate.halfSize = unit.GetHalfSize()
	candidate.maxStepDistance = movement.moveSpeed * dt
	candidate.desiredStepDistance = unit.position.distance_to(desiredPosition)
	candidate.finalTick = finalTick
	candidate.finishOrder = finalTick
	candidate.arrivalActive = true
	candidate.arrivalSlot = slot
	candidate.arrivalDistance = unit.position.distance_to(slot)
	candidate.priority = GetUnitPriority(unit.unitId)

	return candidate


func _OwnsMovement(movement: MovementComponent) -> bool:
	if movement == null:
		return false

	if movement.activeMoveOrder == null:
		return false

	return movement.activeMoveOrder.orderId == orderId


func _PrepareFormationMetrics(units: Dictionary[int, Unit]) -> void:
	var minFull: float = 1000000.0
	var maxFull: float = 1.0
	var validCount: int = 0

	for unitId: int in memberIds:
		if not units.has(unitId):
			continue

		var unit: Unit = units[unitId]
		var fullSize: float = maxf(unit.footprintSize.x, unit.footprintSize.y)
		var minDimension: float = minf(unit.footprintSize.x, unit.footprintSize.y)

		minFull = minf(minFull, minDimension)
		maxFull = maxf(maxFull, fullSize)
		validCount += 1

	if validCount == 0:
		_gridStep = MIN_GRID_STEP
		_formationSpan = 32.0
		return

	_gridStep = maxf(MIN_GRID_STEP, minFull * 0.5 + FORMATION_GAP)
	_formationSpan = maxf(maxFull * 2.0, sqrt(float(validCount)) * maxFull * 1.1)


func _AssignSlots(units: Dictionary[int, Unit]) -> void:
	_slotByUnit.clear()
	_priorityByUnit.clear()
	_claimedSlots.clear()

	var infos: Array[UnitOrderInfo] = []

	for unitId: int in memberIds:
		if not units.has(unitId):
			continue

		var unit: Unit = units[unitId]
		var info: UnitOrderInfo = UnitOrderInfo.new()
		var relative: Vector2 = unit.position - _groupStartCenter

		info.unitId = unitId
		info.front = relative.dot(_approachDirection)
		info.lateral = relative.dot(_approachRight)
		info.distanceToTarget = unit.position.distance_to(_arrivalCenter)

		infos.append(info)

	infos.sort_custom(
		func(a: UnitOrderInfo, b: UnitOrderInfo) -> bool:
			if absf(a.front - b.front) > EPSILON:
				return a.front > b.front

			if absf(a.distanceToTarget - b.distanceToTarget) > EPSILON:
				return a.distanceToTarget < b.distanceToTarget

			return a.unitId < b.unitId,
	)

	var candidateCount: int = clampi(
		maxi(MIN_FORMATION_CANDIDATES, infos.size() * FORMATION_CANDIDATE_MULTIPLIER),
		MIN_FORMATION_CANDIDATES,
		MAX_FORMATION_CANDIDATES,
	)

	var offsets: Array[Vector2i] = _SquareSpiralOffsets(candidateCount)
	var total: int = infos.size()

	for rank: int in range(total):
		var info: UnitOrderInfo = infos[rank]
		var unit: Unit = units[info.unitId]
		var t: float = 0.5

		if total > 1:
			t = float(rank) / float(total - 1)

		var desiredDepth: float = lerpf(_formationSpan * 0.55, -_formationSpan * 0.55, t)
		var desiredLateral: float = clampf(
			info.lateral,
			-_formationSpan * 0.6,
			_formationSpan * 0.6,
		)

		var slot: Vector2 = _FindSlotForUnit(unit, desiredDepth, desiredLateral, offsets)

		_slotByUnit[info.unitId] = slot
		_priorityByUnit[info.unitId] = rank

		var claimed: ClaimedSlot = ClaimedSlot.new()

		claimed.unitId = info.unitId
		claimed.position = slot
		claimed.halfSize = unit.GetHalfSize()

		_claimedSlots.append(claimed)


func _InsertSlotCandidate(
	bestIndices: Array[int],
	bestScores: Array[float],
	spiralIndex: int,
	score: float,
) -> void:
	var insertAt: int = bestScores.size()

	for index: int in range(bestScores.size()):
		var currentScore: float = bestScores[index]
		var comesBefore: bool = false

		if absf(score - currentScore) > EPSILON:
			comesBefore = score < currentScore
		else:
			comesBefore = spiralIndex < bestIndices[index]

		if comesBefore:
			insertAt = index
			break

	if insertAt >= MAX_SLOT_LOCAL_CHECKS:
		return

	bestIndices.insert(insertAt, spiralIndex)
	bestScores.insert(insertAt, score)

	if bestIndices.size() > MAX_SLOT_LOCAL_CHECKS:
		bestIndices.pop_back()
		bestScores.pop_back()


func _FindSlotForUnit(
	unit: Unit,
	desiredDepth: float,
	desiredLateral: float,
	offsets: Array[Vector2i],
) -> Vector2:
	var bestIndices: Array[int] = []
	var bestScores: Array[float] = []
	var halfSize: Vector2 = unit.GetHalfSize()

	for index: int in range(offsets.size()):
		var offset: Vector2i = offsets[index]
		var local: Vector2 = Vector2(float(offset.x) * _gridStep, float(offset.y) * _gridStep)
		var position: Vector2 = _arrivalCenter + local

		if not _navigationService.CanPlaceStatic(position, halfSize):
			continue

		if _OverlapsClaimed(position, halfSize):
			continue

		var relative: Vector2 = position - _arrivalCenter
		var depth: float = relative.dot(_approachDirection)
		var lateral: float = relative.dot(_approachRight)
		var score: float = (
			absf(depth - desiredDepth) * SLOT_DEPTH_WEIGHT
			+ absf(lateral - desiredLateral) * SLOT_LATERAL_WEIGHT
			+ relative.length() * SLOT_RADIUS_WEIGHT + float(index) * 0.0001
		)

		_InsertSlotCandidate(bestIndices, bestScores, index, score)

	for spiralIndex: int in bestIndices:
		var offset: Vector2i = offsets[spiralIndex]
		var position: Vector2 = _arrivalCenter + Vector2(
			float(offset.x) * _gridStep,
			float(offset.y) * _gridStep,
		)

		if _navigationService.SegmentClear(_arrivalCenter, position, halfSize):
			return position

	var fallback: Vector2 = _navigationService.NearestPlaceablePoint(
		_arrivalCenter,
		halfSize,
		unit.position,
	)

	if not _OverlapsClaimed(fallback, halfSize):
		var fallbackPath: PackedVector2Array = _navigationService.FindPath(
			unit.position,
			fallback,
			halfSize,
		)

		if not fallbackPath.is_empty():
			return fallbackPath[fallbackPath.size() - 1]

	if not bestIndices.is_empty():
		var bestOffset: Vector2i = offsets[bestIndices[0]]

		return _arrivalCenter + Vector2(
			float(bestOffset.x) * _gridStep,
			float(bestOffset.y) * _gridStep,
		)

	return unit.position


func _OverlapsClaimed(position: Vector2, halfSize: Vector2) -> bool:
	for claimed: ClaimedSlot in _claimedSlots:
		if (
			absf(position.x - claimed.position.x) < halfSize.x + claimed.halfSize.x + FORMATION_GAP
			and absf(position.y - claimed.position.y)
			< halfSize.y + claimed.halfSize.y + FORMATION_GAP
		):
			return true

	return false


func _SquareSpiralOffsets(count: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []

	if count <= 0:
		return result

	var position: Vector2i = Vector2i.ZERO

	result.append(position)

	if count == 1:
		return result

	var directions: Array[Vector2i] = [
		Vector2i(0, -1),
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(-1, 0),
	]
	var directionIndex: int = 0
	var stepLength: int = 1

	while result.size() < count:
		for pairStep: int in range(2):
			var direction: Vector2i = directions[directionIndex]

			for step: int in range(stepLength):
				position += direction
				result.append(position)

				if result.size() >= count:
					return result

			directionIndex = (directionIndex + 1) % directions.size()

		stepLength += 1

	return result


func _AverageMemberPosition(units: Dictionary[int, Unit]) -> Vector2:
	var sum: Vector2 = Vector2.ZERO
	var count: int = 0

	for unitId: int in memberIds:
		if not units.has(unitId):
			continue

		sum += units[unitId].position
		count += 1

	if count == 0:
		return targetWorld

	return sum / float(count)


func _LargestMemberHalfSize(units: Dictionary[int, Unit]) -> Vector2:
	var result: Vector2 = Vector2(8.0, 8.0)

	for unitId: int in memberIds:
		if not units.has(unitId):
			continue

		var halfSize: Vector2 = units[unitId].GetHalfSize()

		result.x = maxf(result.x, halfSize.x)
		result.y = maxf(result.y, halfSize.y)

	return result
