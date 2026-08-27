class_name UnitStats
extends RefCounted

var finalStats: PackedInt32Array = PackedInt32Array()
var _baseStats: PackedInt32Array = PackedInt32Array()
var _bonusStats: BonusStats = BonusStats.new()

var currentHp: int
var currentMp: int

func _init() -> void:
	finalStats.resize(UnitStatType.COUNT)
	_baseStats.resize(UnitStatType.COUNT)
	LoadBaseStats()
	
func Set() -> void:
	UpdateFinalStats()
	currentHp = finalStats[UnitStatType.MAX_HP]
	currentMp = finalStats[UnitStatType.MAX_MP]
	
func LoadBaseStats() -> void:
	pass

func UpdateFinalStats() -> void:
	for type in range(UnitStatType.COUNT):
		var baseStat: int = _baseStats[type]
		finalStats[type] = baseStat + _bonusStats.GetBonus(type, baseStat)
		
