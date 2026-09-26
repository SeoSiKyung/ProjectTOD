class_name DefenseUnitGroupManager
extends DefenseCharacterManager

var _unitGroupStatusByCell: Dictionary[Vector2i, DefenseUnitGroupStatus] = { }


func AddUnitGroup(
	cell: Vector2i,
	characterData: CharacterData,
	recruitRatio: int,
	totalPopulation: int,
) -> bool:
	if _unitGroupStatusByCell.has(cell) or characterData == null:
		return false

	var status: DefenseUnitGroupStatus = _CreateUnitGroupStatus(
		characterData,
		recruitRatio,
		totalPopulation,
	)
	if status == null:
		return false

	_unitGroupStatusByCell[cell] = status

	return true


func Clear() -> void:
	super.Clear()
	_unitGroupStatusByCell.clear()


func BindUnit(cell: Vector2i, unit: Unit) -> bool:
	var status: DefenseUnitGroupStatus = _unitGroupStatusByCell.get(cell)
	if status == null:
		return false

	return _BindStatus(unit, status)


func HasAliveUnitGroup() -> bool:
	for cell: Vector2i in _unitGroupStatusByCell:
		var status: DefenseUnitGroupStatus = _unitGroupStatusByCell[cell]
		if not status.IsDead():
			return true

	return false


func GetUnitGroupStatusByCell(cell: Vector2i) -> DefenseUnitGroupStatus:
	return _unitGroupStatusByCell.get(cell)


func GetRecruitedPopulation() -> int:
	var population: int = 0
	for cell: Vector2i in _unitGroupStatusByCell:
		var status: DefenseUnitGroupStatus = _unitGroupStatusByCell[cell]
		population += status.recruitedPopulation

	return population


func GetSurvivingPopulation() -> int:
	var population: int = 0
	for cell: Vector2i in _unitGroupStatusByCell:
		var status: DefenseUnitGroupStatus = _unitGroupStatusByCell[cell]
		population += status.survivingPopulation

	return population


func GetDeadPopulation() -> int:
	var population: int = 0
	for cell: Vector2i in _unitGroupStatusByCell:
		var status: DefenseUnitGroupStatus = _unitGroupStatusByCell[cell]
		population += status.GetDeadPopulation()

	return population


func _CreateUnitGroupStatus(
	characterData: CharacterData,
	recruitRatio: int,
	totalPopulation: int,
) -> DefenseUnitGroupStatus:
	var recruitedPopulation: int = Math.ApplyRatio(totalPopulation, recruitRatio)
	if recruitedPopulation <= 0:
		return null

	if characterData.characterType != CharacterData.CharacterType.UNIT:
		push_error(
			"DefenseUnitGroupManager: UNIT 타입이 아닌 캐릭터가 배치되었습니다. key: "
			+ str(characterData.characterKey)
		)
		return null

	return DefenseUnitGroupStatus.new(recruitedPopulation, characterData)
