class_name DefenseBattleFacade
extends RefCounted

var _unitRuntime: UnitRuntime
var _unitGroupManager: DefenseUnitGroupManager
var _machineManager: DefenseMachineManager
var _trapManager: DefenseTrapManager
var _monsterManager: DefenseMonsterManager
var _cpManager: DefenseCPManager


func _init(
	unitRuntime: UnitRuntime,
	unitGroupManager: DefenseUnitGroupManager,
	machineManager: DefenseMachineManager,
	trapManager: DefenseTrapManager,
	monsterManager: DefenseMonsterManager,
	cpManager: DefenseCPManager,
) -> void:
	_unitRuntime = unitRuntime
	_unitGroupManager = unitGroupManager
	_machineManager = machineManager
	_trapManager = trapManager
	_monsterManager = monsterManager
	_cpManager = cpManager


func IsManagedUnit(unit: Unit) -> bool:
	return _unitRuntime != null and _unitRuntime.IsManagedUnit(unit)


func GetUnit(unitId: int) -> Unit:
	if _unitRuntime == null:
		return null

	return _unitRuntime.GetUnit(unitId)


func AreEnemies(a: CharacterData.CharacterType, b: CharacterData.CharacterType) -> bool:
	if _IsFriendlyType(a):
		return b == CharacterData.CharacterType.MONSTER

	if a == CharacterData.CharacterType.MONSTER:
		return _IsFriendlyType(b)

	return false


func GetCharacterCount(characterType: CharacterData.CharacterType) -> int:
	var manager: DefenseCharacterManager = _GetCharacterManager(characterType)
	if manager == null:
		return 0

	return manager.GetCharacterCount()


func GetCharacterByIndex(characterType: CharacterData.CharacterType, index: int) -> Unit:
	var manager: DefenseCharacterManager = _GetCharacterManager(characterType)
	if manager == null:
		return null

	return manager.GetCharacterByIndex(index)


func GetCharacterStatus(character: Unit) -> DefenseCharacterStatus:
	if character == null:
		return null

	var status: DefenseCharacterStatus = _unitGroupManager.GetStatusByCharacter(character)
	if status != null:
		return status

	status = _machineManager.GetStatusByCharacter(character)
	if status != null:
		return status

	status = _trapManager.GetStatusByCharacter(character)
	if status != null:
		return status

	return _monsterManager.GetStatusByCharacter(character)


func GetCP() -> DefenseCP:
	return _cpManager.GetCP()


func GetCPStatus() -> DefenseCPStatus:
	return _cpManager.GetStatus()


func IsValidTarget(attacker: Unit, target: Unit) -> bool:
	if not IsManagedUnit(attacker) or not IsManagedUnit(target):
		return false

	if attacker == target:
		return false

	var attackerStatus: DefenseCharacterStatus = GetCharacterStatus(attacker)
	if attackerStatus == null or attackerStatus.IsDead():
		return false

	if target == GetCP():
		var cpStatus: DefenseCPStatus = GetCPStatus()
		return (
			attackerStatus.characterType == CharacterData.CharacterType.MONSTER
			and cpStatus != null and not cpStatus.IsDestroyed()
		)

	var targetStatus: DefenseCharacterStatus = GetCharacterStatus(target)
	if targetStatus == null or targetStatus.IsDead():
		return false

	return AreEnemies(attackerStatus.characterType, targetStatus.characterType)


func ApplyDamage(target: Unit, damage: int) -> bool:
	if damage <= 0 or not IsManagedUnit(target):
		return false

	if target == GetCP():
		var cpStatus: DefenseCPStatus = GetCPStatus()
		if cpStatus == null or cpStatus.IsDestroyed():
			return false

		return _cpManager.TakeDamage(damage)

	var status: DefenseCharacterStatus = GetCharacterStatus(target)
	if status == null or status.IsDead():
		return false

	var manager: DefenseCharacterManager = _GetCharacterManager(status.characterType)
	return manager != null and manager.TakeDamage(target, damage)


func _GetCharacterManager(characterType: CharacterData.CharacterType) -> DefenseCharacterManager:
	match characterType:
		CharacterData.CharacterType.UNIT:
			return _unitGroupManager

		CharacterData.CharacterType.MACHINE:
			return _machineManager

		CharacterData.CharacterType.TRAP:
			return _trapManager

		CharacterData.CharacterType.MONSTER:
			return _monsterManager

	return null


func _IsFriendlyType(characterType: CharacterData.CharacterType) -> bool:
	return (
		characterType == CharacterData.CharacterType.UNIT
		or characterType == CharacterData.CharacterType.MACHINE
		or characterType == CharacterData.CharacterType.TRAP
	)
