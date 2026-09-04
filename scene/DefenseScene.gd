extends Node2D

const DEPLOYMENT_CELL_SIZE: int = 128

# TODO: 병과 / 징집률 선택 UI 구현 후 제거
const TEMP_CHARACTER_KEY: int = 1000
const TEMP_RECRUIT_RATIO: int = 100

signal DefenseFinished(result: DefenseResult)

@export var navigationData: NavigationData

@onready var _pools: Node = $Pools
@onready var _deploymentGridView: DefenseDeploymentGridView = $DeploymentGridView
@onready var _confirmButton: Button = $CanvasLayer/ConfirmButton

var _navigationService: NavigationService
var _deploymentGrid: DefenseDeploymentGrid

var _defenseManager: DefenseManager
var _startData: DefenseStartData


func Initialize(startData: DefenseStartData) -> void:
	_startData = startData


func _ready() -> void:
	if not _InitializeNavigation():
		return

	_InitializeDeploymentGrid()
	_InitializeStartData()
	_InitializeDefenseManager()


func _process(_delta: float) -> void:
	if _defenseManager == null:
		return

	_defenseManager.Update()


func _InitializeNavigation() -> bool:
	_navigationService = NavigationService.new()
	_navigationService.navigationData = navigationData
	_navigationService.Ready()

	if not _navigationService.IsReady():
		push_error("DefenseScene: NavigationService 초기화에 실패했습니다.")
		return false

	return true


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

	_deploymentGridView.Initialize(_deploymentGrid)
	_deploymentGridView.CellClicked.connect(_OnDeploymentCellClicked)
	_deploymentGridView.CellRightClicked.connect(_OnDeploymentCellRightClicked)

	_confirmButton.pressed.connect(_OnConfirmDeploymentPressed)


func _InitializeStartData() -> void:
	if _startData != null:
		return

	_startData = DefenseStartData.new()
	_startData.cycle = 1
	_startData.population = 100


func _InitializeDefenseManager() -> void:
	_defenseManager = DefenseManager.new(_startData, _pools, _navigationService)

	_defenseManager.DefenseFinished.connect(_OnDefenseFinished)


func _OnDeploymentCellClicked(cell: Vector2i) -> void:
	var characterKey: int = TEMP_CHARACTER_KEY
	var recruitRatio: int = TEMP_RECRUIT_RATIO
	var spawnPosition: Vector2 = _deploymentGrid.CellToWorldCenter(cell)

	if not _defenseManager.AddDeployment(cell, characterKey, recruitRatio, spawnPosition):
		return

	_deploymentGridView.SetDeployment(cell)


func _OnDeploymentCellRightClicked(cell: Vector2i) -> void:
	if not _defenseManager.RemoveDeployment(cell):
		return

	_deploymentGridView.RemoveDeployment(cell)


func _OnConfirmDeploymentPressed() -> void:
	if not _defenseManager.ConfirmDeployment():
		return

	_deploymentGridView.visible = false
	_deploymentGridView.process_mode = Node.PROCESS_MODE_DISABLED

	_confirmButton.visible = false


func _OnDefenseFinished(result: DefenseResult) -> void:
	print("Defense Finished")
	print("Victory: ", result.isVictory)
	print("Dead Population: ", result.deadPopulation)

	DefenseFinished.emit(result)
