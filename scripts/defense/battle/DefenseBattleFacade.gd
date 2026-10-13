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
	if a == null or b == null:
		return false

	return (
		(a.faction == Faction.Type.ALLY and b.faction == Faction.Type.ENEMY)
		or (a.faction == Faction.Type.ENEMY and b.faction == Faction.Type.ALLY)
	)


func GetCharacterCount(characterType: CharacterType.Type) -> int:
	var manager: DefenseCharacterManager = _GetCharacterManager(characterType)
	if manager == null:
		return 0

	return manager.GetCharacterCount()


func GetCharacterByIndex(characterType: CharacterType.Type, index: int) -> Unit:
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
			attacker.faction == Faction.Type.ENEMY and target.faction == Faction.Type.ALLY
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


func _GetCharacterManager(characterType: CharacterType.Type) -> DefenseCharacterManager:
	match characterType:
		CharacterType.TOWER:
			return _towerManager

		CharacterType.MACHINE:
			return _machineManager

		CharacterType.TRAP:
			return _trapManager

		CharacterType.ENEMY:
			return _enemyManager

	return null
