class_name DefenseCharacterRemovalService
extends RefCounted

var _towerManager: DefenseTowerManager
var _machineManager: DefenseMachineManager
var _trapManager: DefenseTrapManager
var _monsterManager: DefenseMonsterManager

var _monsterPoolManager: DefensePoolManager.MonsterPoolManager
var _unitLifecycle: DefenseUnitLifecycle


func _init(
	towerManager: DefenseTowerManager,
	machineManager: DefenseMachineManager,
	trapManager: DefenseTrapManager,
	monsterManager: DefenseMonsterManager,
	monsterPoolManager: DefensePoolManager.MonsterPoolManager,
	unitLifecycle: DefenseUnitLifecycle,
) -> void:
	_towerManager = towerManager
	_machineManager = machineManager
	_trapManager = trapManager
	_monsterManager = monsterManager

	_monsterPoolManager = monsterPoolManager
	_unitLifecycle = unitLifecycle


func Remove(character: Unit) -> bool:
	if character == null:
		return false

	var characterManager: DefenseCharacterManager = _GetCharacterManager(character.characterType)
	if characterManager == null:
		return false

	var poolManager: DefensePoolManager

	if character.characterType == CharacterData.CharacterType.MONSTER:
		poolManager = _monsterPoolManager

	return _RemoveFromManager(character, characterManager, poolManager)


func CleanupAll() -> bool:
	if not _CleanupManager(_towerManager):
		return false

	if not _CleanupManager(_machineManager):
		return false

	if not _CleanupManager(_trapManager):
		return false

	if not _CleanupManager(_monsterManager, _monsterPoolManager):
		return false

	return true


func _RemoveFromManager(
	character: Unit,
	characterManager: DefenseCharacterManager,
	poolManager: DefensePoolManager = null,
) -> bool:
	# 먼저 전투 데이터에서 제거한다. 실패하면 Runtime 제거 또는 Pool 반환을 진행하면 안 된다.
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


func _GetCharacterManager(characterType: CharacterData.CharacterType) -> DefenseCharacterManager:
	match characterType:
		CharacterData.CharacterType.UNIT:
			return _towerManager
		CharacterData.CharacterType.MACHINE:
			return _machineManager
		CharacterData.CharacterType.TRAP:
			return _trapManager
		CharacterData.CharacterType.MONSTER:
			return _monsterManager

	return null
