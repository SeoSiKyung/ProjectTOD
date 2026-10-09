class_name DefenseBattleFacade
extends RefCounted

var _unitRuntime: UnitRuntime
var _towerManager: DefenseTowerManager
var _machineManager: DefenseMachineManager
var _trapManager: DefenseTrapManager
var _enemyManager: DefenseEnemyManager
var _cpManager: DefenseCPManager


func _init(
	unitRuntime: UnitRuntime,
	towerManager: DefenseTowerManager,
	machineManager: DefenseMachineManager,
	trapManager: DefenseTrapManager,
	enemyManager: DefenseEnemyManager,
	cpManager: DefenseCPManager,
) -> void:
	_unitRuntime = unitRuntime
	_towerManager = towerManager
	_machineManager = machineManager
	_trapManager = trapManager
	_enemyManager = enemyManager
	_cpManager = cpManager


func IsManagedUnit(unit: Unit) -> bool:
	return _unitRuntime != null and _unitRuntime.IsManagedUnit(unit)


func GetUnit(unitId: int) -> Unit:
	if _unitRuntime == null:
		return null

	return _unitRuntime.GetUnit(unitId)


func AreEnemies(a: Unit, b: Unit) -> bool:
	if _IsFriendlyType(a.characterType):
		return b.characterType == CharacterData.CharacterType.ENEMY

	if a.characterType == CharacterData.CharacterType.ENEMY:
		return _IsFriendlyType(b.characterType)

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


func GetCP() -> Unit:
	return _cpManager.GetCP()


func IsValidTarget(attacker: Unit, target: Unit) -> bool:
	if not IsManagedUnit(attacker) or not IsManagedUnit(target):
		return false

	if attacker == target or not attacker.HasCharacterStats() or attacker.IsDead():
		return false

	if target == GetCP():
		return (
			attacker.characterType == CharacterData.CharacterType.ENEMY
			and target.HasCharacterStats() and not target.IsDead()
		)

	if not target.HasCharacterStats() or target.IsDead():
		return false

	return AreEnemies(attacker, target)


func ApplyDamage(target: Unit, damage: int) -> bool:
	if damage <= 0 or not IsManagedUnit(target):
		return false

	if target == GetCP():
		if not target.HasCharacterStats() or target.IsDead():
			return false

		return _cpManager.TakeDamage(damage)

	if not target.HasCharacterStats() or target.IsDead():
		return false

	var manager: DefenseCharacterManager = _GetCharacterManager(target.characterType)
	return manager != null and manager.TakeDamage(target, damage)


func _GetCharacterManager(characterType: CharacterData.CharacterType) -> DefenseCharacterManager:
	match characterType:
		CharacterData.CharacterType.TOWER:
			return _towerManager

		CharacterData.CharacterType.MACHINE:
			return _machineManager

		CharacterData.CharacterType.TRAP:
			return _trapManager

		CharacterData.CharacterType.ENEMY:
			return _enemyManager

	return null


func _IsFriendlyType(characterType: CharacterData.CharacterType) -> bool:
	return (
		characterType == CharacterData.CharacterType.TOWER
		or characterType == CharacterData.CharacterType.MACHINE
		or characterType == CharacterData.CharacterType.TRAP
		or characterType == CharacterData.CharacterType.COMMAND_POST
	)
