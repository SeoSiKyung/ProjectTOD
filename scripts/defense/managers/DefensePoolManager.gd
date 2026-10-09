@abstract
class_name DefensePoolManager
extends RefCounted

var _pool: Node2D

var _inactiveObjectsByCharacterKey: Dictionary[int, Array] = { }
var _characterKeyByActiveObject: Dictionary[Node2D, int] = { }


func _init(pool: Node2D) -> void:
	_pool = pool


func Return(object: Node2D) -> bool:
	if not _characterKeyByActiveObject.has(object):
		return false

	var characterKey: int = _characterKeyByActiveObject[object]
	_characterKeyByActiveObject.erase(object)

	_DeactivateObject(object)
	_AddInactiveObject(characterKey, object)

	return true


func _Spawn(characterData: CharacterData, spawnPosition: Vector2) -> Node2D:
	if characterData == null:
		return null

	var characterKey: int = characterData.characterKey
	var object: Node2D = _TakeInactiveObject(characterKey)
	if object == null:
		object = _CreateObject(characterData)
		if object == null:
			return null

		_pool.add_child(object)

	_ActivateObject(object, spawnPosition)
	_characterKeyByActiveObject[object] = characterKey

	return object


func _TakeInactiveObject(characterKey: int) -> Node2D:
	if not _inactiveObjectsByCharacterKey.has(characterKey):
		return null

	var inactiveObjects: Array = _inactiveObjectsByCharacterKey[characterKey]
	if inactiveObjects.is_empty():
		return null

	return inactiveObjects.pop_back()


func _AddInactiveObject(characterKey: int, object: Node2D) -> void:
	if not _inactiveObjectsByCharacterKey.has(characterKey):
		_inactiveObjectsByCharacterKey[characterKey] = []

	var inactiveObjects: Array = _inactiveObjectsByCharacterKey[characterKey]
	inactiveObjects.append(object)


@abstract
func _CreateObject(_characterData: CharacterData) -> Node2D


func _ActivateObject(object: Node2D, spawnPosition: Vector2) -> void:
	object.position = spawnPosition
	if object is Unit:
		var unit: Unit = object as Unit
		unit.ResetForReuse()

	object.visible = true
	object.process_mode = Node.PROCESS_MODE_INHERIT


func _DeactivateObject(object: Node2D) -> void:
	if object is Unit:
		var unit: Unit = object as Unit
		unit.unitId = 0

	object.visible = false
	object.process_mode = Node.PROCESS_MODE_DISABLED


class EnemyPoolManager extends DefensePoolManager:
	func SpawnEnemy(characterData: CharacterData, spawnPosition: Vector2) -> Enemy:
		return _Spawn(characterData, spawnPosition) as Enemy


	func _CreateObject(characterData: CharacterData) -> Node2D:
		if characterData == null:
			push_error("EnemyPoolManager: CharacterData가 없습니다.")
			return null

		if characterData.characterType != CharacterData.CharacterType.ENEMY:
			push_error("EnemyPoolManager: ENEMY 타입이 아닙니다. key: " + str(characterData.characterKey))
			return null

		var unit: Unit = UnitFactory.Create(characterData)
		var enemy: Enemy = unit as Enemy
		if enemy == null:
			if unit != null:
				unit.free()

			push_error(
				"EnemyPoolManager: Enemy 생성에 실패했습니다. key: " + str(characterData.characterKey)
			)
			return null

		enemy.playerControllable = false

		return enemy
