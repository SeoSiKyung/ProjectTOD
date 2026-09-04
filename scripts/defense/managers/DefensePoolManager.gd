@abstract
class_name DefensePoolManager
extends RefCounted

var _pool: Node2D

var _inactiveObjectsByCharacterKey: Dictionary = { }
var _characterKeyByObject: Dictionary = { }
var _activeObjects: Dictionary = { }


func _init(pool: Node2D) -> void:
	_pool = pool


func _Spawn(characterKey: int, spawnPosition: Vector2) -> Node2D:
	var object: Node2D = _TakeInactiveObject(characterKey)
	if object == null:
		object = _CreateObject(characterKey)
		if object == null:
			return null

		_pool.add_child(object)
		_characterKeyByObject[object] = characterKey

	_ActivateObject(object, spawnPosition)
	_activeObjects[object] = true

	return object


func Return(object: Node2D) -> bool:
	if not _activeObjects.has(object):
		return false

	var characterKey: int = _characterKeyByObject[object]

	_activeObjects.erase(object)

	_DeactivateObject(object)
	_OnObjectReturned(object)

	if not _inactiveObjectsByCharacterKey.has(characterKey):
		_inactiveObjectsByCharacterKey[characterKey] = []
	_inactiveObjectsByCharacterKey[characterKey].append(object)

	return true


func GetActiveCount() -> int:
	return _activeObjects.size()


func _TakeInactiveObject(characterKey: int) -> Node2D:
	if not _inactiveObjectsByCharacterKey.has(characterKey):
		return null

	var inactiveObjects: Array = _inactiveObjectsByCharacterKey[characterKey]
	if inactiveObjects.is_empty():
		return null

	return inactiveObjects.pop_back()


@abstract
func _CreateObject(_characterKey: int) -> Node2D


func _ActivateObject(object: Node2D, spawnPosition: Vector2) -> void:
	object.position = spawnPosition
	object.visible = true
	object.process_mode = Node.PROCESS_MODE_INHERIT


func _DeactivateObject(object: Node2D) -> void:
	object.visible = false
	object.process_mode = Node.PROCESS_MODE_DISABLED


func _OnObjectReturned(_object: Node2D) -> void:
	pass


class MonsterPoolManager extends DefensePoolManager:
	# TODO: 실제 Monster Scene 구현 후 CharacterData.path 기반 생성으로 교체
	const TEMP_MONSTER_SCENE: PackedScene = preload("res://unit/unit.tscn")
	const TEMP_MONSTER_COLOR: Color = Color(1.0, 0.25, 0.25, 1.0)


	func SpawnMonster(characterKey: int, spawnPosition: Vector2) -> Node2D:
		return _Spawn(characterKey, spawnPosition)


	func _CreateObject(characterKey: int) -> Node2D:
		var characterData: CharacterData = GameDataManager.GetCharacterData(characterKey)
		if characterData == null:
			push_error("MonsterPoolManager: 존재하지 않는 characterKey입니다. key: " + str(characterKey))
			return null

		if characterData.characterType != CharacterData.CharacterType.MONSTER:
			push_error("MonsterPoolManager: MONSTER 타입이 아닌 캐릭터입니다. key: " + str(characterKey))
			return null

		var monster: Unit = TEMP_MONSTER_SCENE.instantiate() as Unit
		if monster == null:
			push_error("MonsterPoolManager: 임시 몬스터 Unit 생성에 실패했습니다.")
			return null

		monster.playerControllable = false
		monster.modulate = TEMP_MONSTER_COLOR

		return monster


class UnitPoolManager extends DefensePoolManager:
	var _unitGroupStateByUnit: Dictionary = { }


	func SpawnUnit(
		characterKey: int,
		spawnPosition: Vector2,
		unitGroupState: DefenseUnitGroupManager.DefenseUnitGroupState = null,
	) -> Unit:
		var unit: Unit = _Spawn(characterKey, spawnPosition) as Unit
		if unit == null:
			return null

		if unitGroupState != null:
			_unitGroupStateByUnit[unit] = unitGroupState

		return unit


	func GetUnitGroupState(unit: Unit) -> DefenseUnitGroupManager.DefenseUnitGroupState:
		return _unitGroupStateByUnit.get(unit)


	func _CreateObject(characterKey: int) -> Node2D:
		var characterData: CharacterData = GameDataManager.GetCharacterData(characterKey)
		if characterData == null:
			push_error("UnitPoolManager: 존재하지 않는 characterKey입니다. key: " + str(characterKey))
			return null

		if characterData.characterType != CharacterData.CharacterType.UNIT:
			push_error("UnitPoolManager: UNIT 타입이 아닌 캐릭터입니다. key: " + str(characterKey))
			return null

		if characterData.path.is_empty():
			push_error("UnitPoolManager: 캐릭터 path가 비어있습니다. key: " + str(characterKey))
			return null

		var scene: PackedScene = load(characterData.path) as PackedScene
		if scene == null:
			push_error("UnitPoolManager: 캐릭터 scene을 불러올 수 없습니다. path: " + characterData.path)
			return null

		var unit: Unit = scene.instantiate() as Unit
		if unit == null:
			push_error("UnitPoolManager: 캐릭터 scene의 루트가 Unit이 아닙니다. key: " + str(characterKey))
			return null

		return unit


	func _OnObjectReturned(object: Node2D) -> void:
		var unit: Unit = object as Unit
		_unitGroupStateByUnit.erase(unit)
