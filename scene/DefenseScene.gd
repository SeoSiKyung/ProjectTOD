extends Node2D

const DEPLOYMENT_CELL_SIZE: int = 128
const DEPLOYMENT_UNIT_HALF_SIZE: int = 16
const INVALID_DEPLOYMENT_CELL: Vector2i = Vector2i(-1, -1)

signal DefenseFinished(result: DefenseResult)

@export var _navigationData: NavigationData

@export_group("UI")
@export var _deploymentUI: Control
@export var _battleHud: PanelContainer
@export var _resultUI: PanelContainer

@onready var _movementSimulator: MovementSimulator = $MovementSimulator
@onready var _deploymentGridView: DefenseDeploymentGridView = $DeploymentGridView
@onready var _pools: Node = $Pools

#region Deployment

@onready var _deploymentPanel: PanelContainer = _deploymentUI.get_node("DeploymentPanel")
@onready var _recruitContainer: VBoxContainer = _deploymentPanel.get_node("RecruitContainer")

@onready var _characterButtonContainer: HBoxContainer = _recruitContainer.get_node(
	"CharacterButtonContainer"
)
@onready var _recruitRatioSpinBox: SpinBox = _recruitContainer.get_node(
	"RecruitRatio/RecruitRatioSpinBox"
)
@onready var _recruitPopulationLabel: Label = _recruitContainer.get_node("RecruitPopulationLabel")
@onready var _deploymentApplyButton: Button = _recruitContainer.get_node("ApplyButton")

@onready var _recruitRatioLabel: Label = _deploymentUI.get_node("RecruitRatioLabel")
@onready var _confirmButton: Button = _deploymentUI.get_node("ConfirmButton")

#endregion

#region Battle

@onready var _battleHudContainer: VBoxContainer = _battleHud.get_node("Margin/BattleHudContainer")

@onready var _elapsedTime: Label = _battleHudContainer.get_node("ElapsedTime")

@onready var _cp: VBoxContainer = _battleHudContainer.get_node("CP")

@onready var _cpHp: VBoxContainer = _cp.get_node("Hp")
@onready var _cpHpLabel: Label = _cpHp.get_node("HpLabel")
@onready var _cpHpBar: ProgressBar = _cpHp.get_node("HpBar")

@onready var _cpMp: VBoxContainer = _cp.get_node("Mp")
@onready var _cpMpLabel: Label = _cpMp.get_node("MpLabel")
@onready var _cpMpBar: ProgressBar = _cpMp.get_node("MpBar")

@onready var _population: VBoxContainer = _battleHudContainer.get_node("Population")
@onready var _recruitedPopulation: Label = _population.get_node("RecruitedPopulation")
@onready var _survivingPopulation: Label = _population.get_node("SurvivingPopulation")
@onready var _deadPopulation: Label = _population.get_node("DeadPopulation")

@onready var _pauseButton: Button = _battleHudContainer.get_node("PauseButton")

#endregion

#region Result

@onready var _resultContainer: VBoxContainer = _resultUI.get_node("Margin/ResultContainer")

@onready var _result: Label = _resultContainer.get_node("Result")
@onready var _resultElapsedTime: Label = _resultContainer.get_node("ElapsedTime")
@onready var _resultCPStatus: Label = _resultContainer.get_node("CPStatus")
@onready var _resultRecruitedPopulation: Label = _resultContainer.get_node("RecruitedPopulation")
@onready var _resultSurvivingPopulation: Label = _resultContainer.get_node("SurvivingPopulation")
@onready var _resultDeadPopulation: Label = _resultContainer.get_node("DeadPopulation")
@onready var _resultConfirmButton: Button = _resultContainer.get_node("ConfirmButton")

#endregion

var _navigationService: NavigationService
var _deploymentGrid: DefenseDeploymentGrid

var _defenseManager: DefenseManager
var _startData: DefenseStartData

var _characterButtonGroup: ButtonGroup = ButtonGroup.new()
var _characterButtonByKey: Dictionary = { }

var _selectedDeploymentCell: Vector2i = INVALID_DEPLOYMENT_CELL
var _selectedCharacterKey: int = -1
var _selectedRecruitRatio: int = 0

var _displayedBattleTimeSeconds: int = -1

