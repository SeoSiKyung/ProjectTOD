class_name DefenseMonsterManager
extends DefenseCharacterManager


func AddMonster(monster: Unit, characterKey: int) -> bool:
	if monster == null:
		return false

	var characterData: CharacterData = GameDataManager.GetCharacterData(characterKey)
	if characterData == null:
		push_error("DefenseMonsterManager: 존재하지 않는 characterKey입니다. key: " + str(characterKey))
		return false

	if characterData.characterType != CharacterData.CharacterType.MONSTER:
		push_error("DefenseMonsterManager: MONSTER 타입이 아닌 캐릭터입니다. key: " + str(characterKey))
		return false

	var status: DefenseMonsterStatus = DefenseMonsterStatus.new(characterData)
	return _BindStatus(monster, status)
