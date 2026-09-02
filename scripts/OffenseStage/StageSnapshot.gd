class_name StageSnapshot
extends RefCounted

const SPATIAL_CELL_SIZE: float = 64.0
const DEFAULT_SLOT_CAPACITY: int = 512

var _slots: UnitSlotStorage
var _slotsByCell: Dictionary[Vector2i, Array] = {}


func _init(initialCapacity: int = DEFAULT_SLOT_CAPACITY) -> void:
	_slots = UnitSlotStorage.new(initialCapacity)


func GetUnitCount() -> int:
	return _slots.GetUnitCount()


func GetSlotCapacity() -> int:
	return _slots.GetSlotCapacity()


func HasUnit(unitId: int) -> bool:
	return _slots.HasUnit(unitId)


func GetPosition(unitId: int) -> Vector2:
	var slot: int = _getSlotOrError(unitId)

	if slot == UnitSlotStorage.INVALID_SLOT:
		return Vector2.ZERO

	return _slots.GetPositionBySlot(slot)


func GetHalfSize(unitId: int) -> int:
	var slot: int = _getSlotOrError(unitId)

	if slot == UnitSlotStorage.INVALID_SLOT:
		return 0

	return _slots.GetHalfSizeBySlot(slot)


func GetUnitIds() -> Array[int]:
	return _slots.GetUnitIds()


func RegisterUnit(unitId: int, position: Vector2, halfSize: int) -> void:
	var slot: int = _slots.Allocate(unitId, position, halfSize)

	if slot == UnitSlotStorage.INVALID_SLOT:
		return

	var extent: Vector2 = Vector2(float(halfSize), float(halfSize))
	var minCell: Vector2i = _getCell(position - extent)
	var maxCell: Vector2i = _getCell(position + extent)

	_slots.SetCellBoundsBySlot(slot, minCell, maxCell)
	_addSlotToCells(slot, minCell, maxCell)


func UnregisterUnit(unitId: int) -> void:
	var slot: int = _slots.FindSlot(unitId)

	if slot == UnitSlotStorage.INVALID_SLOT:
		return

	var minCell: Vector2i = _slots.GetMinCellBySlot(slot)
	var maxCell: Vector2i = _slots.GetMaxCellBySlot(slot)

	_removeSlotFromCells(slot, minCell, maxCell)
	_slots.ReleaseSlot(slot)


func UpdateUnit(unitId: int, position: Vector2, halfSize: int) -> void:
	var slot: int = _getSlotOrError(unitId)

	if slot == UnitSlotStorage.INVALID_SLOT:
		return

	_updateSlot(slot, position, halfSize)


func UpdatePosition(unitId: int, position: Vector2) -> void:
	var slot: int = _getSlotOrError(unitId)

	if slot == UnitSlotStorage.INVALID_SLOT:
		return

	_updateSlot(slot, position, _slots.GetHalfSizeBySlot(slot))


func UpdateHalfSize(unitId: int, halfSize: int) -> void:
	var slot: int = _getSlotOrError(unitId)

	if slot == UnitSlotStorage.INVALID_SLOT:
		return

	_updateSlot(slot, _slots.GetPositionBySlot(slot), halfSize)


func Clear() -> void:
	_slotsByCell.clear()
	_slots.Clear()


func FindUnitIdsInCircle(center: Vector2, radius: float) -> Array[int]:
	var result: Array[int] = []

	if radius < 0.0:
		push_error("검색 반경은 0 이상이어야 합니다.")
		return result

	var radiusVector: Vector2 = Vector2(radius, radius)
	var minCell: Vector2i = _getCell(center - radiusVector)
	var maxCell: Vector2i = _getCell(center + radiusVector)
	var radiusSquared: float = radius * radius
	var queryStamp: int = _slots.BeginQuery()

	for cellX: int in range(minCell.x, maxCell.x + 1):
		for cellY: int in range(minCell.y, maxCell.y + 1):
			var cell: Vector2i = Vector2i(cellX, cellY)

			if not _slotsByCell.has(cell):
				continue

			var cellSlots: Array = _slotsByCell[cell]

			for slot: int in cellSlots:
				if not _slots.TryMarkQuerySlot(slot, queryStamp):
					continue

				if _intersectsCircle(slot, center, radiusSquared):
					result.append(_slots.GetUnitIdBySlot(slot))

	return result


