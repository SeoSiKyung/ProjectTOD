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


func AreEnemies(a: Unit, b: Unit) -> bool:
	if _IsFriendlyType(a.characterType):
		return b.characterType == CharacterData.CharacterType.MONSTER

	if a.characterType == CharacterData.CharacterType.MONSTER:
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


func GetCP() -> CommandPost:
	return _cpManager.GetCP()


func GetCPStatus() -> CommandPostStatus:
	return _cpManager.GetStatus()


func IsValidTarget(attacker: Unit, target: Unit) -> bool:
	if not IsManagedUnit(attacker) or not IsManagedUnit(target):
		return false

	if attacker == target or not attacker.HasCharacterStats() or attacker.IsDead():
		return false

	if target == GetCP():
		var cpStatus: CommandPostStatus = GetCPStatus()
		return (
			attacker.characterType == CharacterData.CharacterType.MONSTER
			and cpStatus != null and not cpStatus.IsDestroyed()
		)

	if not target.HasCharacterStats() or target.IsDead():
		return false

	return AreEnemies(attacker, target)


func ApplyDamage(target: Unit, damage: int) -> bool:
	if damage <= 0 or not IsManagedUnit(target):
		return false

	if target == GetCP():
		var cpStatus: CommandPostStatus = GetCPStatus()
		if cpStatus == null or cpStatus.IsDestroyed():
			return false

		return _cpManager.TakeDamage(damage)

	if not target.HasCharacterStats() or target.IsDead():
		return false

	var manager: DefenseCharacterManager = _GetCharacterManager(target.characterType)
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
