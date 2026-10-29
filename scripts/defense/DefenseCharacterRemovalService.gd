class_name DefenseCharacterRemovalService
extends RefCounted

var _towerManager: DefenseTowerManager
var _machineManager: DefenseMachineManager
var _trapManager: DefenseTrapManager
var _enemyManager: DefenseEnemyManager

var _enemyPoolManager: DefensePoolManager.EnemyPoolManager
var _unitLifecycle: DefenseUnitLifecycle


func _init(
	towerManager: DefenseTowerManager,
	machineManager: DefenseMachineManager,
	trapManager: DefenseTrapManager,
	enemyManager: DefenseEnemyManager,
	enemyPoolManager: DefensePoolManager.EnemyPoolManager,
	unitLifecycle: DefenseUnitLifecycle,
) -> void:
	_towerManager = towerManager
	_machineManager = machineManager
	_trapManager = trapManager
	_enemyManager = enemyManager

	_enemyPoolManager = enemyPoolManager
	_unitLifecycle = unitLifecycle


func Remove(character: Unit) -> bool:
	if character == null:
		return false

	var characterManager: DefenseCharacterManager = _GetCharacterManager(character.characterType)
	if characterManager == null:
		return false

	var poolManager: DefensePoolManager

	if character.characterType == CharacterType.ENEMY:
		poolManager = _enemyPoolManager

	return _RemoveFromManager(character, characterManager, poolManager)


func CleanupAll() -> bool:
	if not _CleanupManager(_towerManager):
		return false

	if not _CleanupManager(_machineManager):
		return false

	if not _CleanupManager(_trapManager):
		return false

	if not _CleanupManager(_enemyManager, _enemyPoolManager):
		return false

	return true


func _RemoveFromManager(
	character: Unit,
	characterManager: DefenseCharacterManager,
	poolManager: DefensePoolManager = null,
) -> bool:
	if not characterManager.HasCharacter(character):
		push_error(
			"DefenseCharacterRemovalService: CharacterManager에 등록되지 않은 Character입니다. unitId: "
			+ str(character.unitId)
		)
		return false

	if not _unitLifecycle.IsManagedUnit(character):
		push_error(
			"DefenseCharacterRemovalService: Runtime에 등록되지 않은 Character입니다. unitId: "
			+ str(character.unitId)
		)
		return false

	if poolManager != null and not poolManager.CanReturn(character):
		push_error(
			"DefenseCharacterRemovalService: Pool에 등록되지 않은 Character입니다. unitId: "
			+ str(character.unitId)
		)
		return false

	if not characterManager.UnregisterCharacter(character):
		push_error(
			"DefenseCharacterRemovalService: Character 연결 해제에 실패했습니다. unitId: "
			+ str(character.unitId)
		)
		return false

	# 그 다음 Runtime 제거 + 필요하면 Pool 반환.
	if poolManager != null:
		if not _unitLifecycle.ReturnToPool(character, poolManager):
			push_error(
				"DefenseCharacterRemovalService: Character Pool 반환에 실패했습니다. unitId: "
				+ str(character.unitId)
			)
			return false
	else:
		if not _unitLifecycle.DestroyUnit(character):
			push_error(
				"DefenseCharacterRemovalService: Character 제거에 실패했습니다. unitId: "
				+ str(character.unitId)
			)
			return false

	return true


func _CleanupManager(
	characterManager: DefenseCharacterManager,
	poolManager: DefensePoolManager = null,
) -> bool:
	while characterManager.GetCharacterCount() > 0:
		var lastIndex: int = characterManager.GetCharacterCount() - 1
		var character: Unit = characterManager.GetCharacterByIndex(lastIndex)

		if not _RemoveFromManager(character, characterManager, poolManager):
			return false

	return true


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
