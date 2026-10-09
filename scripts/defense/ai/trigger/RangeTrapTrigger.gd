class_name RangeTrapTrigger
extends TrapTrigger


func CanTrigger(owner: Unit, target: Unit, distanceSquared: float) -> bool:
	if owner == null or target == null:
		return false

	if not owner.HasCharacterStats() or owner.IsDead():
		return false

	if not target.HasCharacterStats() or target.IsDead():
		return false

	if distanceSquared < 0.0:
		return false

	var attackRange: int = owner.GetStat(CharacterStats.Type.ATK_RANGE)
	return distanceSquared <= float(attackRange) * float(attackRange)
