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

	if characterData.characterType == CharacterData.CharacterType.UNIT:
		var towerComponent: TowerComponent = TowerComponent.new()

		if not unit.AttachTowerComponent(towerComponent):
			push_error(
				"DefenseUnitFactory: TowerComponent 연결에 실패했습니다. key: "
				+ str(characterData.characterKey)
			)
			unit.free()
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
