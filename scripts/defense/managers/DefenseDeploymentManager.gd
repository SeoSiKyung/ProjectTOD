class_name DefenseDeploymentManager
extends RefCounted

const MAX_RECRUIT_RATIO: int = 300 # 30%를 의미


class DefenseDeployment:
	var unitType: int # 아직 유닛 타입 없음
	var recruitRatio: int


	func _init(pUnitType: int, pRecruitRatio: int):
		unitType = pUnitType
		recruitRatio = pRecruitRatio


var _deployments: Dictionary = { }


func GetDeploymentCells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell: Vector2i in _deployments:
		cells.append(cell)

	return cells


func GetDeployment(cell: Vector2i) -> DefenseDeployment:
	return _deployments.get(cell)


func AddDeployment(cell: Vector2i, unitType: int, recruitRatio: int) -> bool:
	if _deployments.has(cell) or not _CanAddDeployment(recruitRatio):
		return false

	var deployment: DefenseDeployment = DefenseDeployment.new(unitType, recruitRatio)
	_deployments[cell] = deployment

	return true


func RemoveDeployment(cell: Vector2i) -> bool:
	if not _deployments.has(cell):
		return false

	_deployments.erase(cell)

	return true


func UpdateDeployment(cell: Vector2i, unitType: int, recruitRatio: int) -> bool:
	var deployment: DefenseDeployment = _deployments.get(cell)
	if deployment == null or recruitRatio <= 0:
		return false

	var updatedTotalRatio: int = (GetTotalRecruitRatio() - deployment.recruitRatio + recruitRatio)
	if updatedTotalRatio > MAX_RECRUIT_RATIO:
		return false

	deployment.unitType = unitType
	deployment.recruitRatio = recruitRatio

	return true


func GetTotalRecruitRatio() -> int:
	var total: int = 0
	for deployment: DefenseDeployment in _deployments.values():
		total += deployment.recruitRatio

	return total


func _CanAddDeployment(recruitRatio: int) -> bool:
	if recruitRatio <= 0:
		return false

	return GetTotalRecruitRatio() + recruitRatio <= MAX_RECRUIT_RATIO
