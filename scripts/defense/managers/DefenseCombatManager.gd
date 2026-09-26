class_name DefenseCombatManager
extends RefCounted

var _battleContext: DefenseBattleFacade

var _attackBuffer: AttackBuffer

var _damageByUnitId: PackedInt64Array
var _touchedTargetIds: PackedInt32Array
var _touchedTargetCount: int = 0

var _attackTickByUnitId: PackedInt32Array

var _isInitialized: bool = false


func _init(battleContext: DefenseBattleFacade) -> void:
	_battleContext = battleContext


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


func Update() -> void:
	if not _isInitialized:
		return

	_UpdateCharacterCombat(CharacterData.CharacterType.UNIT)
	_UpdateCharacterCombat(CharacterData.CharacterType.MONSTER)


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

	if attackerId < 0 or targetId < 0 or damage < 0:
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
		if damage > 0:
			_AccumulateDamage(targetId, damage)

	_attackBuffer.Clear()

	for index: int in _touchedTargetCount:
		var targetId: int = _touchedTargetIds[index]
		var damage: int = _damageByUnitId[targetId]
		_damageByUnitId[targetId] = 0

		if damage <= 0:
			continue

		var target: Unit = _battleContext.GetUnit(targetId)
		if target != null:
			_battleContext.ApplyDamage(target, damage)

	_touchedTargetCount = 0


func _UpdateCharacterCombat(characterType: CharacterData.CharacterType) -> void:
	var characterCount: int = _battleContext.GetCharacterCount(characterType)
	for index: int in characterCount:
		var character: Unit = _battleContext.GetCharacterByIndex(characterType, index)
		_UpdateAttackerCombat(character)


func _UpdateAttackerCombat(attacker: Unit) -> void:
	if not _battleContext.IsManagedUnit(attacker):
		return

	if attacker.fsm == null or attacker.fsm.currentState != UnitFSM.State.ATTACK:
		ResetAttackTick(attacker.unitId)
		return

	var target: Unit = attacker.fsm.GetAttackTarget()
	if target == null or not _battleContext.IsValidTarget(attacker, target):
		ResetAttackTick(attacker.unitId)
		return

	var attackerStatus: DefenseCharacterStatus = _battleContext.GetCharacterStatus(attacker)
	if attackerStatus == null or attackerStatus.IsDead() or attackerStatus.attackIntervalFrames <= 0:
		ResetAttackTick(attacker.unitId)
		return

	if not AdvanceAttackTick(attacker.unitId, attackerStatus.attackIntervalFrames):
		return

	var damage: int = _CalculateDamage(attacker, target)
	if damage >= 0:
		QueueAttack(attacker.unitId, target.unitId, damage)


func _CalculateDamage(attacker: Unit, target: Unit) -> int:
	var attackerStatus: DefenseCharacterStatus = _battleContext.GetCharacterStatus(attacker)
	if attackerStatus == null or attackerStatus.IsDead():
		return -1

	if target == _battleContext.GetCP():
		return _CalculateCPDamage(attackerStatus)

	var targetStatus: DefenseCharacterStatus = _battleContext.GetCharacterStatus(target)
	if targetStatus == null or targetStatus.IsDead():
		return -1

	if attackerStatus.characterType == targetStatus.characterType:
		return -1

	return attackerStatus.CalculateDamage(targetStatus)


func _CalculateCPDamage(attackerStatus: DefenseCharacterStatus) -> int:
	if attackerStatus.characterType != CharacterData.CharacterType.MONSTER:
		return -1

	var cpStatus: DefenseCPStatus = _battleContext.GetCPStatus()
	if cpStatus == null or cpStatus.IsDestroyed():
		return -1

	return Math.CalculateDamage(attackerStatus.atk, 0, attackerStatus.magicAtk, 0)


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
