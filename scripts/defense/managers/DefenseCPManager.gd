class_name DefenseCPManager
extends RefCounted

signal CPDestroyed

var _cpCharacterKey: int = -1
var _cp: CommandPost


func Initialize(cp: CommandPost, cpCharacterKey: int) -> bool:
	if cp == null:
		push_error("DefenseCPManager: CP가 없습니다.")
		return false

	if cp.characterKey != cpCharacterKey:
		push_error("DefenseCPManager: CP 캐릭터 키가 일치하지 않습니다. key: " + str(cpCharacterKey))
		return false

	if cp.characterType != CharacterData.CharacterType.COMMAND_POST:
		push_error("DefenseCPManager: COMMAND_POST 타입이 아닙니다.")
		return false

	if not cp.HasCharacterStats():
		push_error("DefenseCPManager: CP 스탯이 초기화되지 않았습니다.")
		return false

	_cpCharacterKey = cpCharacterKey
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


func GetCPCharacterKey() -> int:
	return _cpCharacterKey


func GetPosition() -> Vector2:
	if _cp == null:
		return Vector2.ZERO

	return _cp.global_position


func Clear() -> void:
	_cpCharacterKey = -1
	_cp = null