func FindUnitIdsInRect(center: Vector2, halfExtent: Vector2) -> Array[int]:
	var result: Array[int] = []
	var extent: Vector2 = Vector2(absf(halfExtent.x), absf(halfExtent.y))
	var minCell: Vector2i = _getCell(center - extent)
	var maxCell: Vector2i = _getCell(center + extent)
	var queryStamp: int = _slots.BeginQuery()

	for cellX: int in range(minCell.x, maxCell.x + 1):
		for cellY: int in range(minCell.y, maxCell.y + 1):
			var cell: Vector2i = Vector2i(cellX, cellY)

			if not _slotsByCell.has(cell):
				continue

			var cellSlots: Array = _slotsByCell[cell]

			for slot: int in cellSlots:
				if not _slots.TryMarkQuerySlot(slot, queryStamp):
					continue

				if _intersectsRect(slot, center, extent):
					result.append(_slots.GetUnitIdBySlot(slot))

	return result


func FindUnitIdsInRadius(center: Vector2, radius: float) -> Array[int]:
	return FindUnitIdsInCircle(center, radius)


func FindUnitIdsInBounds(center: Vector2, halfExtent: Vector2) -> Array[int]:
	return FindUnitIdsInRect(center, halfExtent)


func _getSlotOrError(unitId: int) -> int:
	var slot: int = _slots.FindSlot(unitId)

	if slot == UnitSlotStorage.INVALID_SLOT:
		push_error("StageSnapshot에 unitId %d가 없습니다." % unitId)

	return slot


func _updateSlot(slot: int, position: Vector2, halfSize: int) -> void:
	var oldMinCell: Vector2i = _slots.GetMinCellBySlot(slot)
	var oldMaxCell: Vector2i = _slots.GetMaxCellBySlot(slot)
	var extent: Vector2 = Vector2(float(halfSize), float(halfSize))
	var newMinCell: Vector2i = _getCell(position - extent)
	var newMaxCell: Vector2i = _getCell(position + extent)

	if not _slots.UpdateStateBySlot(slot, position, halfSize):
		return

	if oldMinCell == newMinCell and oldMaxCell == newMaxCell:
		return

	_removeSlotFromCells(slot, oldMinCell, oldMaxCell)
	_addSlotToCells(slot, newMinCell, newMaxCell)
	_slots.SetCellBoundsBySlot(slot, newMinCell, newMaxCell)


func _intersectsCircle(slot: int, center: Vector2, radiusSquared: float) -> bool:
	var unitPosition: Vector2 = _slots.GetPositionBySlot(slot)
	var halfSize: float = float(_slots.GetHalfSizeBySlot(slot))
	var minPosition: Vector2 = unitPosition - Vector2(halfSize, halfSize)
	var maxPosition: Vector2 = unitPosition + Vector2(halfSize, halfSize)
	var closestPoint: Vector2 = Vector2(
		clampf(center.x, minPosition.x, maxPosition.x),
		clampf(center.y, minPosition.y, maxPosition.y),
	)

	return center.distance_squared_to(closestPoint) <= radiusSquared


func _intersectsRect(slot: int, center: Vector2, halfExtent: Vector2) -> bool:
	var unitPosition: Vector2 = _slots.GetPositionBySlot(slot)
	var halfSize: float = float(_slots.GetHalfSizeBySlot(slot))

	return (
		absf(unitPosition.x - center.x) <= halfExtent.x + halfSize
		and absf(unitPosition.y - center.y) <= halfExtent.y + halfSize
	)


func _addSlotToCells(slot: int, minCell: Vector2i, maxCell: Vector2i) -> void:
	for cellX: int in range(minCell.x, maxCell.x + 1):
		for cellY: int in range(minCell.y, maxCell.y + 1):
			var cell: Vector2i = Vector2i(cellX, cellY)
			var cellSlots: Array = []

			if _slotsByCell.has(cell):
				cellSlots = _slotsByCell[cell]

			cellSlots.append(slot)
			_slotsByCell[cell] = cellSlots


func _removeSlotFromCells(slot: int, minCell: Vector2i, maxCell: Vector2i) -> void:
	for cellX: int in range(minCell.x, maxCell.x + 1):
		for cellY: int in range(minCell.y, maxCell.y + 1):
			var cell: Vector2i = Vector2i(cellX, cellY)

			if not _slotsByCell.has(cell):
				continue

			var cellSlots: Array = _slotsByCell[cell]
			var slotIndex: int = cellSlots.find(slot)

			if slotIndex < 0:
				continue

			var lastIndex: int = cellSlots.size() - 1

			if slotIndex != lastIndex:
				cellSlots[slotIndex] = cellSlots[lastIndex]

			cellSlots.pop_back()

			if cellSlots.is_empty():
				_slotsByCell.erase(cell)
			else:
				_slotsByCell[cell] = cellSlots


func _getCell(position: Vector2) -> Vector2i:
	return Vector2i(
		floori(position.x / SPATIAL_CELL_SIZE),
		floori(position.y / SPATIAL_CELL_SIZE),
	)
