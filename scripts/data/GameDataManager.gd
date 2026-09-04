extends Node

# 여기에 Dictionary 하나 추가
var _characterDataByKey: Dictionary = { }
var _defenseSpawnDataByCycle: Dictionary = { }

#region 수정 금지

var _isInitialized: bool = false


func _ready() -> void:
	Initialize()


func Initialize() -> void:
	if _isInitialized:
		return

	_LoadGameData()

	_isInitialized = true

#endregion

# 여기서 Load 함수 호출
func _LoadGameData() -> void:
	_characterDataByKey = GameDataLoader.LoadCharacterData()
	_defenseSpawnDataByCycle = GameDataLoader.LoadDefenseSpawnData()

#region Data Getters
func GetCharacterData(characterKey: int) -> CharacterData:
	return _characterDataByKey.get(characterKey)


func GetDefenseSpawnData(cycle: int) -> Array:
	if not _defenseSpawnDataByCycle.has(cycle):
		return []

	return _defenseSpawnDataByCycle[cycle]

#endregion
