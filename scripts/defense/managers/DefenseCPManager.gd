class_name DefenseCPManager
extends RefCounted

signal CPDestroyed

var _status: DefenseCPStatus


func Initialize(maxHp: int) -> bool:
	if maxHp <= 0:
		return false

	_status = DefenseCPStatus.new(maxHp)
	return true


func TakeDamage(damage: int) -> bool:
	if _status == null or _status.IsDestroyed():
		return false

	_status.TakeDamage(damage)

	if _status.IsDestroyed():
		CPDestroyed.emit()

	return true


func GetStatus() -> DefenseCPStatus:
	return _status


func Clear() -> void:
	_status = null
