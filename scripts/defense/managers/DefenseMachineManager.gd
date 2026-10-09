class_name DefenseMachineManager
extends DefenseCharacterManager


func AddMachine(machine: Unit, characterData: CharacterData) -> bool:
	if machine == null or characterData == null:
		return false

	if (
		characterData.characterType != CharacterData.CharacterType.MACHINE
		or machine.characterType != CharacterData.CharacterType.MACHINE
		or machine.characterKey != characterData.characterKey
	):
		push_error("DefenseMachineManager: Machine 데이터가 일치하지 않습니다.")
		return false

	return RegisterCharacter(machine)
