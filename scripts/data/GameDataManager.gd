extends Node

# 여기에 Dictionary 추가
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

	if not _ValidateGameData():
		push_error("GameDataManager: 게임 데이터 참조 검증에 실패했습니다.")


# 여기서 참조 검증, Load 순서의 종속성을 없애기 위함!
func _ValidateGameData() -> bool:
	var isValid: bool = true

	if not GameDataLoader.ValidateDefenseSpawnDataReferences(
		_defenseSpawnDataByCycle,
		_characterDataByKey,
	):
		isValid = false

	return isValid

#region Data Getters
func GetCharacterData(characterKey: int) -> CharacterData:
	return _characterDataByKey.get(characterKey)


func GetDefenseSpawnData(cycle: int) -> Array[DefenseSpawnData]:
	var spawnDataList: Array[DefenseSpawnData] = []
	if not _defenseSpawnDataByCycle.has(cycle):
		return spawnDataList

	spawnDataList.assign(_defenseSpawnDataByCycle[cycle])
	return spawnDataList

#endregion
