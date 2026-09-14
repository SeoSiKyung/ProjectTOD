class_name DefenseDeploymentManager
extends RefCounted

const MAX_RECRUIT_RATIO: int = 300 # 30%를 의미


class DefenseDeployment:
	var characterKey: int
	var recruitRatio: int


	func _init(pCharacterKey: int, pRecruitRatio: int) -> void:
		characterKey = pCharacterKey
		recruitRatio = pRecruitRatio


var _deployments: Dictionary = { }
var _totalRecruitRatio: int = 0


func GetDeploymentCells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell: Vector2i in _deployments:
		cells.append(cell)

	return cells


func GetDeploymentByCell(cell: Vector2i) -> DefenseDeployment:
	return _deployments.get(cell)


func GetTotalRecruitRatio() -> int:
	return _totalRecruitRatio


func GetMaxRecruitRatioForCell(cell: Vector2i) -> int:
	var deployment: DefenseDeployment = _deployments.get(cell)

	var previousRecruitRatio: int = 0
	if deployment != null:
		previousRecruitRatio = deployment.recruitRatio

	return MAX_RECRUIT_RATIO - (_totalRecruitRatio - previousRecruitRatio)


func CalculateTotalRecruitedPopulation(totalPopulation: int) -> int:
	var totalRecruitedPopulation: int = 0
	for cell: Vector2i in _deployments:
		var deployment: DefenseDeployment = _deployments[cell]
		totalRecruitedPopulation += Math.ApplyRatio(totalPopulation, deployment.recruitRatio)

	return totalRecruitedPopulation


func AddDeployment(cell: Vector2i, characterKey: int, recruitRatio: int) -> bool:
	if _deployments.has(cell):
		return false

	if not _CanChangeRecruitRatio(0, recruitRatio):
		return false

	_deployments[cell] = DefenseDeployment.new(characterKey, recruitRatio)
	_totalRecruitRatio += recruitRatio

	return true


func RemoveDeployment(cell: Vector2i) -> bool:
	var deployment: DefenseDeployment = _deployments.get(cell)
	if deployment == null:
		return false

	_totalRecruitRatio -= deployment.recruitRatio
	_deployments.erase(cell)

	return true


func UpdateDeployment(cell: Vector2i, characterKey: int, recruitRatio: int) -> bool:
	var deployment: DefenseDeployment = _deployments.get(cell)
	if deployment == null:
		return false

	var previousRecruitRatio: int = deployment.recruitRatio
	if not _CanChangeRecruitRatio(previousRecruitRatio, recruitRatio):
		return false

	_totalRecruitRatio += recruitRatio - previousRecruitRatio
	deployment.characterKey = characterKey
	deployment.recruitRatio = recruitRatio

	return true


func _CanChangeRecruitRatio(previousRatio: int, newRatio: int) -> bool:
	if newRatio <= 0:
		return false

	var updatedTotalRatio: int = _totalRecruitRatio - previousRatio + newRatio
	return updatedTotalRatio <= MAX_RECRUIT_RATIO
