class_name AttackBuffer
extends RefCounted

const MIN_CAPACITY: int = 16

var _attackerIds: PackedInt32Array
var _targetIds: PackedInt32Array
var _damages: PackedInt32Array

var _count: int = 0


func _init(initialCapacity: int) -> void:
	var capacity: int = maxi(initialCapacity, MIN_CAPACITY)

	_attackerIds.resize(capacity)
	_targetIds.resize(capacity)
	_damages.resize(capacity)


func GetCount() -> int:
	return _count


func GetTargetId(index: int) -> int:
	return _targetIds[index]


func GetDamage(index: int) -> int:
	return _damages[index]


func Add(attackerId: int, targetId: int, damage: int) -> bool:
	if attackerId < 0 or targetId < 0 or damage < 0:
		return false

	_EnsureCapacity(_count + 1)

	_attackerIds[_count] = attackerId
	_targetIds[_count] = targetId
	_damages[_count] = damage

	_count += 1

	return true


func Clear() -> void:
	_count = 0


func _EnsureCapacity(requiredCapacity: int) -> void:
	var currentCapacity: int = _damages.size()
	if requiredCapacity <= currentCapacity:
		return

	var newCapacity: int = currentCapacity * 2
	_attackerIds.resize(newCapacity)
	_targetIds.resize(newCapacity)
	_damages.resize(newCapacity)
