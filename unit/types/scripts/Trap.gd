class_name Trap
extends Unit

var _hasActivated: bool = false


func ConfigureCharacter(characterData: CharacterData) -> bool:
	if characterData == null:
		return false

	if characterData.characterType != CharacterData.CharacterType.TRAP:
		push_error("Trap: TRAP 타입이 아닙니다.")
		return false

	_hasActivated = false
	return super.ConfigureCharacter(characterData)


func CanTrigger(target: Unit, distanceSquared: float) -> bool:
	if _hasActivated or target == null:
		return false

	if not HasCharacterStats() or IsDead():
		return false

	if not target.HasCharacterStats() or target.IsDead():
		return false

	if distanceSquared < 0.0:
		return false

	var attackRange: int = GetStat(CharacterStats.Type.ATK_RANGE)
	return distanceSquared <= float(attackRange) * float(attackRange)


func HasActivated() -> bool:
	return _hasActivated


func CommitActivation() -> bool:
	if _hasActivated:
		return false

	_hasActivated = true
	return true


func ResetForReuse() -> void:
	super.ResetForReuse()
	_hasActivated = false
