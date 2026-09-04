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


func GetDeploymentCells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell: Vector2i in _deployments:
		cells.append(cell)

	return cells


func GetDeployment(cell: Vector2i) -> DefenseDeployment:
	return _deployments.get(cell)


func AddDeployment(cell: Vector2i, characterKey: int, recruitRatio: int) -> bool:
	if _deployments.has(cell):
		return false

	if not _CanChangeRecruitRatio(0, recruitRatio):
		return false

	_deployments[cell] = DefenseDeployment.new(characterKey, recruitRatio)

	return true


func RemoveDeployment(cell: Vector2i) -> bool:
	if not _deployments.has(cell):
		return false

	_deployments.erase(cell)

	return true


func UpdateDeployment(cell: Vector2i, characterKey: int, recruitRatio: int) -> bool:
	var deployment: DefenseDeployment = _deployments.get(cell)
	if deployment == null:
		return false

	if not _CanChangeRecruitRatio(deployment.recruitRatio, recruitRatio):
		return false

	deployment.characterKey = characterKey
	deployment.recruitRatio = recruitRatio

	return true


func _CanChangeRecruitRatio(previousRatio: int, newRatio: int) -> bool:
	if newRatio <= 0:
		return false

	var updatedTotalRatio: int = _GetTotalRecruitRatio() - previousRatio + newRatio
	return updatedTotalRatio <= MAX_RECRUIT_RATIO


func _GetTotalRecruitRatio() -> int:
	var totalRecruitRatio: int = 0
	for cell: Vector2i in _deployments:
		var deployment: DefenseDeployment = _deployments[cell]
		totalRecruitRatio += deployment.recruitRatio

	return totalRecruitRatio
