class_name DefenseCombatManager
extends RefCounted

var _unitManager: UnitManager

var _unitGroupManager: DefenseUnitGroupManager
var _monsterManager: DefenseMonsterManager
var _cpManager: DefenseCPManager

var _attackBuffer: AttackBuffer
var _damageByUnitId: PackedInt64Array
var _touchedTargetIds: PackedInt32Array
var _touchedTargetCount: int = 0

var _attackTickByUnitId: PackedInt32Array

var _isInitialized: bool = false


func _init(
	unitManager: UnitManager,
	unitGroupManager: DefenseUnitGroupManager,
	monsterManager: DefenseMonsterManager,
	cpManager: DefenseCPManager,
) -> void:
	_unitManager = unitManager

	_unitGroupManager = unitGroupManager
	_monsterManager = monsterManager
	_cpManager = cpManager


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


func QueueAttack(attacker: Unit, target: Unit) -> bool:
	if not _isInitialized:
		return false

	if attacker == null or target == null:
		return false

	if not _unitManager.HasUnit(attacker.unitId) or not _unitManager.HasUnit(target.unitId):
		return false

	var damage: int = _CalculateDamage(attacker, target)
	if damage < 0:
		return false

	return _attackBuffer.Add(attacker.unitId, target.unitId, damage)


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

		_ApplyDamage(targetId, damage)

	_touchedTargetCount = 0


func UpdateAttacker(attacker: Unit, target: Unit) -> void:
	if not _isInitialized or attacker == null:
		return

	var unitId: int = attacker.unitId
	if not _unitManager.HasUnit(unitId):
		return

	_EnsureAttackTickCapacity(unitId)

	if attacker.fsm == null or attacker.fsm.currentState != UnitFSM.State.ATTACK:
		_attackTickByUnitId[unitId] = 0
		return

	if target == null:
		_attackTickByUnitId[unitId] = 0
		return

	var attackerStatus: DefenseCharacterStatus = _GetCharacterStatus(attacker)
	if attackerStatus == null or attackerStatus.IsDead():
		_attackTickByUnitId[unitId] = 0
		return

	var attackIntervalFrames: int = attackerStatus.attackIntervalFrames
	if attackIntervalFrames <= 0:
		_attackTickByUnitId[unitId] = 0
		return

	_attackTickByUnitId[unitId] += 1

	if _attackTickByUnitId[unitId] < attackIntervalFrames:
		return

	_attackTickByUnitId[unitId] = 0

	QueueAttack(attacker, target)


func _CalculateDamage(attacker: Unit, target: Unit) -> int:
	var attackerStatus: DefenseCharacterStatus = _GetCharacterStatus(attacker)
	if attackerStatus == null or attackerStatus.IsDead():
		return -1

	if target == _cpManager.GetCP():
		return _CalculateCPDamage(attackerStatus)

	var targetStatus: DefenseCharacterStatus = _GetCharacterStatus(target)
	if targetStatus == null or targetStatus.IsDead():
		return -1

	if attackerStatus.characterType == targetStatus.characterType:
		return -1

	return attackerStatus.CalculateDamage(targetStatus)


func _CalculateCPDamage(attackerStatus: DefenseCharacterStatus) -> int:
	if attackerStatus.characterType != CharacterData.CharacterType.MONSTER:
		return -1

	var cpStatus: DefenseCPStatus = _cpManager.GetStatus()
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


func _ApplyDamage(targetId: int, damage: int) -> void:
	if damage <= 0:
		return

	if not _unitManager.HasUnit(targetId):
		return

	var target: Unit = _unitManager.GetUnit(targetId)
	if target == null:
		return

	if target == _cpManager.GetCP():
		var cpStatus: DefenseCPStatus = _cpManager.GetStatus()
		if cpStatus == null or cpStatus.IsDestroyed():
			return

		_cpManager.TakeDamage(damage)
		return

	var targetStatus: DefenseCharacterStatus = _GetCharacterStatus(target)
	if targetStatus == null or targetStatus.IsDead():
		return

	var targetManager: DefenseCharacterManager = _GetCharacterManager(targetStatus.characterType)
	if targetManager == null:
		return

	targetManager.TakeDamage(target, damage)


func _GetCharacterStatus(character: Unit) -> DefenseCharacterStatus:
	var status: DefenseCharacterStatus = _unitGroupManager.GetStatusByCharacter(character)
	if status != null:
		return status

	return _monsterManager.GetStatusByCharacter(character)


func _GetCharacterManager(characterType: CharacterData.CharacterType) -> DefenseCharacterManager:
	match characterType:
		CharacterData.CharacterType.UNIT:
			return _unitGroupManager

		CharacterData.CharacterType.MONSTER:
			return _monsterManager

	return null
