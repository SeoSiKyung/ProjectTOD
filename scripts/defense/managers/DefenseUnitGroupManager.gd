class_name DefenseUnitGroupManager
extends DefenseCharacterManager

var _unitGroupStateByCell: Dictionary[Vector2i, DefenseUnitGroupState] = { }
var _unitGroupStateByCharacter: Dictionary[Unit, DefenseUnitGroupState] = { }


func AddUnitGroup(
	cell: Vector2i,
	characterData: CharacterData,
	recruitRatio: int,
	totalPopulation: int,
) -> bool:
	if _unitGroupStateByCell.has(cell) or characterData == null:
		return false

	var state: DefenseUnitGroupState = _CreateUnitGroupState(
		characterData,
		recruitRatio,
		totalPopulation,
	)
	if state == null:
		return false

	_unitGroupStateByCell[cell] = state
	return true


func Clear() -> void:
	for character: Unit in _unitGroupStateByCharacter:
		_DisconnectMaxHpStatChanged(character)

	super.Clear()
	_unitGroupStateByCell.clear()
	_unitGroupStateByCharacter.clear()


func BindUnit(cell: Vector2i, unit: Unit) -> bool:
	var state: DefenseUnitGroupState = _unitGroupStateByCell.get(cell)
	if state == null or unit == null:
		return false

	if unit.characterType != CharacterData.CharacterType.UNIT:
		return false

	if not RegisterCharacter(unit):
		return false

	if not state.BindUnit(unit):
		super.UnregisterCharacter(unit)
		return false

	_unitGroupStateByCharacter[unit] = state
	unit.MaxHpStatChanged.connect(_OnMaxHpStatChanged.bind(unit))
	return true


func UnregisterCharacter(character: Unit) -> bool:
	if not HasCharacter(character):
		return false

	_DisconnectMaxHpStatChanged(character)

	if not super.UnregisterCharacter(character):
		return false

	_unitGroupStateByCharacter.erase(character)
	return true


func TakeDamage(character: Unit, damage: int) -> bool:
	var state: DefenseUnitGroupState = _unitGroupStateByCharacter.get(character)
	if state == null or character == null or character.IsDead():
		return false

	character.TakeDamage(damage)
	state.UpdateAfterDamage(character)

	if character.IsDead():
		CharacterDied.emit(character)

	return true


func GetAttackMultiplier(character: Unit) -> int:
	var state: DefenseUnitGroupState = _unitGroupStateByCharacter.get(character)
	if state == null:
		return 1

	return maxi(state.survivingPopulation, 0)


func HasAliveUnitGroup() -> bool:
	for cell: Vector2i in _unitGroupStateByCell:
		var state: DefenseUnitGroupState = _unitGroupStateByCell[cell]
		if not state.IsDead():
			return true

	return false


func GetUnitGroupStateByCell(cell: Vector2i) -> DefenseUnitGroupState:
	return _unitGroupStateByCell.get(cell)


func GetRecruitedPopulation() -> int:
	var population: int = 0
	for cell: Vector2i in _unitGroupStateByCell:
		var state: DefenseUnitGroupState = _unitGroupStateByCell[cell]
		population += state.recruitedPopulation

	return population


func GetSurvivingPopulation() -> int:
	var population: int = 0
	for cell: Vector2i in _unitGroupStateByCell:
		var state: DefenseUnitGroupState = _unitGroupStateByCell[cell]
		population += state.survivingPopulation

	return population


func GetDeadPopulation() -> int:
	var population: int = 0
	for cell: Vector2i in _unitGroupStateByCell:
		var state: DefenseUnitGroupState = _unitGroupStateByCell[cell]
		population += state.GetDeadPopulation()

	return population


func _CreateUnitGroupState(
	characterData: CharacterData,
	recruitRatio: int,
	totalPopulation: int,
) -> DefenseUnitGroupState:
	var recruitedPopulation: int = Math.ApplyRatio(totalPopulation, recruitRatio)
	if recruitedPopulation <= 0:
		return null

	if characterData.characterType != CharacterData.CharacterType.UNIT:
		push_error(
			"DefenseUnitGroupManager: UNIT 타입이 아닌 캐릭터가 배치되었습니다. key: "
			+ str(characterData.characterKey)
		)
		return null

	return DefenseUnitGroupState.new(recruitedPopulation)


func _OnMaxHpStatChanged(_maxHpStat: int, character: Unit) -> void:
	var state: DefenseUnitGroupState = _unitGroupStateByCharacter.get(character)
	if state == null:
		return

	var wasDead: bool = state.IsDead()
	state.UpdateAfterDamage(character)

	if not wasDead and character.IsDead():
		CharacterDied.emit(character)


func _DisconnectMaxHpStatChanged(character: Unit) -> void:
	if character == null:
		return

	var callback: Callable = _OnMaxHpStatChanged.bind(character)
	if character.MaxHpStatChanged.is_connected(callback):
		character.MaxHpStatChanged.disconnect(callback)
