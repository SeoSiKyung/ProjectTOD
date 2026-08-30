class_name UnitSlotStorage
extends RefCounted

const DEFAULT_SLOT_CAPACITY: int = 512
const SLOT_GROW_SIZE: int = 256
const INVALID_SLOT: int = -1
const INVALID_UNIT_ID: int = -1
const MAX_INT32_VALUE: int = 2147483647

var _slotByUnitId: Dictionary[int, int] = {}

var _unitIds: PackedInt32Array = []
var _positions: PackedVector2Array = []
var _halfSizes: PackedInt32Array = []
var _minCellXs: PackedInt32Array = []
var _minCellYs: PackedInt32Array = []
var _maxCellXs: PackedInt32Array = []
var _maxCellYs: PackedInt32Array = []
var _activeFlags: PackedByteArray = []
var _queryStamps: PackedInt32Array = []
var _activeListIndices: PackedInt32Array = []

var _activeSlots: Array[int] = []
var _freeSlots: Array[int] = []
var _queryStamp: int = 0


func _init(initialCapacity: int = DEFAULT_SLOT_CAPACITY) -> void:
	if initialCapacity < 0:
		push_error("초기 슬롯 크기는 0 이상이어야 합니다.")
		initialCapacity = 0

	if initialCapacity > 0:
		_growSlots(initialCapacity)


func GetUnitCount() -> int:
	return _activeSlots.size()


func GetSlotCapacity() -> int:
	return _positions.size()


func HasUnit(unitId: int) -> bool:
	return _slotByUnitId.has(unitId)


func FindSlot(unitId: int) -> int:
	if not _slotByUnitId.has(unitId):
		return INVALID_SLOT

	return _slotByUnitId[unitId]


func Allocate(unitId: int, position: Vector2, halfSize: int) -> int:
	if not _isValidInt32(unitId):
		push_error("unitId가 PackedInt32Array 범위를 벗어났습니다.")
		return INVALID_SLOT

	if _slotByUnitId.has(unitId):
		push_error("UnitSlotStorage에 unitId %d가 이미 등록되어 있습니다." % unitId)
		return INVALID_SLOT

	if not _isValidInt32(halfSize):
		push_error("halfSize가 PackedInt32Array 범위를 벗어났습니다.")
		return INVALID_SLOT

	var slot: int = _acquireSlot()

	_slotByUnitId[unitId] = slot
	_unitIds[slot] = unitId
	_positions[slot] = position
	_halfSizes[slot] = halfSize
	_minCellXs[slot] = 0
	_minCellYs[slot] = 0
	_maxCellXs[slot] = 0
	_maxCellYs[slot] = 0
	_activeFlags[slot] = 1
	_queryStamps[slot] = 0
	_addActiveSlot(slot)

	return slot


func ReleaseSlot(slot: int) -> bool:
	if not _isActiveSlot(slot):
		return false

	var unitId: int = _unitIds[slot]

	_removeActiveSlot(slot)
	_slotByUnitId.erase(unitId)
	_unitIds[slot] = INVALID_UNIT_ID
	_positions[slot] = Vector2.ZERO
	_halfSizes[slot] = 0
	_minCellXs[slot] = 0
	_minCellYs[slot] = 0
	_maxCellXs[slot] = 0
	_maxCellYs[slot] = 0
	_activeFlags[slot] = 0
	_queryStamps[slot] = 0
	_freeSlots.append(slot)

	return true


func UpdateState(slot: int, position: Vector2) -> bool:
	if not _isActiveSlot(slot):
		push_error("활성 상태가 아닌 슬롯은 갱신할 수 없습니다.")
		return false

	_positions[slot] = position
	return true


func GetUnitId(slot: int) -> int:
	return _unitIds[slot]


func GetPosition(slot: int) -> Vector2:
	return _positions[slot]


func GetHalfSize(slot: int) -> int:
	return _halfSizes[slot]


func GetMinCell(slot: int) -> Vector2i:
	return Vector2i(_minCellXs[slot], _minCellYs[slot])


