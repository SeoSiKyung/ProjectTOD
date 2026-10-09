class_name Enemy
extends Unit


func ConfigureCharacter(characterData: CharacterData) -> bool:
	if characterData == null:
		return false

	if characterData.characterType != CharacterData.CharacterType.ENEMY:
		push_error("Enemy: ENEMY 타입이 아닙니다.")
		return false

	return super.ConfigureCharacter(characterData)
