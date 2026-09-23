class_name DefenseCombatManager
extends RefCounted

signal DamageRequested(targetId: int, damage: int)

var _attackBuffer: AttackBuffer

var _damageByUnitId: PackedInt64Array
var _touchedTargetIds: PackedInt32Array
var _touchedTargetCount: int = 0

var _attackTickByUnitId: PackedInt32Array

var _isInitialized: bool = false


func Initialize(initialAttackCapacity: int) -> bool:
	if initialAttackCapacity < 0:
		push_error("DefenseCombatManager: initialAttackCapacity는 0 이상이어야 합니다.")
		return false

	_attackBuffer = AttackBuffer.new(initialAttackCapacity)

	_damageByUnitId.resize(initialAttackCapacity)
	_damageByUnitId.fill(0)
	_touchedTargetIds.resize(initialAttackCapacity)
	_touchedTargetIds.fill(0)
	_touchedTargetCount = 0

	_attackTickByUnitId.resize(initialAttackCapacity)
	_attackTickByUnitId.fill(0)

	_isInitialized = true
	return true


func AdvanceAttackTick(unitId: int, attackIntervalFrames: int) -> bool:
	if not _isInitialized:
		return false

	if unitId < 0:
		return false

	_EnsureAttackTickCapacity(unitId)

	if attackIntervalFrames <= 0:
		_attackTickByUnitId[unitId] = 0
		return false

	_attackTickByUnitId[unitId] += 1
	if _attackTickByUnitId[unitId] < attackIntervalFrames:
		return false

	_attackTickByUnitId[unitId] = 0
	return true


func ResetAttackTick(unitId: int) -> void:
	if not _isInitialized:
		return

	if unitId < 0 or unitId >= _attackTickByUnitId.size():
		return

	_attackTickByUnitId[unitId] = 0


func QueueAttack(attackerId: int, targetId: int, damage: int) -> bool:
	if not _isInitialized:
		return false

	if attackerId < 0 or targetId < 0:
		return false

	if damage < 0:
		return false

	return _attackBuffer.Add(attackerId, targetId, damage)


func FlushAttacks() -> void:
	if not _isInitialized:
		return

	var attackCount: int = _attackBuffer.GetCount()
	if attackCount == 0:
		return

	_touchedTargetCount = 0

	for index: int in attackCount:
		var targetId: int = _attackBuffer.GetTargetId(index)
		var damage: int = _attackBuffer.GetDamage(index)
		if damage <= 0:
			continue

		_AccumulateDamage(targetId, damage)

	_attackBuffer.Clear()

	for index: int in _touchedTargetCount:
		var targetId: int = _touchedTargetIds[index]
		var damage: int = _damageByUnitId[targetId]

		_damageByUnitId[targetId] = 0

		if damage > 0:
			DamageRequested.emit(targetId, damage)

	_touchedTargetCount = 0


func _AccumulateDamage(targetId: int, damage: int) -> void:
	_EnsureDamageCapacity(targetId)

	if _damageByUnitId[targetId] == 0:
		_AddTouchedTarget(targetId)

	_damageByUnitId[targetId] += damage


func _EnsureDamageCapacity(targetId: int) -> void:
	var requiredCapacity: int = targetId + 1
	var currentCapacity: int = _damageByUnitId.size()
	if requiredCapacity <= currentCapacity:
		return

	var newCapacity: int = maxi(
		requiredCapacity,
		maxi(currentCapacity * 2, AttackBuffer.MIN_CAPACITY),
	)
	_damageByUnitId.resize(newCapacity)


func _AddTouchedTarget(targetId: int) -> void:
	_EnsureTouchedTargetCapacity(_touchedTargetCount + 1)

	_touchedTargetIds[_touchedTargetCount] = targetId
	_touchedTargetCount += 1


func _EnsureTouchedTargetCapacity(requiredCapacity: int) -> void:
	var currentCapacity: int = _touchedTargetIds.size()
	if requiredCapacity <= currentCapacity:
		return

	var newCapacity: int = maxi(
		requiredCapacity,
		maxi(currentCapacity * 2, AttackBuffer.MIN_CAPACITY),
	)
	_touchedTargetIds.resize(newCapacity)


func _EnsureAttackTickCapacity(unitId: int) -> void:
	var requiredCapacity: int = unitId + 1
	var currentCapacity: int = _attackTickByUnitId.size()
	if requiredCapacity <= currentCapacity:
		return

	var newCapacity: int = maxi(
		requiredCapacity,
		maxi(currentCapacity * 2, AttackBuffer.MIN_CAPACITY),
	)
	_attackTickByUnitId.resize(newCapacity)
