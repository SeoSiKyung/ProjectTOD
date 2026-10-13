class_name DefenseUnitFactory
extends RefCounted

var _parent: Node2D


func _init(parent: Node2D) -> void:
	_parent = parent


func Create(characterData: CharacterData, position: Vector2) -> Unit:
	if characterData == null:
		push_error("DefenseUnitFactory: CharacterData가 없습니다.")
		return null

	var unit: Unit = UnitFactory.Create(characterData)
	if unit == null:
		return null

	unit.playerControllable = (characterData.characterType == CharacterType.TOWER)

	_parent.add_child(unit)
	unit.position = position

	return unit