var _displayedCPHp: int = -1
var _displayedCPMaxHp: int = -1
var _displayedCPMp: int = -1
var _displayedCPMaxMp: int = -1

var _displayedRecruitedPopulation: int = -1
var _displayedSurvivingPopulation: int = -1
var _displayedDeadPopulation: int = -1

var _isBattlePaused: bool = false

var _pendingDefenseResult: DefenseResult


func _ready() -> void:
	if not _InitializeNavigation():
		return

	_InitializeDeploymentGrid()
	_InitializeStartData()
	_InitializeDefenseManager()

	if not _InitializeDeploymentSelection():
		return

	_InitializeUI()


func _process(_delta: float) -> void:
	if _defenseManager == null:
		return

	_defenseManager.Update()

	if _defenseManager.GetPhase() == DefenseManager.DefensePhase.BATTLE:
		_UpdateBattleHUD()


func _unhandled_input(event: InputEvent) -> void:
	if not _deploymentPanel.visible:
		return

	if event.is_action_pressed("ui_cancel"):
		_CloseDeploymentPanel()
		get_viewport().set_input_as_handled()


func Initialize(startData: DefenseStartData) -> void:
	_startData = startData


#region Event

func _OnDeploymentCellClicked(cell: Vector2i) -> void:
	_selectedDeploymentCell = cell

	var deployment: DefenseDeploymentManager.DefenseDeployment = (
		_defenseManager.GetDeploymentByCell(cell)
	)
	if deployment != null:
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
	_UpdateRecruitPopulationLabel()
	_UpdateDeploymentApplyButton()


func _OnDeploymentApplyPressed() -> void:
	if not _ApplyDeploymentSelection():
		return

	_CloseDeploymentPanel()


func _OnConfirmDeploymentPressed() -> void:
	if not _defenseManager.ConfirmDeployment():
		return

	_FinishDeploymentUI()


func _FinishDeploymentUI() -> void:
	_CloseDeploymentPanel()

	_deploymentGridView.visible = false
	_deploymentGridView.process_mode = Node.PROCESS_MODE_DISABLED

	_deploymentUI.visible = false
	_battleHud.visible = true

	_displayedBattleTimeSeconds = -1
	_UpdateBattleTimeLabel()


func _OnPauseButtonPressed() -> void:
	if _isBattlePaused:
		_defenseManager.ResumeBattle()
		_isBattlePaused = false
		_pauseButton.text = "일시정지"
	else:
		_defenseManager.PauseBattle()
		_isBattlePaused = true
		_pauseButton.text = "계속"


func _OnResultConfirmPressed() -> void:
	if _pendingDefenseResult == null:
		return

	var result: DefenseResult = _pendingDefenseResult
	_pendingDefenseResult = null

	_resultConfirmButton.disabled = true

	DefenseFinished.emit(result)


func _OnDefenseFinished(result: DefenseResult) -> void:
	_ShowResultUI(result)

#endregion


#region Initialize

func _InitializeNavigation() -> bool:
	_navigationService = NavigationService.new()
	_navigationService.navigationData = _navigationData
	_navigationService.Ready()

	if not _navigationService.IsReady():
		push_error("DefenseScene: NavigationService 초기화에 실패했습니다.")
		return false

	_movementSimulator.navigationService = _navigationService

	return true


func _InitializeDeploymentGrid() -> void:
	var worldRect: Rect2 = _navigationData.GetWorldRect()
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

	_startData.cpMaxHp = 1000


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

	_InitializeCharacterButtons(unitDataList)

	_selectedCharacterKey = unitDataList[0].characterKey
	_selectedRecruitRatio = 0

	_ConnectDeploymentSelectionSignals()

	_deploymentPanel.visible = false
	_UpdateRecruitRatioLabel()

	return true


func _InitializeCharacterButtons(unitDataList: Array[CharacterData]) -> void:
	_characterButtonGroup.allow_unpress = false

	for characterData: CharacterData in unitDataList:
		var characterButton: Button = Button.new()
		characterButton.text = characterData.characterName
		characterButton.toggle_mode = true
		characterButton.button_group = _characterButtonGroup
		characterButton.pressed.connect(_OnCharacterButtonPressed.bind(characterData.characterKey))

		_characterButtonContainer.add_child(characterButton)
		_characterButtonByKey[characterData.characterKey] = characterButton


