class_name DefenseTrapManager
extends DefenseCharacterManager


func AddTrap(trap: Trap, characterData: CharacterData) -> bool:
	if trap == null or characterData == null:
		return false

	if (
		characterData.characterType != CharacterData.CharacterType.TRAP
		or trap.characterType != CharacterData.CharacterType.TRAP
		or trap.characterKey != characterData.characterKey
	):
		push_error("DefenseTrapManager: Trap 데이터가 일치하지 않습니다.")
		return false

	return RegisterCharacter(trap)
