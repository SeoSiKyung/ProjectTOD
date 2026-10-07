class_name DefenseUnitGroupManager
extends DefenseCharacterManager

var _preparedPopulationByCell: Dictionary[Vector2i, int] = { }
var _unitGroupByCell: Dictionary[Vector2i, UnitGroup] = { }
var _cellByUnitGroup: Dictionary[UnitGroup, Vector2i] = { }
var _totalRecruitedPopulation: int = 0


func AddUnitGroup(
	cell: Vector2i,
	characterData: CharacterData,
	recruitRatio: int,
	totalPopulation: int,
) -> bool:
	if _preparedPopulationByCell.has(cell) or characterData == null:
		return false

	if characterData.characterType != CharacterData.CharacterType.UNIT:
		push_error(
			"DefenseUnitGroupManager: UNIT 타입이 아닌 캐릭터가 배치되었습니다. key: "
			+ str(characterData.characterKey)
		)
		return false

	var recruitedPopulation: int = Math.ApplyRatio(totalPopulation, recruitRatio)
	if recruitedPopulation <= 0:
		return false

	_preparedPopulationByCell[cell] = recruitedPopulation
	_totalRecruitedPopulation += recruitedPopulation
	return true


func Clear() -> void:
	super.Clear()
	_preparedPopulationByCell.clear()
	_unitGroupByCell.clear()
	_cellByUnitGroup.clear()
	_totalRecruitedPopulation = 0


func BindUnit(cell: Vector2i, unit: Unit) -> bool:
	if not _preparedPopulationByCell.has(cell) or _unitGroupByCell.has(cell):
		return false

	if not unit is UnitGroup:
		push_error("DefenseUnitGroupManager: UnitGroup이 아닌 Unit입니다. cell: " + str(cell))
		return false

	var unitGroup: UnitGroup = unit as UnitGroup
	if unitGroup.characterType != CharacterData.CharacterType.UNIT:
		return false

	if not RegisterCharacter(unitGroup):
		return false

	var recruitedPopulation: int = _preparedPopulationByCell[cell]
	if not unitGroup.InitializePopulation(recruitedPopulation):
		super.UnregisterCharacter(unitGroup)
		return false

	_unitGroupByCell[cell] = unitGroup
	_cellByUnitGroup[unitGroup] = cell
	return true


func UnregisterCharacter(character: Unit) -> bool:
	if not character is UnitGroup or not HasCharacter(character):
		return false

	var unitGroup: UnitGroup = character as UnitGroup
	var cell: Vector2i = _cellByUnitGroup.get(unitGroup, Vector2i(-1, -1))

	if not super.UnregisterCharacter(unitGroup):
		return false

	_cellByUnitGroup.erase(unitGroup)
	if cell != Vector2i(-1, -1):
		_unitGroupByCell.erase(cell)

	return true


func TakeDamage(character: Unit, damage: int) -> bool:
	if not character is UnitGroup or not HasCharacter(character) or character.IsDead():
		return false

	var unitGroup: UnitGroup = character as UnitGroup
	unitGroup.TakeDamage(damage)

	if unitGroup.IsDead():
		CharacterDied.emit(unitGroup)

	return true


func AddStatBonusToUnitGroup(
	cell: Vector2i,
	type: CharacterStats.Type,
	flatValue: int,
	ratioValue: int,
) -> bool:
	var unitGroup: UnitGroup = _unitGroupByCell.get(cell)
	return unitGroup != null and unitGroup.AddStatBonus(type, flatValue, ratioValue)


func RemoveStatBonusFromUnitGroup(
	cell: Vector2i,
	type: CharacterStats.Type,
	flatValue: int,
	ratioValue: int,
) -> bool:
	var unitGroup: UnitGroup = _unitGroupByCell.get(cell)
	return unitGroup != null and unitGroup.RemoveStatBonus(type, flatValue, ratioValue)


func AddStatBonusToAllUnitGroups(
	type: CharacterStats.Type,
	flatValue: int,
	ratioValue: int,
) -> bool:
	for unitGroup: UnitGroup in _unitGroupByCell.values():
		if not unitGroup.AddStatBonus(type, flatValue, ratioValue):
			return false

	return true


func RemoveStatBonusFromAllUnitGroups(
	type: CharacterStats.Type,
	flatValue: int,
	ratioValue: int,
) -> bool:
	for unitGroup: UnitGroup in _unitGroupByCell.values():
		if not unitGroup.RemoveStatBonus(type, flatValue, ratioValue):
			return false

	return true


func ClearStatBonuses() -> void:
	for unitGroup: UnitGroup in _unitGroupByCell.values():
		unitGroup.ClearStatBonuses()


func ResetVitals() -> void:
	for unitGroup: UnitGroup in _unitGroupByCell.values():
		unitGroup.ResetVitals()


func HasPreparedUnitGroup(cell: Vector2i) -> bool:
	return _preparedPopulationByCell.has(cell)


func GetUnitGroupByCell(cell: Vector2i) -> UnitGroup:
	return _unitGroupByCell.get(cell)


func GetRecruitedPopulation() -> int:
	return _totalRecruitedPopulation


func GetSurvivingPopulation() -> int:
	var population: int = 0
	for unitGroup: UnitGroup in _unitGroupByCell.values():
		population += unitGroup.GetSurvivingPopulation()

	return population


func GetDeadPopulation() -> int:
	return _totalRecruitedPopulation - GetSurvivingPopulation()
