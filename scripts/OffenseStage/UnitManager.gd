class_name UnitManager
extends RefCounted

const INVALID_INDEX: int = -1
const MAX_INT32_VALUE: int = 2147483647

var _units: Array[Unit] = []
var _unitIdsByIndex: PackedInt32Array = []
var _unitIndexById: Dictionary[int, int] = {}

func GetUnitCount() -> int:
	return _units.size()

func HasUnit(unitId: int) -> bool:
	return _unitIndexById.has(unitId)

func GetUnit(unitId: int) -> Unit:
	var index: int = _unitIndexById.get(unitId, INVALID_INDEX)
	if index == INVALID_INDEX:
		return null

	var unit: Unit = _units[index]
	if not is_instance_valid(unit):
		return null

	return unit


func RegisterUnit(unitId: int, unit: Unit) -> bool:
	if not is_instance_valid(unit):
		push_error("유효하지 않은 Unit은 등록할 수 없습니다.")
		return false

	if unit.is_queued_for_deletion():
		push_error("삭제 대기 중인 Unit은 등록할 수 없습니다.")
		return false

	if _units.has(unit):
		push_error("같은 Unit 객체가 이미 UnitManager에 등록되어 있습니다.")
		return false

	var index: int = _units.size()
	_units.append(unit)
	_unitIdsByIndex.append(unitId)
	_unitIndexById[unitId] = index
	
	return true

func _UnregisterUnit(unitId: int) -> Unit:
	var index: int = _unitIndexById.get(unitId, INVALID_INDEX)

	if index == INVALID_INDEX:
		return null

	var removedUnit: Unit = _units[index]
	var lastIndex: int = _units.size() - 1

	if index != lastIndex:
		var lastUnit: Unit = _units[lastIndex]
		var lastUnitId: int = _unitIdsByIndex[lastIndex]

		_units[index] = lastUnit
		_unitIdsByIndex[index] = lastUnitId
		_unitIndexById[lastUnitId] = index

	_units.pop_back()
	_unitIdsByIndex.resize(lastIndex)
	_unitIndexById.erase(unitId)

	return removedUnit

func DestroyUnit(unitId: int) -> void:
	var unit: Unit = _UnregisterUnit(unitId)
	if is_instance_valid(unit) and not unit.is_queued_for_deletion():
		unit.queue_free()

func SyncPositions(snapshot: StageSnapshot) -> void:
	for idx: int in range(_units.size()):
		var unitId: int = _unitIdsByIndex[idx]

		if not snapshot.HasUnit(unitId):
			push_error("StageSnapshot에 unitId %d가 없습니다." % unitId)
			continue

		var unit: Unit = _units[idx]

		if not is_instance_valid(unit):
			push_error("UnitManager에 유효하지 않은 Unit이 남아 있습니다.")
			continue

		unit.global_position = snapshot.GetPosition(unitId)


func Clear() -> void:
	for unit: Unit in _units:
		if is_instance_valid(unit) and not unit.is_queued_for_deletion():
			unit.queue_free()

	_units.clear()
	_unitIdsByIndex.clear()
	_unitIndexById.clear()
