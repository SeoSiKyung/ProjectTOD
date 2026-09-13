extends Node2D

const DEPLOYMENT_CELL_SIZE: int = 128
const DEPLOYMENT_UNIT_HALF_SIZE: int = 16
const INVALID_DEPLOYMENT_CELL: Vector2i = Vector2i(-1, -1)

signal DefenseFinished(result: DefenseResult)

@export var navigationData: NavigationData

@onready var _movementSimulator: MovementSimulator = $MovementSimulator
@onready var _deploymentGridView: DefenseDeploymentGridView = $DeploymentGridView
@onready var _pools: Node = $Pools

@onready var _deploymentPanel: PanelContainer = $CanvasLayer/DeploymentPanel
@onready var _characterButtonContainer: HBoxContainer = (
	$CanvasLayer/DeploymentPanel/VBoxContainer/CharacterButtonContainer
)
@onready var _recruitRatioSpinBox: SpinBox = (
	$CanvasLayer/DeploymentPanel/VBoxContainer/RecruitRatioContainer/RecruitRatioSpinBox
)
@onready var _deploymentApplyButton: Button = (
	$CanvasLayer/DeploymentPanel/VBoxContainer/ApplyButton
)

@onready var _recruitRatioLabel: Label = $CanvasLayer/RecruitRatioLabel
@onready var _confirmButton: Button = $CanvasLayer/ConfirmButton

var _navigationService: NavigationService
var _deploymentGrid: DefenseDeploymentGrid

var _defenseManager: DefenseManager
var _startData: DefenseStartData

var _characterButtonGroup: ButtonGroup = ButtonGroup.new()
var _characterButtonByKey: Dictionary = { }

var _selectedDeploymentCell: Vector2i = INVALID_DEPLOYMENT_CELL
var _selectedCharacterKey: int = -1
var _selectedRecruitRatio: int = 0


func _ready() -> void:
	if not _InitializeNavigation():
		return

	_InitializeDeploymentGrid()
	_InitializeStartData()
	_InitializeDefenseManager()

	if not _InitializeDeploymentSelection():
		return


func _process(_delta: float) -> void:
	if _defenseManager == null:
		return

	_defenseManager.Update()


func Initialize(startData: DefenseStartData) -> void:
	_startData = startData

#region Event

func _OnDeploymentCellClicked(cell: Vector2i) -> void:
	_selectedDeploymentCell = cell

	var deployment: DefenseDeploymentManager.DefenseDeployment = (
		_defenseManager.GetDeploymentByCell(cell)
	)
	if deployment == null:
		_selectedRecruitRatio = 0
	else:
		_selectedCharacterKey = deployment.characterKey
		_selectedRecruitRatio = deployment.recruitRatio

	_UpdateDeploymentPanel()
	_ShowDeploymentPanel(cell)


func _OnDeploymentCellRightClicked(cell: Vector2i) -> void:
	if not _defenseManager.RemoveDeployment(cell):
		return

	_deploymentGridView.RemoveDeployment(cell)

	if _selectedDeploymentCell == cell:
		_selectedRecruitRatio = 0
		_UpdateDeploymentPanel()

	_UpdateRecruitRatioLabel()


func _OnCharacterButtonPressed(characterKey: int) -> void:
	_selectedCharacterKey = characterKey


func _OnRecruitRatioChanged(value: float) -> void:
	_selectedRecruitRatio = Math.PercentToRatio(int(value))


func _OnDeploymentApplyPressed() -> void:
	if not _ApplyDeploymentSelection():
		return

	_CloseDeploymentPanel()


func _OnConfirmDeploymentPressed() -> void:
	if not _defenseManager.ConfirmDeployment():
		return

	_CloseDeploymentPanel()
	_deploymentGridView.visible = false
	_deploymentGridView.process_mode = Node.PROCESS_MODE_DISABLED
	_confirmButton.visible = false


