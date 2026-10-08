class_name DefaultMonsterTargetPolicy
extends TargetPolicy


func GetPriority(_attacker: Unit, candidate: Unit, context: SelectionContext) -> int:
	if candidate == null:
		return INVALID_PRIORITY

	match context:
		SelectionContext.DEFAULT:
			match candidate.characterType:
				CharacterData.CharacterType.COMMAND_POST:
					return 100
				CharacterData.CharacterType.UNIT:
					return 0
		SelectionContext.ACQUISITION:
			match candidate.characterType:
				CharacterData.CharacterType.UNIT, \
						CharacterData.CharacterType.MACHINE, \
						CharacterData.CharacterType.TRAP:
					return 0

	return INVALID_PRIORITY
