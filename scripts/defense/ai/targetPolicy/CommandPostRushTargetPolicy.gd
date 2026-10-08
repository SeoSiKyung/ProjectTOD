class_name CommandPostRushTargetPolicy
extends TargetPolicy


func GetPriority(_attacker: Unit, candidate: Unit, _context: SelectionContext) -> int:
	if candidate == null:
		return INVALID_PRIORITY

	if candidate.characterType == CharacterData.CharacterType.COMMAND_POST:
		return 0

	return INVALID_PRIORITY
