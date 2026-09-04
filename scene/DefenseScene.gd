extends Node2D

const DEPLOYMENT_CELL_SIZE: int = 128

# TODO: 병과 / 징집률 선택 UI 구현 후 제거
const TEMP_CHARACTER_KEY: int = 1000
const TEMP_RECRUIT_RATIO: int = 100

signal DefenseFinished(result: DefenseResult)

@export var navigationData: NavigationData

var _navigationService: NavigationService
var _deploymentGrid: DefenseDeploymentGrid
var _deploymentUnitsByCell: Dictionary = { }

var _defenseManager: DefenseManager
var _startData: DefenseStartData


func Initialize(startData: DefenseStartData) -> void:
	_startData = startData


func _ready() -> void:
	_navigationService = NavigationService.new()
	_navigationService.navigationData = navigationData
	_navigationService.Ready()
	if not _navigationService.IsReady():
		push_error("DefenseScene: NavigationService 초기화에 실패했습니다.")
		return

	_InitializeDeploymentGrid()

	if _startData == null:
		_startData = DefenseStartData.new()
		_startData.cycle = 1
		_startData.population = 100

	_defenseManager = DefenseManager.new(_startData, $Pools, _navigationService)

	_defenseManager.DefenseFinished.connect(_OnDefenseFinished)


func _process(_delta: float) -> void:
	if _defenseManager == null:
		return

	_defenseManager.Update()


func _InitializeDeploymentGrid() -> void:
	var worldRect: Rect2 = navigationData.GetWorldRect()
	var deploymentGridSize: Vector2i = Vector2i(
		floori(worldRect.size.x / DEPLOYMENT_CELL_SIZE),
		floori(worldRect.size.y / DEPLOYMENT_CELL_SIZE),
	)

	_deploymentGrid = DefenseDeploymentGrid.new(
		DEPLOYMENT_CELL_SIZE,
		worldRect.position,
		deploymentGridSize,
	)

	$DeploymentGridView.Initialize(_deploymentGrid)
	$DeploymentGridView.CellClicked.connect(_OnDeploymentCellClicked)
	$DeploymentGridView.CellRightClicked.connect(_OnDeploymentCellRightClicked)

	$CanvasLayer/ConfirmButton.pressed.connect(_OnConfirmDeploymentPressed)


func _OnDeploymentCellClicked(cell: Vector2i) -> void:
	var characterKey: int = TEMP_CHARACTER_KEY
	var recruitRatio: int = TEMP_RECRUIT_RATIO

	var success: bool = _defenseManager.AddDeployment(cell, characterKey, recruitRatio)
	if not success:
		return

	var spawnPosition: Vector2 = _deploymentGrid.CellToWorld(cell)
	var unit: Unit = _defenseManager.SpawnDeploymentUnit(characterKey, spawnPosition)
	if unit == null:
		_defenseManager.RemoveDeployment(cell)
		return

	_deploymentUnitsByCell[cell] = unit

	$DeploymentGridView.SetDeployment(cell, characterKey)


func _OnDeploymentCellRightClicked(cell: Vector2i) -> void:
	var success: bool = _defenseManager.RemoveDeployment(cell)
	if not success:
		return

	if _deploymentUnitsByCell.has(cell):
		var unit: Unit = _deploymentUnitsByCell[cell]

		_defenseManager.ReturnUnit(unit)
		_deploymentUnitsByCell.erase(cell)

	$DeploymentGridView.RemoveDeployment(cell)


func _OnConfirmDeploymentPressed() -> void:
	var success: bool = _defenseManager.ConfirmDeployment()
	if not success:
		return

	$DeploymentGridView.visible = false
	$DeploymentGridView.process_mode = Node.PROCESS_MODE_DISABLED

	$CanvasLayer/ConfirmButton.visible = false


func _OnDefenseFinished(result: DefenseResult) -> void:
	print("Defense Finished")
	print("Victory: ", result.isVictory)
	print("Dead Population: ", result.deadPopulation)
	DefenseFinished.emit(result)
