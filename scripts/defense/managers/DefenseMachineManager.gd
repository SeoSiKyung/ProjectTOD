class_name DefenseMachineManager
extends DefenseCharacterManager


func AddMachine(machine: Unit, characterData: CharacterData) -> bool:
	if machine == null:
		return false

	if characterData == null:
		push_error("DefenseMachineManager: CharacterData가 없습니다.")
		return false

	if characterData.characterType != CharacterData.CharacterType.MACHINE:
		push_error(
			"DefenseMachineManager: MACHINE 타입이 아닌 캐릭터입니다. key: " + str(characterData.characterKey)
		)
		return false

	var status: DefenseCharacterStatus = DefenseCharacterStatus.new(characterData)
	return _BindStatus(machine, status)
