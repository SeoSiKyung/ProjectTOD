class_name DefenseUnitFactory
extends RefCounted

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

	var unit: Unit = UnitFactory.Create(characterData)
	if unit == null:
		return null

	unit.playerControllable = (characterData.characterType == CharacterData.CharacterType.TOWER)

	_parent.add_child(unit)
	unit.position = position

	return unit


func _IsSupportedCharacterType(characterType: CharacterData.CharacterType) -> bool:
	return (
		characterType == CharacterData.CharacterType.TOWER
		or characterType == CharacterData.CharacterType.MACHINE
		or characterType == CharacterData.CharacterType.TRAP
	)
