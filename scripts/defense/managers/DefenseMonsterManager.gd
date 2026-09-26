class_name DefenseMonsterManager
extends DefenseCharacterManager


func AddMonster(monster: Unit, characterData: CharacterData) -> bool:
	if monster == null:
		return false

	if characterData == null:
		push_error("DefenseMonsterManager: CharacterData가 없습니다.")
		return false

	if characterData.characterType != CharacterData.CharacterType.MONSTER:
		push_error(
			"DefenseMonsterManager: MONSTER 타입이 아닌 캐릭터입니다. key: "
			+ str(characterData.characterKey)
		)
		return false

	var status: DefenseMonsterStatus = DefenseMonsterStatus.new(characterData)
	return _BindStatus(monster, status)
