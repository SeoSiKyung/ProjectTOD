class_name UnitSlotStorage
extends RefCounted

const DEFAULT_SLOT_CAPACITY: int = 512
const SLOT_GROW_SIZE: int = 256
const INVALID_SLOT: int = -1
const INVALID_UNIT_ID: int = -1
const MAX_INT32_VALUE: int = 2147483647

var _slotByUnitId: Dictionary[int, int] = {}

var _unitIdsBySlot: PackedInt32Array = []
var _positionsBySlot: PackedVector2Array = []
var _halfSizesBySlot: PackedInt32Array = []
var _minCellXsBySlot: PackedInt32Array = []
var _minCellYsBySlot: PackedInt32Array = []
var _maxCellXsBySlot: PackedInt32Array = []
var _maxCellYsBySlot: PackedInt32Array = []
var _activeFlagsBySlot: PackedByteArray = []
var _queryStampsBySlot: PackedInt32Array = []
var _activeListIndicesBySlot: PackedInt32Array = []

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
	return _positionsBySlot.size()


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
	_unitIdsBySlot[slot] = unitId
	_positionsBySlot[slot] = position
	_halfSizesBySlot[slot] = halfSize
	_minCellXsBySlot[slot] = 0
	_minCellYsBySlot[slot] = 0
	_maxCellXsBySlot[slot] = 0
	_maxCellYsBySlot[slot] = 0
	_activeFlagsBySlot[slot] = 1
	_queryStampsBySlot[slot] = 0
	_addActiveSlot(slot)

	return slot


func ReleaseSlot(slot: int) -> bool:
	if not _isActiveSlot(slot):
		return false

	var unitId: int = _unitIdsBySlot[slot]

	_removeActiveSlot(slot)
	_slotByUnitId.erase(unitId)
	_unitIdsBySlot[slot] = INVALID_UNIT_ID
	_positionsBySlot[slot] = Vector2.ZERO
	_halfSizesBySlot[slot] = 0
	_minCellXsBySlot[slot] = 0
	_minCellYsBySlot[slot] = 0
	_maxCellXsBySlot[slot] = 0
	_maxCellYsBySlot[slot] = 0
	_activeFlagsBySlot[slot] = 0
	_queryStampsBySlot[slot] = 0
	_freeSlots.append(slot)

	return true


func UpdateStateBySlot(slot: int, position: Vector2, halfSize: int) -> bool:
	if not _isActiveSlot(slot):
		push_error("활성 상태가 아닌 슬롯은 갱신할 수 없습니다.")
		return false

	if not _isValidInt32(halfSize):
		push_error("halfSize가 PackedInt32Array 범위를 벗어났습니다.")
		return false

	_positionsBySlot[slot] = position
	_halfSizesBySlot[slot] = halfSize

	return true


func GetUnitIdBySlot(slot: int) -> int:
	return _unitIdsBySlot[slot]


func GetPositionBySlot(slot: int) -> Vector2:
	return _positionsBySlot[slot]


func GetHalfSizeBySlot(slot: int) -> int:
	return _halfSizesBySlot[slot]


func GetMinCellBySlot(slot: int) -> Vector2i:
	return Vector2i(_minCellXsBySlot[slot], _minCellYsBySlot[slot])


func GetMaxCellBySlot(slot: int) -> Vector2i:
	return Vector2i(_maxCellXsBySlot[slot], _maxCellYsBySlot[slot])


func SetCellBoundsBySlot(slot: int, minCell: Vector2i, maxCell: Vector2i) -> void:
	_minCellXsBySlot[slot] = minCell.x
	_minCellYsBySlot[slot] = minCell.y
	_maxCellXsBySlot[slot] = maxCell.x
	_maxCellYsBySlot[slot] = maxCell.y


func GetUnitIds() -> Array[int]:
	var result: Array[int] = []
	result.resize(_activeSlots.size())

	for index: int in range(_activeSlots.size()):
		var slot: int = _activeSlots[index]
		result[index] = _unitIdsBySlot[slot]

	return result


func BeginQuery() -> int:
	if _queryStamp >= MAX_INT32_VALUE:
		_queryStampsBySlot.fill(0)
		_queryStamp = 1
	else:
		_queryStamp += 1

	return _queryStamp


func TryMarkQuerySlot(slot: int, queryStamp: int) -> bool:
	if not _isActiveSlot(slot):
		return false

	if _queryStampsBySlot[slot] == queryStamp:
		return false

	_queryStampsBySlot[slot] = queryStamp
	return true


func Clear() -> void:
	var capacity: int = GetSlotCapacity()

	_slotByUnitId.clear()
	_activeSlots.clear()
	_freeSlots.clear()
	_queryStamp = 0

	_unitIdsBySlot.fill(INVALID_UNIT_ID)
	_positionsBySlot.fill(Vector2.ZERO)
	_halfSizesBySlot.fill(0)
	_minCellXsBySlot.fill(0)
	_minCellYsBySlot.fill(0)
	_maxCellXsBySlot.fill(0)
	_maxCellYsBySlot.fill(0)
	_activeFlagsBySlot.fill(0)
	_queryStampsBySlot.fill(0)
	_activeListIndicesBySlot.fill(INVALID_SLOT)

	for slot: int in range(capacity - 1, -1, -1):
		_freeSlots.append(slot)


func _acquireSlot() -> int:
	if _freeSlots.is_empty():
		_growSlots(SLOT_GROW_SIZE)

	return _freeSlots.pop_back()


func _addActiveSlot(slot: int) -> void:
	_activeListIndicesBySlot[slot] = _activeSlots.size()
	_activeSlots.append(slot)


func _removeActiveSlot(slot: int) -> void:
	var activeIndex: int = _activeListIndicesBySlot[slot]
	var lastIndex: int = _activeSlots.size() - 1
	var lastSlot: int = _activeSlots[lastIndex]

	if activeIndex != lastIndex:
		_activeSlots[activeIndex] = lastSlot
		_activeListIndicesBySlot[lastSlot] = activeIndex

	_activeSlots.pop_back()
	_activeListIndicesBySlot[slot] = INVALID_SLOT


func _growSlots(growSize: int) -> void:
	if growSize <= 0:
		return

	var oldCapacity: int = GetSlotCapacity()
	var newCapacity: int = oldCapacity + growSize

	_unitIdsBySlot.resize(newCapacity)
	_positionsBySlot.resize(newCapacity)
	_halfSizesBySlot.resize(newCapacity)
	_minCellXsBySlot.resize(newCapacity)
	_minCellYsBySlot.resize(newCapacity)
	_maxCellXsBySlot.resize(newCapacity)
	_maxCellYsBySlot.resize(newCapacity)
	_activeFlagsBySlot.resize(newCapacity)
	_queryStampsBySlot.resize(newCapacity)
	_activeListIndicesBySlot.resize(newCapacity)

	for slot: int in range(oldCapacity, newCapacity):
		_unitIdsBySlot[slot] = INVALID_UNIT_ID
		_activeFlagsBySlot[slot] = 0
		_queryStampsBySlot[slot] = 0
		_activeListIndicesBySlot[slot] = INVALID_SLOT

	for slot: int in range(newCapacity - 1, oldCapacity - 1, -1):
		_freeSlots.append(slot)


func _isActiveSlot(slot: int) -> bool:
	return (
		slot >= 0
		and slot < GetSlotCapacity()
		and _activeFlagsBySlot[slot] != 0
	)


func _isValidInt32(value: int) -> bool:
	return value >= 0 and value <= MAX_INT32_VALUE
