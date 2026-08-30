class_name UnitStats
extends RefCounted

enum Type {
	MAX_HP,
	MAX_MP,
	HP_REGEN,
	MP_REGEN,
	ATK,
	MAGIC_ATK,
	DEF,
	MAGIC_DEF,
	MOVE_SPEED,
	ATTACK_RAGNE,
	ACQUISITION_RANGE,
	COUNT
}

var finalStats: PackedInt32Array = PackedInt32Array()
var _baseStats: PackedInt32Array = PackedInt32Array()
var _bonusStats: BonusStats

func _init() -> void:
	finalStats.resize(UnitStats.Type.COUNT)
	
func loadBaseStat() -> void:
	pass

func Update() -> void:
	for type in range(UnitStats.Type.COUNT):
		var baseStat: int = _baseStats[type]
		finalStats[type] = baseStat + _bonusStats.GetBonus(type, baseStat)
		
