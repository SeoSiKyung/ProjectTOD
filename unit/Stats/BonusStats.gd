class_name BonusStats
extends RefCounted

var _ratio: PackedInt32Array = PackedInt32Array()
var _flat: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	_ratio.resize(CharacterStats.Type.COUNT)
	_flat.resize(CharacterStats.Type.COUNT)
	Clear()


func GetBonus(type: CharacterStats.Type, base: int) -> int:
	if not CharacterStats.IsValidType(type):
		return 0

	return Math.ApplyRatio(base, _ratio[type]) + _flat[type]


func AddBonus(type: CharacterStats.Type, flatValue: int, ratioValue: int) -> bool:
	if not CharacterStats.IsValidType(type):
		return false

	_ratio[type] += ratioValue
	_flat[type] += flatValue
	return true


func RemoveBonus(type: CharacterStats.Type, flatValue: int, ratioValue: int) -> bool:
	if not CharacterStats.IsValidType(type):
		return false

	_ratio[type] -= ratioValue
	_flat[type] -= flatValue
	return true


func Clear() -> void:
	_ratio.fill(0)
	_flat.fill(0)
