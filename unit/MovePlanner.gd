class_name MovePlanner
extends RefCounted

const SLOT_GAP: float = 2.0
const MAX_EXACT_ASSIGNMENT_UNIT_COUNT: int = 8
const DIRECTION_EPSILON_SQUARED: float = 0.000001

var _searchUnitPositions: PackedVector2Array = []
var _searchSlotPositions: PackedVector2Array = []
var _currentAssignment: PackedInt32Array = []
var _bestAssignment: PackedInt32Array = []
var _bestAssignmentCost: float = 0.0
var _bestAssignmentFound: bool = false


func Plan(unitIds: PackedInt32Array, targetWorld: Vector2, snapshot: StageSnapshot) -> PackedVector2Array:
	var emptyResult: PackedVector2Array = []

	if not is_instance_valid(snapshot):
		push_error("MovePlanner에 StageSnapshot이 없습니다.")
		return emptyResult

	if not targetWorld.is_finite():
		push_error("이동 목적지가 유효하지 않습니다.")
		return emptyResult

	if unitIds.is_empty():
		return emptyResult

	var unitCount: int = unitIds.size()
	var unitPositions: PackedVector2Array = []
	var groupCenter: Vector2 = Vector2.ZERO
	var maximumHalfSize: int = 0

	unitPositions.resize(unitCount)

	for unitIndex: int in range(unitCount):
		var unitId: int = unitIds[unitIndex]

		if not snapshot.HasUnit(unitId):
			push_error("StageSnapshot에 unitId %d가 없습니다." % unitId)
			return emptyResult

		var unitPosition: Vector2 = snapshot.GetPosition(unitId)

		if not unitPosition.is_finite():
			push_error("unitId %d의 위치가 유효하지 않습니다." % unitId)
			return emptyResult

		unitPositions[unitIndex] = unitPosition
		groupCenter += unitPosition
		maximumHalfSize = maxi(maximumHalfSize, snapshot.GetHalfSize(unitId))

	groupCenter /= float(unitCount)

	var slotSpacing: float = float(maximumHalfSize * 2) + SLOT_GAP
	var slotPositions: PackedVector2Array = _createSlotPositions(unitCount, targetWorld, groupCenter, slotSpacing)

	if unitCount <= MAX_EXACT_ASSIGNMENT_UNIT_COUNT:
		return _assignSlotsExactly(unitPositions, slotPositions)

	return _assignSlotsGreedily(unitPositions, slotPositions)


func _createSlotPositions(unitCount: int, targetWorld: Vector2, groupCenter: Vector2, slotSpacing: float) -> PackedVector2Array:
	var slotPositions: PackedVector2Array = []
	var localOffsets: PackedVector2Array = []
	var columnCount: int = ceili(sqrt(float(unitCount)))
	var rowCount: int = ceili(float(unitCount) / float(columnCount))
	var offsetSum: Vector2 = Vector2.ZERO

	for row: int in range(rowCount):
		var unitsInRow: int = mini(columnCount, unitCount - row * columnCount)

		for column: int in range(unitsInRow):
			var offsetX: float = (float(column) - float(unitsInRow - 1) * 0.5) * slotSpacing
			var offsetY: float = (float(row) - float(rowCount - 1) * 0.5) * slotSpacing
			var localOffset: Vector2 = Vector2(offsetX, offsetY)

			localOffsets.append(localOffset)
			offsetSum += localOffset

	var offsetCenter: Vector2 = offsetSum / float(unitCount)
	var movementDelta: Vector2 = targetWorld - groupCenter
	var forward: Vector2 = Vector2.UP

	if movementDelta.length_squared() > DIRECTION_EPSILON_SQUARED:
		forward = movementDelta.normalized()

	var right: Vector2 = Vector2(-forward.y, forward.x)

	for localOffset: Vector2 in localOffsets:
		var centeredOffset: Vector2 = localOffset - offsetCenter
		var worldOffset: Vector2 = right * centeredOffset.x + forward * centeredOffset.y

		slotPositions.append(targetWorld + worldOffset)

	return slotPositions


func _assignSlotsExactly(unitPositions: PackedVector2Array, slotPositions: PackedVector2Array) -> PackedVector2Array:
	var unitCount: int = unitPositions.size()

	_searchUnitPositions = unitPositions
	_searchSlotPositions = slotPositions
	_currentAssignment.resize(unitCount)
	_currentAssignment.fill(-1)
	_bestAssignment.clear()
	_bestAssignmentCost = 0.0
	_bestAssignmentFound = false

	_searchAssignment(0, 0, 0.0)

	var destinations: PackedVector2Array = []

	if not _bestAssignmentFound:
		_clearSearchState()
		return destinations

	destinations.resize(unitCount)

	for unitIndex: int in range(unitCount):
		destinations[unitIndex] = slotPositions[_bestAssignment[unitIndex]]

	_clearSearchState()
	return destinations


func _searchAssignment(unitIndex: int, usedSlotMask: int, currentCost: float) -> void:
	if _bestAssignmentFound and currentCost >= _bestAssignmentCost:
		return

	if unitIndex == _searchUnitPositions.size():
		_bestAssignment = _currentAssignment.duplicate()
		_bestAssignmentCost = currentCost
		_bestAssignmentFound = true
		return

	for slotIndex: int in range(_searchSlotPositions.size()):
		var slotBit: int = 1 << slotIndex

		if (usedSlotMask & slotBit) != 0:
			continue

		_currentAssignment[unitIndex] = slotIndex

		var assignmentCost: float = _searchUnitPositions[unitIndex].distance_to(_searchSlotPositions[slotIndex])
		_searchAssignment(unitIndex + 1, usedSlotMask | slotBit, currentCost + assignmentCost)

	_currentAssignment[unitIndex] = -1


func _assignSlotsGreedily(unitPositions: PackedVector2Array, slotPositions: PackedVector2Array) -> PackedVector2Array:
	var unitCount: int = unitPositions.size()
	var destinations: PackedVector2Array = []
	var usedSlots: PackedByteArray = []

	destinations.resize(unitCount)
	usedSlots.resize(unitCount)
	usedSlots.fill(0)

	for unitIndex: int in range(unitCount):
		var bestSlotIndex: int = -1
		var bestDistanceSquared: float = INF

		for slotIndex: int in range(unitCount):
			if usedSlots[slotIndex] != 0:
				continue

			var distanceSquared: float = unitPositions[unitIndex].distance_squared_to(slotPositions[slotIndex])

			if distanceSquared >= bestDistanceSquared:
				continue

			bestDistanceSquared = distanceSquared
			bestSlotIndex = slotIndex

		if bestSlotIndex < 0:
			push_error("MovePlanner가 배정할 슬롯을 찾지 못했습니다.")
			return PackedVector2Array()

		usedSlots[bestSlotIndex] = 1
		destinations[unitIndex] = slotPositions[bestSlotIndex]

	return destinations


func _clearSearchState() -> void:
	_searchUnitPositions.clear()
	_searchSlotPositions.clear()
	_currentAssignment.clear()
	_bestAssignment.clear()
	_bestAssignmentCost = 0.0
	_bestAssignmentFound = false
