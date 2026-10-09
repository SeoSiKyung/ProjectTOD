class_name UnitFactory
extends RefCounted

const UNIT_SCENE: PackedScene = preload("res://unit/Unit.tscn")


static func Create(characterData: CharacterData) -> Unit:
	if characterData == null:
		push_error("UnitFactory: CharacterData가 없습니다.")
		return null

	var instance: Node = UNIT_SCENE.instantiate()
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
