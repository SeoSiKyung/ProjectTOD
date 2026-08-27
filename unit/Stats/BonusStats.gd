class_name BonusStats
extends RefCounted

var _ratio: PackedInt32Array = PackedInt32Array()
var _flat: PackedInt32Array = PackedInt32Array()

func _init() -> void:
	_ratio.resize(UnitStatType.COUNT)
	_flat.resize(UnitStatType.COUNT)

func GetBonus(type: int, base: int) -> int:
	return base * _ratio[type] / 1000 + _flat[type]

func AddItem(item: int) -> void:
	pass
	
func AddBuff(buff: int) -> void:
	pass

func RemoveItem(item: int) -> void:
	pass
	
func RemoveBuff(buff: int) -> void:
	pass
