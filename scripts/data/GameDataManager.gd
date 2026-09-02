extends Node

var _defenseSpawnDataByCycle: Dictionary = { }

var _isInitialized: bool = false


func _ready() -> void:
	Initialize()


func Initialize() -> void:
	if _isInitialized:
		return

	_LoadGameData()

	_isInitialized = true


# 여기에 Load 함수 추가
func _LoadGameData() -> void:
	_defenseSpawnDataByCycle = GameDataLoader.LoadDefenseSpawnData()

#region Data Getters
func GetDefenseSpawnData(cycle: int) -> Array:
	if not _defenseSpawnDataByCycle.has(cycle):
		return []

	return _defenseSpawnDataByCycle[cycle]

#endregion
