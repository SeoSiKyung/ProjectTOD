class_name DefenseTowerManager
extends DefenseCharacterManager

var _preparedPopulationByCell: Dictionary[Vector2i, int] = { }
var _towerByCell: Dictionary[Vector2i, Tower] = { }
var _cellByTower: Dictionary[Tower, Vector2i] = { }
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
	if not _preparedPopulationByCell.has(cell) or _towerByCell.has(cell):
		return false

	if not unit is Tower:
		push_error("DefenseTowerManager: Tower가 아닌 Unit입니다. cell: " + str(cell))
		return false

	var tower: Tower = unit as Tower
	if tower.characterType != CharacterData.CharacterType.UNIT:
		return false

	if not RegisterCharacter(tower):
		return false

	var recruitedPopulation: int = _preparedPopulationByCell[cell]
	if not tower.InitializePopulation(recruitedPopulation):
		super.UnregisterCharacter(tower)
		return false

	_towerByCell[cell] = tower
	_cellByTower[tower] = cell
	return true


func UnregisterCharacter(character: Unit) -> bool:
	if not character is Tower or not HasCharacter(character):
		return false

	var tower: Tower = character as Tower
	var cell: Vector2i = _cellByTower.get(tower, Vector2i(-1, -1))

	if not super.UnregisterCharacter(tower):
		return false

	_cellByTower.erase(tower)
	if cell != Vector2i(-1, -1):
		_towerByCell.erase(cell)

	return true


func TakeDamage(character: Unit, damage: int) -> bool:
	if not character is Tower or not HasCharacter(character) or character.IsDead():
		return false

	var tower: Tower = character as Tower
	tower.TakeDamage(damage)

	if tower.IsDead():
		CharacterDied.emit(tower)

	return true


func AddStatBonusToTower(
	cell: Vector2i,
	type: CharacterStats.Type,
	flatValue: int,
	ratioValue: int,
) -> bool:
	var tower: Tower = _towerByCell.get(cell)
	return tower != null and tower.AddStatBonus(type, flatValue, ratioValue)


func RemoveStatBonusFromTower(
	cell: Vector2i,
	type: CharacterStats.Type,
	flatValue: int,
	ratioValue: int,
) -> bool:
	var tower: Tower = _towerByCell.get(cell)
	return tower != null and tower.RemoveStatBonus(type, flatValue, ratioValue)


func AddStatBonusToAllTowers(type: CharacterStats.Type, flatValue: int, ratioValue: int) -> bool:
	for tower: Tower in _towerByCell.values():
		if not tower.AddStatBonus(type, flatValue, ratioValue):
			return false

	return true


func RemoveStatBonusFromAllTowers(
	type: CharacterStats.Type,
	flatValue: int,
	ratioValue: int,
) -> bool:
	for tower: Tower in _towerByCell.values():
		if not tower.RemoveStatBonus(type, flatValue, ratioValue):
			return false

	return true


func ClearStatBonuses() -> void:
	for tower: Tower in _towerByCell.values():
		tower.ClearStatBonuses()


func ResetVitals() -> void:
	for tower: Tower in _towerByCell.values():
		tower.ResetVitals()


func HasPreparedTower(cell: Vector2i) -> bool:
	return _preparedPopulationByCell.has(cell)


func GetTowerByCell(cell: Vector2i) -> Tower:
	return _towerByCell.get(cell)


func GetRecruitedPopulation() -> int:
	return _totalRecruitedPopulation


func GetSurvivingPopulation() -> int:
	var population: int = 0
	for tower: Tower in _towerByCell.values():
		population += tower.GetSurvivingPopulation()

	return population


func GetDeadPopulation() -> int:
	return _totalRecruitedPopulation - GetSurvivingPopulation()