func _OnDefenseFinished(result: DefenseResult) -> void:
	print("Defense Finished")
	print("Victory: ", result.isVictory)
	print("Recruited Population: ", result.recruitedPopulation)
	print("Surviving Population: ", result.survivingPopulation)
	print("Dead Population: ", result.deadPopulation)

	DefenseFinished.emit(result)

#endregion

#region Initialize

func _InitializeNavigation() -> bool:
	_navigationService = NavigationService.new()
	_navigationService.navigationData = navigationData
	_navigationService.Ready()

	if not _navigationService.IsReady():
		push_error("DefenseScene: NavigationService 초기화에 실패했습니다.")
		return false

	_movementSimulator.navigationService = _navigationService

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

	_deploymentGridView.Initialize(_deploymentGrid, Callable(self, "_CanInteractDeploymentCell"))
	_deploymentGridView.CellClicked.connect(_OnDeploymentCellClicked)
	_deploymentGridView.CellRightClicked.connect(_OnDeploymentCellRightClicked)

	_confirmButton.pressed.connect(_OnConfirmDeploymentPressed)


func _InitializeStartData() -> void:
	if _startData != null:
		return

	_startData = DefenseStartData.new()
	_startData.cycle = 1
	_startData.population = 100

	_startData.commandPostMaxHp = 1000


func _InitializeDefenseManager() -> void:
	_defenseManager = DefenseManager.new(_startData, _pools, _navigationService, _movementSimulator)

	_defenseManager.DefenseFinished.connect(_OnDefenseFinished)


func _InitializeDeploymentSelection() -> bool:
	var unitDataList: Array[CharacterData] = GameDataManager.GetCharacterDataByType(
		CharacterData.CharacterType.UNIT
	)
	if unitDataList.is_empty():
		push_error("DefenseScene: 배치 가능한 UNIT 데이터가 없습니다.")
		return false

	_characterButtonGroup.allow_unpress = false

	for characterData: CharacterData in unitDataList:
		var characterButton: Button = Button.new()
		characterButton.text = characterData.characterName
		characterButton.toggle_mode = true
		characterButton.button_group = _characterButtonGroup
		characterButton.pressed.connect(_OnCharacterButtonPressed.bind(characterData.characterKey))

		_characterButtonContainer.add_child(characterButton)
		_characterButtonByKey[characterData.characterKey] = characterButton

	_selectedCharacterKey = unitDataList[0].characterKey
	_selectedRecruitRatio = 0

	var defaultButton: Button = _characterButtonByKey[_selectedCharacterKey]
	defaultButton.button_pressed = true

	_recruitRatioSpinBox.value_changed.connect(_OnRecruitRatioChanged)

	_deploymentApplyButton.pressed.connect(_OnDeploymentApplyPressed)

	_deploymentPanel.visible = false
	_UpdateRecruitRatioLabel()

	return true

#endregion

#region Deployment UI

func _ApplyDeploymentSelection() -> bool:
	if _selectedDeploymentCell == INVALID_DEPLOYMENT_CELL or _selectedCharacterKey < 0:
		return false

	var deployment: DefenseDeploymentManager.DefenseDeployment = (
		_defenseManager.GetDeploymentByCell(_selectedDeploymentCell)
	)

	if _selectedRecruitRatio == 0:
		if deployment == null:
			return true

		if not _defenseManager.RemoveDeployment(_selectedDeploymentCell):
			_ReloadDeploymentSelection()
			return false

		_deploymentGridView.RemoveDeployment(_selectedDeploymentCell)
		_UpdateRecruitRatioLabel()

		return true

	if deployment == null:
		var spawnPosition: Vector2 = _deploymentGrid.CellToWorldCenter(_selectedDeploymentCell)

		if not _defenseManager.AddDeployment(
			_selectedDeploymentCell,
			_selectedCharacterKey,
			_selectedRecruitRatio,
			spawnPosition,
		):
			_ReloadDeploymentSelection()
			return false

		_deploymentGridView.SetDeployment(_selectedDeploymentCell)
	else:
		if not _defenseManager.UpdateDeployment(
			_selectedDeploymentCell,
			_selectedCharacterKey,
			_selectedRecruitRatio,
		):
			_ReloadDeploymentSelection()
			return false

	_UpdateRecruitRatioLabel()

	return true


