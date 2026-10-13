class_name DefaultEnemyTargetPolicy
extends TargetPolicy


func GetPriority(_attacker: Unit, candidate: Unit, context: SelectionContext) -> int:
	if candidate == null:
		return INVALID_PRIORITY

	match context:
		SelectionContext.DEFAULT:
			match candidate.characterType:
				CharacterType.COMMAND_POST:
					return 100
				CharacterType.TOWER:
					return 0
		SelectionContext.ACQUISITION:
			match candidate.characterType:
				CharacterType.TOWER, \
						CharacterType.MACHINE, \
						CharacterType.TRAP:
					return 0

	return INVALID_PRIORITY
