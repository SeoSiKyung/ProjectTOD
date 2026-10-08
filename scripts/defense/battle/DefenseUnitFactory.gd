class_name DefenseUnitFactory
extends RefCounted

const DEFENSE_UNIT_GROUP_SCRIPT: Script = preload("res://unit/types/Tower.gd")

var _parent: Node2D


func _init(parent: Node2D) -> void:
	_parent = parent


func Create(characterData: CharacterData, position: Vector2) -> Unit:
	if characterData == null:
		push_error("DefenseUnitFactory: CharacterData가 없습니다.")
		return null

	if not _IsSupportedCharacterType(characterData.characterType):
		push_error(
			"DefenseUnitFactory: 지원하지 않는 CharacterType입니다. key: " + str(characterData.characterKey)
		)
		return null

	if characterData.prefabPath.is_empty():
		push_error(
			"DefenseUnitFactory: prefabPath가 비어있습니다. key: " + str(characterData.characterKey)
		)
		return null

	var scene: PackedScene = load(characterData.prefabPath) as PackedScene
	if scene == null:
		push_error("DefenseUnitFactory: Scene을 불러올 수 없습니다. path: " + characterData.prefabPath)
		return null

	var unit: Unit = scene.instantiate() as Unit
	if unit == null:
		push_error(
			"DefenseUnitFactory: Scene 루트가 Unit이 아닙니다. key: " + str(characterData.characterKey)
		)
		return null

	if characterData.characterType == CharacterData.CharacterType.UNIT:
		unit.set_script(DEFENSE_UNIT_GROUP_SCRIPT)
		if not unit is Tower:
			push_error(
				"DefenseUnitFactory: Tower 스크립트 적용에 실패했습니다. key: " + str(characterData.characterKey)
			)
			unit.queue_free()
			return null

	if not unit.ConfigureCharacter(characterData):
		unit.queue_free()
		return null

	unit.playerControllable = (characterData.characterType == CharacterData.CharacterType.UNIT)

	_parent.add_child(unit)
	unit.position = position

	return unit


func _IsSupportedCharacterType(characterType: CharacterData.CharacterType) -> bool:
	return (
		characterType == CharacterData.CharacterType.UNIT
		or characterType == CharacterData.CharacterType.MACHINE
		or characterType == CharacterData.CharacterType.TRAP
	)
