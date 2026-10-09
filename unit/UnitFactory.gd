class_name UnitFactory
extends RefCounted

const ALLY_SCENE: PackedScene = preload("res://unit/types/scenes/Ally.tscn")
const COMMAND_POST_SCENE: PackedScene = preload("res://unit/types/scenes/CommandPost.tscn")
const TOWER_SCENE: PackedScene = preload("res://unit/types/scenes/Tower.tscn")
const MACHINE_SCENE: PackedScene = preload("res://unit/types/scenes/Machine.tscn")
const TRAP_SCENE: PackedScene = preload("res://unit/types/scenes/Trap.tscn")
const ENEMY_SCENE: PackedScene = preload("res://unit/types/scenes/Enemy.tscn")


static func Create(characterData: CharacterData) -> Unit:
	if characterData == null:
		push_error("UnitFactory: CharacterData가 없습니다.")
		return null

	var scene: PackedScene = _GetCharacterScene(characterData.characterType)
	if scene == null:
		push_error("UnitFactory: 지원하지 않는 CharacterType입니다. key: " + str(characterData.characterKey))
		return null

	var instance: Node = scene.instantiate()
	var unit: Unit = instance as Unit
	if unit == null:
		push_error("UnitFactory: Scene 루트가 Unit이 아닙니다.")
		instance.free()
		return null

	if not _ApplyCharacterVisual(unit, characterData):
		unit.free()
		return null

	if not unit.ConfigureCharacter(characterData):
		unit.free()
		return null

	return unit


static func _GetCharacterScene(characterType: CharacterData.CharacterType) -> PackedScene:
	match characterType:
		CharacterData.CharacterType.ALLY:
			return ALLY_SCENE
		CharacterData.CharacterType.COMMAND_POST:
			return COMMAND_POST_SCENE
		CharacterData.CharacterType.TOWER:
			return TOWER_SCENE
		CharacterData.CharacterType.MACHINE:
			return MACHINE_SCENE
		CharacterData.CharacterType.TRAP:
			return TRAP_SCENE
		CharacterData.CharacterType.ENEMY:
			return ENEMY_SCENE
		_:
			return null


static func _ApplyCharacterVisual(unit: Unit, characterData: CharacterData) -> bool:
	var sprite: Sprite2D = unit.get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null:
		push_error("UnitFactory: Sprite2D를 찾을 수 없습니다.")
		return false

	if characterData.iconPath.is_empty():
		push_error("UnitFactory: 캐릭터 이미지 경로가 없습니다. key: " + str(characterData.characterKey))
		return false

	var texture: Texture2D = load(characterData.iconPath) as Texture2D
	if texture == null:
		push_error("UnitFactory: 캐릭터 이미지를 불러올 수 없습니다. path: " + characterData.iconPath)
		return false

	sprite.texture = texture
	return true
