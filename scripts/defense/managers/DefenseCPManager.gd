class_name DefenseCPManager
extends RefCounted

signal CPDestroyed

var _cp: DefenseCP
var _status: DefenseCPStatus


func Initialize(cp: DefenseCP, maxHp: int) -> bool:
	if maxHp <= 0:
		return false

	_cp = cp
	_status = DefenseCPStatus.new(maxHp)
	return true


func TakeDamage(damage: int) -> bool:
	if _status == null or _status.IsDestroyed():
		return false

	_status.TakeDamage(damage)

	if _status.IsDestroyed():
		CPDestroyed.emit()

	return true


func GetCP() -> DefenseCP:
	return _cp


func GetStatus() -> DefenseCPStatus:
	return _status


func GetPosition() -> Vector2:
	return _cp.global_position


func Clear() -> void:
	_status = null
