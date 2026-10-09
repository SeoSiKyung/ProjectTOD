class_name DefenseTowerManager
extends DefenseCharacterManager

var _preparedPopulationByCell: Dictionary[Vector2i, int] = { }
var _towerByCell: Dictionary[Vector2i, Unit] = { }
var _cellByTower: Dictionary[Unit, Vector2i] = { }
var _totalRecruitedPopulation: int = 0


func AddTower(
	cell: Vector2i,
	characterData: CharacterData,
	recruitRatio: int,
	totalPopulation: int,
) -> bool:
	if _preparedPopulationByCell.has(cell) or characterData == null:
		return false

	if characterData.characterType != CharacterData.CharacterType.UNIT:
		push_error(
			"DefenseTowerManager: UNIT 타입이 아닌 캐릭터가 배치되었습니다. key: " + str(characterData.characterKey)
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
	_towerByCell.clear()
	_cellByTower.clear()
	_totalRecruitedPopulation = 0


func BindUnit(cell: Vector2i, unit: Unit) -> bool:
	if unit == null or not _preparedPopulationByCell.has(cell) or _towerByCell.has(cell):
		return false

	if unit.characterType != CharacterData.CharacterType.UNIT:
		return false

	var towerComponent: TowerComponent = unit.GetTowerComponent()
	if towerComponent == null:
		push_error("DefenseTowerManager: TowerComponent가 없습니다. cell: " + str(cell))
		return false

	if not RegisterCharacter(unit):
		return false

	var recruitedPopulation: int = _preparedPopulationByCell[cell]
	if not towerComponent.InitializePopulation(recruitedPopulation):
		super.UnregisterCharacter(unit)
		return false

	unit.ResetVitals()

	_towerByCell[cell] = unit
	_cellByTower[unit] = cell
	return true


func UnregisterCharacter(character: Unit) -> bool:
	if not HasCharacter(character):
		return false

	var cell: Vector2i = _cellByTower.get(character, Vector2i(-1, -1))

	if not super.UnregisterCharacter(character):
		return false

	_cellByTower.erase(character)
	if cell != Vector2i(-1, -1):
		_towerByCell.erase(cell)

	return true


func AddStatBonusToTower(
	cell: Vector2i,
	type: CharacterStats.Type,
	flatValue: int,
	ratioValue: int,
) -> bool:
	var tower: Unit = _towerByCell.get(cell)
	return tower != null and tower.AddStatBonus(type, flatValue, ratioValue)


func RemoveStatBonusFromTower(
	cell: Vector2i,
	type: CharacterStats.Type,
	flatValue: int,
	ratioValue: int,
) -> bool:
	var tower: Unit = _towerByCell.get(cell)
	return tower != null and tower.RemoveStatBonus(type, flatValue, ratioValue)


func AddStatBonusToAllTowers(type: CharacterStats.Type, flatValue: int, ratioValue: int) -> bool:
	for tower: Unit in _towerByCell.values():
		if not tower.AddStatBonus(type, flatValue, ratioValue):
			return false

	return true


func RemoveStatBonusFromAllTowers(
	type: CharacterStats.Type,
	flatValue: int,
	ratioValue: int,
) -> bool:
	for tower: Unit in _towerByCell.values():
		if not tower.RemoveStatBonus(type, flatValue, ratioValue):
			return false

	return true


func ClearStatBonuses() -> void:
	for tower: Unit in _towerByCell.values():
		tower.ClearStatBonuses()


func ResetVitals() -> void:
	for tower: Unit in _towerByCell.values():
		tower.ResetVitals()


func HasPreparedTower(cell: Vector2i) -> bool:
	return _preparedPopulationByCell.has(cell)


func GetTowerByCell(cell: Vector2i) -> Unit:
	return _towerByCell.get(cell)


func GetRecruitedPopulation() -> int:
	return _totalRecruitedPopulation


func GetSurvivingPopulation() -> int:
	var population: int = 0

	for tower: Unit in _towerByCell.values():
		var towerComponent: TowerComponent = tower.GetTowerComponent()
		if towerComponent != null:
			population += towerComponent.GetSurvivingPopulation()

	return population


func GetDeadPopulation() -> int:
	return _totalRecruitedPopulation - GetSurvivingPopulation()
