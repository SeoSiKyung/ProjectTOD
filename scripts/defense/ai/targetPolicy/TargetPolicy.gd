class_name TargetPolicy
extends Resource

enum SelectionContext {
	DEFAULT,
	ACQUISITION,
}

const INVALID_PRIORITY: int = -1


func GetPriority(_attacker: Unit, _candidate: Unit, _context: SelectionContext) -> int:
	return INVALID_PRIORITY