func GetMaxCell(slot: int) -> Vector2i:
	return Vector2i(_maxCellXs[slot], _maxCellYs[slot])


func SetCellBounds(slot: int, minCell: Vector2i, maxCell: Vector2i) -> void:
	_minCellXs[slot] = minCell.x
	_minCellYs[slot] = minCell.y
	_maxCellXs[slot] = maxCell.x
	_maxCellYs[slot] = maxCell.y


func GetUnitIds() -> Array[int]:
	var result: Array[int] = []
	result.resize(_activeSlots.size())

	for index: int in range(_activeSlots.size()):
		var slot: int = _activeSlots[index]
		result[index] = _unitIds[slot]

	return result


func BeginQuery() -> int:
	if _queryStamp >= MAX_INT32_VALUE:
		_queryStamps.fill(0)
		_queryStamp = 1
	else:
		_queryStamp += 1

	return _queryStamp


func TryMarkQuerySlot(slot: int, queryStamp: int) -> bool:
	if not _isActiveSlot(slot):
		return false

	if _queryStamps[slot] == queryStamp:
		return false

	_queryStamps[slot] = queryStamp
	return true


func Clear() -> void:
	var capacity: int = GetSlotCapacity()

	_slotByUnitId.clear()
	_activeSlots.clear()
	_freeSlots.clear()
	_queryStamp = 0

	_unitIds.fill(INVALID_UNIT_ID)
	_positions.fill(Vector2.ZERO)
	_halfSizes.fill(0)
	_minCellXs.fill(0)
	_minCellYs.fill(0)
	_maxCellXs.fill(0)
	_maxCellYs.fill(0)
	_activeFlags.fill(0)
	_queryStamps.fill(0)
	_activeListIndices.fill(INVALID_SLOT)

	for slot: int in range(capacity - 1, -1, -1):
		_freeSlots.append(slot)


func _acquireSlot() -> int:
	if _freeSlots.is_empty():
		_growSlots(SLOT_GROW_SIZE)

	return _freeSlots.pop_back()


func _addActiveSlot(slot: int) -> void:
	_activeListIndices[slot] = _activeSlots.size()
	_activeSlots.append(slot)


func _removeActiveSlot(slot: int) -> void:
	var activeIndex: int = _activeListIndices[slot]
	var lastIndex: int = _activeSlots.size() - 1
	var lastSlot: int = _activeSlots[lastIndex]

	if activeIndex != lastIndex:
		_activeSlots[activeIndex] = lastSlot
		_activeListIndices[lastSlot] = activeIndex

	_activeSlots.pop_back()
	_activeListIndices[slot] = INVALID_SLOT


func _growSlots(growSize: int) -> void:
	if growSize <= 0:
		return

	var oldCapacity: int = GetSlotCapacity()
	var newCapacity: int = oldCapacity + growSize

	_unitIds.resize(newCapacity)
	_positions.resize(newCapacity)
	_halfSizes.resize(newCapacity)
	_minCellXs.resize(newCapacity)
	_minCellYs.resize(newCapacity)
	_maxCellXs.resize(newCapacity)
	_maxCellYs.resize(newCapacity)
	_activeFlags.resize(newCapacity)
	_queryStamps.resize(newCapacity)
	_activeListIndices.resize(newCapacity)

	for slot: int in range(oldCapacity, newCapacity):
		_unitIds[slot] = INVALID_UNIT_ID
		_activeFlags[slot] = 0
		_queryStamps[slot] = 0
		_activeListIndices[slot] = INVALID_SLOT

	for slot: int in range(newCapacity - 1, oldCapacity - 1, -1):
		_freeSlots.append(slot)


func _isActiveSlot(slot: int) -> bool:
	return (
		slot >= 0
		and slot < GetSlotCapacity()
		and _activeFlags[slot] != 0
	)


func _isValidInt32(value: int) -> bool:
	return value >= 0 and value <= MAX_INT32_VALUE
