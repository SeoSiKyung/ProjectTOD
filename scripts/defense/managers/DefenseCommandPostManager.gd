class_name DefenseCommandPostManager
extends RefCounted

signal CommandPostDestroyed

var _status: DefenseCommandPostStatus


func Initialize(maxHp: int) -> bool:
	if maxHp <= 0:
		return false

	_status = DefenseCommandPostStatus.new(maxHp)
	return true


func TakeDamage(damage: int) -> bool:
	if _status == null or _status.IsDestroyed():
		return false

	_status.TakeDamage(damage)

	if _status.IsDestroyed():
		CommandPostDestroyed.emit()

	return true


func GetStatus() -> DefenseCommandPostStatus:
	return _status


func Clear() -> void:
	_status = null