func _ConnectDeploymentSelectionSignals() -> void:
	_recruitRatioSpinBox.value_changed.connect(_OnRecruitRatioChanged)
	_deploymentApplyButton.pressed.connect(_OnDeploymentApplyPressed)


func _InitializeUI() -> void:
	_pauseButton.pressed.connect(_OnPauseButtonPressed)
	_resultConfirmButton.pressed.connect(_OnResultConfirmPressed)

#endregion


#region Deployment UI

func _ApplyDeploymentSelection() -> bool:
	if _selectedDeploymentCell == INVALID_DEPLOYMENT_CELL or _selectedCharacterKey < 0:
		return false

	var deployment: DefenseDeploymentManager.DefenseDeployment = (
		_defenseManager.GetDeploymentByCell(_selectedDeploymentCell)
	)

	if _selectedRecruitRatio == 0 and deployment == null:
		return true

	var isApplied: bool
	if _selectedRecruitRatio == 0:
		isApplied = _RemoveSelectedDeployment()
	elif deployment == null:
		isApplied = _AddSelectedDeployment()
	else:
		isApplied = _UpdateSelectedDeployment()

	if not isApplied:
		_ReloadDeploymentSelection()
		return false

	_UpdateRecruitRatioLabel()
	return true


func _RemoveSelectedDeployment() -> bool:
	if not _defenseManager.RemoveDeployment(_selectedDeploymentCell):
		return false

	_deploymentGridView.RemoveDeployment(_selectedDeploymentCell)
	return true


func _AddSelectedDeployment() -> bool:
	var spawnPosition: Vector2 = _deploymentGrid.CellToWorldCenter(_selectedDeploymentCell)
	if not _defenseManager.AddDeployment(
		_selectedDeploymentCell,
		_selectedCharacterKey,
		_selectedRecruitRatio,
		spawnPosition,
	):
		return false

	_deploymentGridView.SetDeployment(_selectedDeploymentCell)
	return true


func _UpdateSelectedDeployment() -> bool:
	return _defenseManager.UpdateDeployment(
		_selectedDeploymentCell,
		_selectedCharacterKey,
		_selectedRecruitRatio,
	)


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

	var maxRecruitRatio: int = _defenseManager.GetMaxRecruitRatioForCell(_selectedDeploymentCell)
	_selectedRecruitRatio = mini(_selectedRecruitRatio, maxRecruitRatio)
	var maxRecruitPercent: int = Math.RatioToPercent(maxRecruitRatio)
	_recruitRatioSpinBox.max_value = maxRecruitPercent

	var recruitPercent: int = Math.RatioToPercent(_selectedRecruitRatio)
	_recruitRatioSpinBox.set_value_no_signal(recruitPercent)

	_UpdateRecruitPopulationLabel()
	_UpdateDeploymentApplyButton()


func _UpdateRecruitPopulationLabel() -> void:
	var population: int = _defenseManager.CalculateRecruitedPopulation(_selectedRecruitRatio)
	_recruitPopulationLabel.text = "징집 인구: %d명" % population


func _UpdateDeploymentApplyButton() -> void:
	var deployment: DefenseDeploymentManager.DefenseDeployment = _defenseManager.GetDeploymentByCell(
		_selectedDeploymentCell
	)

	if _selectedRecruitRatio == 0:
		_deploymentApplyButton.disabled = deployment == null
		return

	var recruitedPopulation: int = _defenseManager.CalculateRecruitedPopulation(
		_selectedRecruitRatio
	)

	_deploymentApplyButton.disabled = recruitedPopulation <= 0


func _UpdateRecruitRatioLabel() -> void:
	var totalRecruitRatio: int = _defenseManager.GetTotalRecruitRatio()
	var maxRecruitRatio: int = _defenseManager.GetMaxRecruitRatio()

	var totalPercent: int = Math.RatioToPercent(totalRecruitRatio)
	var maxPercent: int = Math.RatioToPercent(maxRecruitRatio)

	var recruitedPopulation: int = _defenseManager.GetTotalRecruitedPopulation()

	_recruitRatioLabel.text = "징집: %d%% / %d%%  (%d명 / %d명)" % [
		totalPercent,
		maxPercent,
		recruitedPopulation,
		_startData.population,
	]

	_confirmButton.disabled = recruitedPopulation <= 0


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


