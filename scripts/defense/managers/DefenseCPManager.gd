class_name DefenseCPManager
extends RefCounted

signal CPDestroyed

var _cp: CommandPost


func Initialize(cp: CommandPost, characterData: CharacterData) -> bool:
	if cp == null or characterData == null:
		return false

	if characterData.characterType != CharacterData.CharacterType.COMMAND_POST:
		push_error(
			"DefenseCPManager: COMMAND_POST 타입의 CharacterData가 아닙니다. key: "
			+ str(characterData.characterKey)
		)
		return false

	if not cp.ConfigureCharacter(characterData):
		return false

	_cp = cp
	return true


func TakeDamage(damage: int) -> bool:
	if _cp == null or _cp.IsDead():
		return false

	_cp.TakeDamage(damage)

	if _cp.IsDead():
		CPDestroyed.emit()

	return true


func ApplyStatBonus(type: CharacterStats.Type, flatValue: int, ratioValue: int) -> bool:
	if _cp == null:
		return false

	return _cp.AddStatBonus(type, flatValue, ratioValue)


func GetCP() -> CommandPost:
	return _cp


func GetPosition() -> Vector2:
	if _cp == null:
		return Vector2.ZERO

	return _cp.global_position


func Clear() -> void:
	_cp = null