func _ReloadDeploymentSelection() -> void:
	var deployment: DefenseDeploymentManager.DefenseDeployment = (
		_defenseManager.GetDeploymentByCell(_selectedDeploymentCell)
	)
	if deployment == null:
		_selectedRecruitRatio = 0
	else:
		_selectedCharacterKey = deployment.characterKey
		_selectedRecruitRatio = deployment.recruitRatio

	_UpdateDeploymentPanel()


func _UpdateDeploymentPanel() -> void:
	var characterButton: Button = _characterButtonByKey.get(_selectedCharacterKey)
	if characterButton != null:
		characterButton.set_pressed_no_signal(true)

	var recruitPercent: int = Math.RatioToPercent(_selectedRecruitRatio)
	_recruitRatioSpinBox.set_value_no_signal(recruitPercent)


func _UpdateRecruitRatioLabel() -> void:
	var totalRecruitRatio: int = _defenseManager.GetTotalRecruitRatio()
	var maxRecruitRatio: int = _defenseManager.GetMaxRecruitRatio()

	var totalPercent: int = Math.RatioToPercent(totalRecruitRatio)
	var maxPercent: int = Math.RatioToPercent(maxRecruitRatio)

	_recruitRatioLabel.text = "%d%% / %d%%" % [totalPercent, maxPercent]
	_confirmButton.disabled = totalRecruitRatio <= 0


func _ShowDeploymentPanel(cell: Vector2i) -> void:
	_deploymentGridView.LockHoverCell(cell)

	_deploymentPanel.visible = true
	_PositionDeploymentPanel(cell)


func _PositionDeploymentPanel(cell: Vector2i) -> void:
	const PANEL_MARGIN: float = 8.0

	var cellWorldTopLeft: Vector2 = (
		_deploymentGrid.worldOrigin + Vector2(cell) * _deploymentGrid.cellSize
	)
	var cellWorldBottomRight: Vector2 = (cellWorldTopLeft + Vector2.ONE * _deploymentGrid.cellSize)

	var canvasTransform: Transform2D = _deploymentGridView.get_canvas_transform()

	var cellScreenTopLeft: Vector2 = canvasTransform * cellWorldTopLeft
	var cellScreenBottomRight: Vector2 = canvasTransform * cellWorldBottomRight

	var panelSize: Vector2 = _deploymentPanel.size
	var viewportSize: Vector2 = get_viewport_rect().size

	var panelPosition: Vector2 = Vector2(
		cellScreenBottomRight.x + PANEL_MARGIN,
		cellScreenBottomRight.y + PANEL_MARGIN,
	)

	if panelPosition.x + panelSize.x > viewportSize.x:
		panelPosition.x = cellScreenTopLeft.x - panelSize.x - PANEL_MARGIN

	if panelPosition.y + panelSize.y > viewportSize.y:
		panelPosition.y = cellScreenTopLeft.y - panelSize.y - PANEL_MARGIN

	panelPosition.x = clampf(
		panelPosition.x,
		PANEL_MARGIN,
		viewportSize.x - panelSize.x - PANEL_MARGIN,
	)
	panelPosition.y = clampf(
		panelPosition.y,
		PANEL_MARGIN,
		viewportSize.y - panelSize.y - PANEL_MARGIN,
	)

	_deploymentPanel.position = panelPosition


func _CloseDeploymentPanel() -> void:
	_deploymentPanel.visible = false
	_deploymentGridView.UnlockHoverCell()

	_selectedDeploymentCell = INVALID_DEPLOYMENT_CELL


func _CanInteractDeploymentCell(cell: Vector2i) -> bool:
	var position: Vector2 = _deploymentGrid.CellToWorldCenter(cell)
	return _navigationService.CanPlaceStatic(position, DEPLOYMENT_UNIT_HALF_SIZE)

#endregion
