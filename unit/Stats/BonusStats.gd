class_name BonusStats
extends RefCounted

var _ratio: PackedInt32Array = PackedInt32Array()
var _flat: PackedInt32Array = PackedInt32Array()

func _init() -> void:
	_ratio.resize(UnitStats.Type.COUNT)
	_flat.resize(UnitStats.Type.COUNT)

func GetBonus(type: int, base: int) -> int:
	return base * _ratio[type] / 1000 + _flat[type]
