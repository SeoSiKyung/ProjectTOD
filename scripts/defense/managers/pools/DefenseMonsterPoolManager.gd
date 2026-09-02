class_name DefenseMonsterPoolManager
extends RefCounted

var _monsterPool: Node2D

var _inactiveMonstersByCharacterKey: Dictionary = { }
var _characterKeyByMonster: Dictionary = { }
var _activeMonsters: Dictionary = { }


func _init(monsterPool: Node2D):
	_monsterPool = monsterPool


func Spawn(characterKey: int, spawnPosition: Vector2 = Vector2.ZERO) -> Node2D:
	var monster: Node2D = _TakeInactiveMonster(characterKey)
	if monster == null:
		monster = _CreateMonster(characterKey)

	_ActivateMonster(monster, spawnPosition)
	_activeMonsters[monster] = true

	return monster


func Return(monster: Node2D) -> bool:
	if not _activeMonsters.has(monster):
		return false

	var characterKey: int = _characterKeyByMonster[monster]

	_activeMonsters.erase(monster)
	_DeactivateMonster(monster)

	if not _inactiveMonstersByCharacterKey.has(characterKey):
		_inactiveMonstersByCharacterKey[characterKey] = []

	_inactiveMonstersByCharacterKey[characterKey].append(monster)

	return true


func GetActiveMonsterCount() -> int:
	return _activeMonsters.size()


func _TakeInactiveMonster(characterKey: int) -> Node2D:
	if not _inactiveMonstersByCharacterKey.has(characterKey):
		return null

	var inactiveMonsters: Array = _inactiveMonstersByCharacterKey[characterKey]
	if inactiveMonsters.is_empty():
		return null

	return inactiveMonsters.pop_back()


func _CreateMonster(characterKey: int) -> Node2D:
	# TODO:
	# var characterData: CharacterData = GameDataManager.GetCharacterData(characterKey)
	# var monster: Node2D = characterData.scene.instantiate()
	var monster: Node2D = Node2D.new()
	_monsterPool.add_child(monster)
	_characterKeyByMonster[monster] = characterKey

	return monster


func _ActivateMonster(monster: Node2D, spawnPosition: Vector2) -> void:
	monster.position = spawnPosition
	monster.visible = true
	monster.process_mode = Node.PROCESS_MODE_INHERIT


func _DeactivateMonster(monster: Node2D) -> void:
	monster.visible = false
	monster.process_mode = Node.PROCESS_MODE_DISABLED
