class_name DefenseDeploymentPhaseHandler
extends RefCounted

var _defenseSceneManager: DefenseSceneManager
var _startData: DefenseStartData

var _deploymentGrid: DefenseDeploymentGrid
var _deploymentGridView: DefenseDeploymentGridView
var _deploymentInfoView: DefenseDeploymentInfoView
var _deploymentView: DefenseDeploymentView

var _cpCell: Vector2i
var _unitHalfSize: int


func _init(
	defenseSceneManager: DefenseSceneManager,
	startData: DefenseStartData,
	deploymentGrid: DefenseDeploymentGrid,
	deploymentGridView: DefenseDeploymentGridView,
	deploymentInfoView: DefenseDeploymentInfoView,
	deploymentView: DefenseDeploymentView,
	cpCell: Vector2i,
	unitHalfSize: int,
) -> void:
	_defenseSceneManager = defenseSceneManager
	_startData = startData

	_deploymentGrid = deploymentGrid
	_deploymentGridView = deploymentGridView
	_deploymentInfoView = deploymentInfoView
	_deploymentView = deploymentView

	_cpCell = cpCell
	_unitHalfSize = unitHalfSize


func Enter() -> bool:
	push_error("DefenseDeploymentPhaseHandler.Enter()가 구현되지 않았습니다.")
	return false


func Confirm() -> bool:
	push_error("DefenseDeploymentPhaseHandler.Confirm()이 구현되지 않았습니다.")
	return false


func Place(cell: Vector2i) -> bool:
	push_error("DefenseDeploymentPhaseHandler.Place()가 구현되지 않았습니다. cell: " + str(cell))
	return false


func Remove(cell: Vector2i) -> void:
	push_error("DefenseDeploymentPhaseHandler.Remove()가 구현되지 않았습니다. cell: " + str(cell))


func CanInteract(cell: Vector2i) -> bool:
	push_error("DefenseDeploymentPhaseHandler.CanInteract()가 구현되지 않았습니다. cell: " + str(cell))
	return false


func CanPlace(cell: Vector2i) -> bool:
	push_error("DefenseDeploymentPhaseHandler.CanPlace()가 구현되지 않았습니다. cell: " + str(cell))
	return false


func OnCharacterSelected(_characterKey: int) -> void:
	pass


func OnCharacterDragStarted(characterKey: int) -> void:
	OnCharacterSelected(characterKey)


func OnRecruitRatioChanged(_value: float) -> void:
	pass


func RefreshPlacementPreview() -> void:
	pass


func OnMercenarySelected(_mercenaryKey: int) -> void:
	pass


func OnMercenaryDragStarted(mercenaryKey: int) -> void:
	OnMercenarySelected(mercenaryKey)


func _CanPlaceStaticAtCell(cell: Vector2i) -> bool:
	var position: Vector2 = _deploymentGrid.CellToWorldCenter(cell)

	return _defenseSceneManager.CanPlaceStatic(position, _unitHalfSize)
