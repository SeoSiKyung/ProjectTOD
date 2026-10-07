class_name DefenseCPManager
extends RefCounted

signal CPDestroyed

var _cp: CommandPost
var _status: CommandPostStatus


func Initialize(cp: CommandPost, maxHp: int, defense: int, magicDefense: int) -> bool:
	if maxHp <= 0 or defense < 0 or magicDefense < 0:
		return false

	_cp = cp
	_status = CommandPostStatus.new(maxHp, defense, magicDefense)
	return true


func TakeDamage(damage: int) -> bool:
	if _status == null or _status.IsDestroyed():
		return false

	_status.TakeDamage(damage)

	if _status.IsDestroyed():
		CPDestroyed.emit()

	return true


func ApplyStatBonus(type: CharacterStats.Type, flatValue: int, ratioValue: int) -> bool:
	if _status == null:
		return false

	return _status.AddStatBonus(type, flatValue, ratioValue)


func GetCP() -> CommandPost:
	return _cp


func GetStatus() -> CommandPostStatus:
	return _status


func GetPosition() -> Vector2:
	return _cp.global_position


func Clear() -> void:
	_status = null