#region Battle UI

func _UpdateBattleHUD() -> void:
	_UpdateBattleTimeLabel()
	_UpdateCPStatus()
	_UpdatePopulationStatus()


func _UpdateBattleTimeLabel() -> void:
	var elapsedTimeMs: int = _defenseManager.GetElapsedTimeMs()
	var elapsedSeconds: int = Math.DivideInt(elapsedTimeMs, 1000)
	if elapsedSeconds == _displayedBattleTimeSeconds:
		return

	_displayedBattleTimeSeconds = elapsedSeconds

	var minutes: int = Math.DivideInt(elapsedSeconds, 60)
	var seconds: int = Math.RemainderInt(elapsedSeconds, 60)

	_elapsedTime.text = "%02d:%02d" % [minutes, seconds]


func _UpdateCPStatus() -> void:
	_UpdateCPHp()
	_UpdateCPMp()


func _UpdateCPHp() -> void:
	var currentHp: int = _defenseManager.GetCPCurrentHp()
	var maxHp: int = _defenseManager.GetCPMaxHp()
	if currentHp == _displayedCPHp and maxHp == _displayedCPMaxHp:
		return

	_displayedCPHp = currentHp
	_displayedCPMaxHp = maxHp

	_cpHpBar.max_value = maxHp
	_cpHpBar.value = currentHp

	_cpHpLabel.text = "HP %d / %d" % [currentHp, maxHp]


func _UpdateCPMp() -> void:
	var currentMp: int = _defenseManager.GetCPCurrentMp()
	var maxMp: int = _defenseManager.GetCPMaxMp()
	if maxMp <= 0:
		_cpMp.visible = false
		return

	_cpMp.visible = true

	if currentMp == _displayedCPMp and maxMp == _displayedCPMaxMp:
		return

	_displayedCPMp = currentMp
	_displayedCPMaxMp = maxMp

	_cpMpBar.max_value = maxMp
	_cpMpBar.value = currentMp

	_cpMpLabel.text = "MP %d / %d" % [currentMp, maxMp]


func _UpdatePopulationStatus() -> void:
	var recruitedPopulation: int = _defenseManager.GetRecruitedPopulation()
	var survivingPopulation: int = _defenseManager.GetSurvivingPopulation()
	var deadPopulation: int = _defenseManager.GetDeadPopulation()

	if (
		recruitedPopulation == _displayedRecruitedPopulation
		and survivingPopulation == _displayedSurvivingPopulation
		and deadPopulation == _displayedDeadPopulation
	):
		return

	_displayedRecruitedPopulation = recruitedPopulation
	_displayedSurvivingPopulation = survivingPopulation
	_displayedDeadPopulation = deadPopulation

	_recruitedPopulation.text = "징집: %d명" % recruitedPopulation
	_survivingPopulation.text = "생존: %d명" % survivingPopulation
	_deadPopulation.text = "사망: %d명" % deadPopulation

#endregion


#region Result UI

func _ShowResultUI(result: DefenseResult) -> void:
	_pendingDefenseResult = result

	_isBattlePaused = false
	_pauseButton.disabled = true
	_pauseButton.text = "일시정지"

	_battleHud.visible = false
	_resultUI.visible = true

	_result.text = "승리" if result.isVictory else "패배"

	_SetResultElapsedTime(result.elapsedTimeMs)

	_resultCPStatus.text = ("지휘소: 파괴"
		if result.cpDestroyed
		else "지휘소: 생존")

	_resultRecruitedPopulation.text = "징집 인구: %d명" % result.recruitedPopulation
	_resultSurvivingPopulation.text = "생존 인구: %d명" % result.survivingPopulation
	_resultDeadPopulation.text = "사망 인구: %d명" % result.deadPopulation


func _SetResultElapsedTime(elapsedTimeMs: int) -> void:
	var elapsedSeconds: int = Math.DivideInt(elapsedTimeMs, 1000)
	var minutes: int = Math.DivideInt(elapsedSeconds, 60)
	var seconds: int = Math.RemainderInt(elapsedSeconds, 60)

	_resultElapsedTime.text = "전투 시간: %02d:%02d" % [minutes, seconds]

#endregion
