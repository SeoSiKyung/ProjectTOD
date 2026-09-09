class_name DefenseUnitGroupManager
extends DefenseCharacterManager


class DefensePopulationSummary:
	var recruitedPopulation: int = 0
	var survivingPopulation: int = 0
	var deadPopulation: int = 0


var _unitGroupStatusByCell: Dictionary = { }


func Initialize(deploymentManager: DefenseDeploymentManager, totalPopulation: int) -> bool:
	Clear()

	var cells: Array[Vector2i] = deploymentManager.GetDeploymentCells()
	for cell: Vector2i in cells:
		var deployment := deploymentManager.GetDeploymentByCell(cell)
		if deployment == null:
			Clear()
			return false

		var status: DefenseUnitGroupStatus = _CreateUnitGroupStatus(deployment, totalPopulation)
		if status == null:
			Clear()
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


func GetPopulationSummary() -> DefensePopulationSummary:
	var summary: DefensePopulationSummary = DefensePopulationSummary.new()
	for cell: Vector2i in _unitGroupStatusByCell:
		var status: DefenseUnitGroupStatus = _unitGroupStatusByCell[cell]
		summary.recruitedPopulation += status.recruitedPopulation
		summary.survivingPopulation += status.survivingPopulation
		summary.deadPopulation += status.GetDeadPopulation()

	return summary


func _CreateUnitGroupStatus(
	deployment: DefenseDeploymentManager.DefenseDeployment,
	totalPopulation: int,
) -> DefenseUnitGroupStatus:
	var recruitedPopulation: int = Math.ApplyRatio(totalPopulation, deployment.recruitRatio)
	if recruitedPopulation <= 0:
		return null

	var characterData: CharacterData = GameDataManager.GetCharacterData(deployment.characterKey)
	if characterData == null:
		push_error(
			"DefenseUnitGroupManager: 존재하지 않는 characterKey입니다. key: " + str(deployment.characterKey)
		)
		return null

	if characterData.characterType != CharacterData.CharacterType.UNIT:
		push_error(
			"DefenseUnitGroupManager: UNIT 타입이 아닌 캐릭터가 배치되었습니다. key: "
			+ str(deployment.characterKey)
		)
		return null

	return DefenseUnitGroupStatus.new(recruitedPopulation, characterData)
