extends Node

# 여기에 Dictionary 추가
var _characterDataByKey: Dictionary[int, CharacterData] = { }
var _characterDataByType: Dictionary[int, Array] = { }
var _defenseSpawnDataByCycle: Dictionary[int, Array] = { }

var _emptyDefenseSpawnDataList: Array[DefenseSpawnData] = []

#region Initialize, 수정 금지

var _isInitialized: bool = false


func _ready() -> void:
	Initialize()


func Initialize() -> void:
	if _isInitialized:
		return

	_LoadGameData()

	if not _ValidateGameData():
		push_error("GameDataManager: 게임 데이터 참조 검증에 실패했습니다.")

	_isInitialized = true

#endregion


#region Data Getters

func GetCharacterData(characterKey: int) -> CharacterData:
	return _characterDataByKey.get(characterKey)


func GetCharacterDataByType(characterType: CharacterData.CharacterType) -> Array[CharacterData]:
	return _characterDataByType[characterType]


func GetDefenseSpawnData(cycle: int) -> Array[DefenseSpawnData]:
	if not _defenseSpawnDataByCycle.has(cycle):
		return _emptyDefenseSpawnDataList

	return _defenseSpawnDataByCycle[cycle]

#endregion


# 여기서 Load 함수 호출
func _LoadGameData() -> void:
	_characterDataByKey = GameDataLoader.LoadCharacterData()
	_characterDataByType = _BuildCharacterDataByType()
	_defenseSpawnDataByCycle = GameDataLoader.LoadDefenseSpawnData()

	_emptyDefenseSpawnDataList.make_read_only()


# 여기서 참조 검증, Load 순서의 종속성을 없애기 위함!
func _ValidateGameData() -> bool:
	var isValid: bool = true

	if not GameDataLoader.ValidateDefenseSpawnDataReferences(
		_defenseSpawnDataByCycle,
		_characterDataByKey,
	):
		isValid = false

	return isValid


func _BuildCharacterDataByType() -> Dictionary[int, Array]:
	var characterDataByType: Dictionary[int, Array] = { }
	for characterType: CharacterData.CharacterType in CharacterData.CharacterType.COUNT:
		var characterDataList: Array[CharacterData] = []
		characterDataByType[characterType] = characterDataList

	for characterKey: int in _characterDataByKey:
		var characterData: CharacterData = _characterDataByKey[characterKey]
		var characterDataList: Array[CharacterData] = characterDataByType[
			characterData.characterType
		]
		characterDataList.append(characterData)

	for characterType: CharacterData.CharacterType in CharacterData.CharacterType.COUNT:
		characterDataByType[characterType].make_read_only()

	characterDataByType.make_read_only()
	return characterDataByType
