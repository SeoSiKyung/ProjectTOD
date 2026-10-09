class_name Trap
extends Unit

var _trigger: TrapTrigger
var _hasActivated: bool = false


func ConfigureCharacter(characterData: CharacterData) -> bool:
	if characterData == null:
		return false

	if characterData.characterType != CharacterData.CharacterType.TRAP:
		push_error("Trap: TRAP 타입이 아닙니다.")
		return false

	_trigger = null
	_hasActivated = false

	if not super.ConfigureCharacter(characterData):
		return false

	_trigger = _CreateTrigger(characterData.triggerId)
	return _trigger != null


func CanTrigger(target: Unit, distanceSquared: float) -> bool:
	if _hasActivated or _trigger == null:
		return false

	return _trigger.CanTrigger(self, target, distanceSquared)


func HasActivated() -> bool:
	return _hasActivated


func CommitActivation() -> bool:
	if _hasActivated or _trigger == null:
		return false

	_hasActivated = true
	return true


func ResetForReuse() -> void:
	super.ResetForReuse()
	_hasActivated = false


func _CreateTrigger(triggerId: CharacterData.TriggerId) -> TrapTrigger:
	match triggerId:
		CharacterData.TriggerId.RANGE:
			return RangeTrapTrigger.new()
		_:
			push_error(
				"Trap: Trigger가 정의되지 않았습니다. key: " + str(characterKey)
				+ ", triggerId: " + str(triggerId)
			)
			return null
