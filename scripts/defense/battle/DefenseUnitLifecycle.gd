class_name DefenseUnitLifecycle
extends RefCounted

signal UnitUnregistered(unit: Unit)

var _unitRuntime: UnitRuntime
var _nextUnitId: int


func _init(unitRuntime: UnitRuntime, firstUnitId: int = 1) -> void:
	_unitRuntime = unitRuntime
	_nextUnitId = maxi(firstUnitId, 0)



func IsManagedUnit(unit: Unit) -> bool:
	return _unitRuntime != null and _unitRuntime.IsManagedUnit(unit)


func RegisterUnit(unit: Unit) -> bool:
	if unit == null or _unitRuntime == null:
		return false

	while _unitRuntime.HasUnit(_nextUnitId):
		_nextUnitId += 1

	var unitId: int = _nextUnitId
	_nextUnitId += 1
	return _unitRuntime.RegisterUnit(unit, unitId, unit.global_position)


func UnregisterUnit(unit: Unit) -> bool:
	if not IsManagedUnit(unit):
		return false

	if not _unitRuntime.UnregisterUnit(unit):
		return false

	UnitUnregistered.emit(unit)
	return true


func ReturnToPool(unit: Unit, poolManager: DefensePoolManager) -> bool:
	if unit == null or poolManager == null:
		return false

	if IsManagedUnit(unit) and not UnregisterUnit(unit):
		return false

	return poolManager.Return(unit)
