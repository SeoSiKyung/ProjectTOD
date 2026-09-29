class_name DefenseTrapManager
extends DefenseCharacterManager


func AddTrap(trap: Unit, characterData: CharacterData) -> bool:
	if trap == null:
		return false

	if characterData == null:
		push_error("DefenseTrapManager: CharacterData가 없습니다.")
		return false

	if characterData.characterType != CharacterData.CharacterType.TRAP:
		push_error(
			"DefenseTrapManager: TRAP 타입이 아닌 캐릭터입니다. key: " + str(characterData.characterKey)
		)
		return false

	if trap.characterKey != characterData.characterKey:
		if not trap.ConfigureCharacter(characterData):
			return false

	return RegisterCharacter(trap)
