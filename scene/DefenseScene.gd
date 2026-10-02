extends Node2D

const DEPLOYMENT_CELL_SIZE: int = 128
const DEPLOYMENT_UNIT_HALF_SIZE: int = 16
const INVALID_DEPLOYMENT_CELL: Vector2i = Vector2i(-1, -1)
const CP_CELL: Vector2i = Vector2i(4, 1)
const DRAG_PREVIEW_SIZE: Vector2 = Vector2(72, 72)
const DEFENSE_CHARACTER_BUTTON_SCENE: PackedScene = preload(
	"res://ui/defense/deployment/DefenseCharacterButton.tscn"
)
const DEFENSE_MERCENARY_BUTTON_SCENE: PackedScene = preload(
	"res://ui/defense/deployment/DefenseMercenaryButton.tscn"
)

signal DefenseFinished(result: DefenseResult)


@export_group("UI")
@export var _deploymentUI: Control
@export var _battleHUD: PanelContainer
@export var _resultUI: PanelContainer

@onready var _defenseSceneManager: DefenseSceneManager = $DefenseSceneManager

@onready var _cp: DefenseCP = $CP
@onready var _deploymentGridView: DefenseDeploymentGridView = $DeploymentGridView
@onready var _deploymentInfoView: DefenseDeploymentInfoView = $DeploymentInfoView

#region Deployment

@onready var _deploymentDock: DefenseDeploymentDock = _deploymentUI.get_node("DeploymentDock")
@onready var _characterButtonContainer: HBoxContainer = _deploymentDock.GetButtonContainer()

@onready var _deploymentHUDContainer: HBoxContainer = _deploymentUI.get_node(
	"DeploymentHUD/Margin/HUDContainer"
)
@onready var _recruitSummaryLabel: Label = _deploymentHUDContainer.get_node("RecruitSummaryLabel")

#endregion

#region Battle

@onready var _battleHUDContainer: VBoxContainer = _battleHUD.get_node("Margin/BattleHUDContainer")

@onready var _elapsedTime: Label = _battleHUDContainer.get_node("BattleHeader/ElapsedTime")
@onready var _pauseButton: Button = _battleHUDContainer.get_node("BattleHeader/PauseButton")

@onready var _cpHUD: VBoxContainer = _battleHUDContainer.get_node("CPHUD")

@onready var _cpHp: HBoxContainer = _cpHUD.get_node("Hp")
@onready var _cpHpLabel: Label = _cpHp.get_node("HpLabel")
@onready var _cpHpBar: ProgressBar = _cpHp.get_node("HpBar")
@onready var _cpMp: HBoxContainer = _cpHUD.get_node("Mp")
@onready var _cpMpLabel: Label = _cpMp.get_node("MpLabel")
@onready var _cpMpBar: ProgressBar = _cpMp.get_node("MpBar")

@onready var _population: HBoxContainer = _battleHUDContainer.get_node("Population")

@onready var _recruitedPopulation: Label = _population.get_node("RecruitedPopulation")
@onready var _survivingPopulation: Label = _population.get_node("SurvivingPopulation")
@onready var _deadPopulation: Label = _population.get_node("DeadPopulation")

#endregion

#region Result

@onready var _resultContainer: VBoxContainer = _resultUI.get_node("Margin/ResultContainer")

@onready var _resultLabel: Label = _resultContainer.get_node("ResultLabel")
@onready var _resultElapsedTime: Label = _resultContainer.get_node("ElapsedTime")
@onready var _resultCPStatus: Label = _resultContainer.get_node("CPStatus")
@onready var _resultRecruitedPopulation: Label = _resultContainer.get_node("RecruitedPopulation")
@onready var _resultSurvivingPopulation: Label = _resultContainer.get_node("SurvivingPopulation")
@onready var _resultDeadPopulation: Label = _resultContainer.get_node("DeadPopulation")
@onready var _resultConfirmButton: Button = _resultContainer.get_node("ConfirmButton")

#endregion

var _deploymentGrid: DefenseDeploymentGrid
var _startData: DefenseStartData

var _characterButtonGroup: ButtonGroup = ButtonGroup.new()
var _characterButtonByKey: Dictionary[int, DefenseCharacterButton] = { }
var _selectedCharacterKey: int = -1
var _selectedRecruitRatio: int = 0

var _mercenaryButtonByKey: Dictionary[int, DefenseMercenaryButton] = { }
var _selectedMercenaryKey: int = -1

var _isDeploymentDragActive: bool = false
var _dragPreview: TextureRect

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


#region Lifecycle

func _ready() -> void:
	_InitializeDeploymentGrid()

	_cp.global_position = _deploymentGrid.CellToWorldCenter(CP_CELL)

	_InitializeStartData()

	if not _defenseSceneManager.Initialize(_startData):
		return

	_InitializeDeploymentGridView()

	if not _InitializeDeploymentSelection():
		return

	_InitializeUI()

	_defenseSceneManager.DefenseFinished.connect(_OnDefenseFinished)


func _process(_delta: float) -> void:
	if _isDeploymentDragActive:
		_UpdateDragPreviewPosition()

	if _defenseSceneManager == null:
		return

	if _defenseSceneManager.GetPhase() == DefenseSceneManager.DefensePhase.BATTLE:
		_UpdateBattleHUD()


func _input(event: InputEvent) -> void:
	if not _isDeploymentDragActive:
		return

	if event.is_action_pressed("ui_cancel"):
		_StopDeploymentDrag()
		return

	if event is not InputEventMouseButton:
		return

	var mouseEvent: InputEventMouseButton = event
	if mouseEvent.button_index != MOUSE_BUTTON_LEFT or mouseEvent.pressed:
		return

	_TryDropDeployment(mouseEvent.position)
	_StopDeploymentDrag()


func Initialize(startData: DefenseStartData) -> void:
	_startData = startData

#endregion


#region Initialize

func _InitializeDeploymentGrid() -> void:
	var worldRect: Rect2 = _defenseSceneManager.GetNavigationWorldRect()

	var deploymentGridSize: Vector2i = Vector2i(
		floori(worldRect.size.x / DEPLOYMENT_CELL_SIZE),
		floori(worldRect.size.y / DEPLOYMENT_CELL_SIZE),
	)

	_deploymentGrid = DefenseDeploymentGrid.new(
		DEPLOYMENT_CELL_SIZE,
		worldRect.position,
		deploymentGridSize,
	)


func _InitializeStartData() -> void:
	if _startData != null:
		return

	_startData = DefenseStartData.new()
	_startData.cycle = 1
	_startData.population = 100

	_startData.cpMaxHp = 1000
	_startData.cpDef = 0
	_startData.cpMagicDef = 0

	_startData.installableCountByCharacterKey[500] = 2
	_startData.installableCountByCharacterKey[501] = 2
	_startData.installableCountByCharacterKey[750] = 2
	_startData.installableCountByCharacterKey[751] = 2

	_startData.availableMercenaryKeys = [0, 1, 2]


func _InitializeDeploymentGridView() -> void:
	_deploymentGridView.Initialize(
		_deploymentGrid,
		Callable(self, "_CanInteractDeploymentCell"),
		Callable(self, "_CanPlaceCurrentSelectionAtCell"),
	)
	_deploymentInfoView.Initialize(_deploymentGrid)

	_deploymentGridView.CellClicked.connect(_OnDeploymentCellClicked)
	_deploymentGridView.CellRightClicked.connect(_OnDeploymentCellRightClicked)


func _InitializeDeploymentSelection() -> bool:
	if not _BeginUnitDeploymentUI():
		return false

	_ConnectDeploymentSelectionSignals()

	return true


func _InitializeCharacterButtons(characterDataList: Array[CharacterData]) -> void:
	_characterButtonGroup.allow_unpress = false

	for characterData: CharacterData in characterDataList:
		var characterButton: DefenseCharacterButton = DEFENSE_CHARACTER_BUTTON_SCENE.instantiate()
		_characterButtonContainer.add_child(characterButton)
		characterButton.Initialize(characterData)
		characterButton.button_group = _characterButtonGroup
		characterButton.pressed.connect(_OnCharacterButtonPressed.bind(characterData.characterKey))
		characterButton.drag_started.connect(_OnCharacterDragStarted)

		_characterButtonByKey[characterData.characterKey] = characterButton


func _InitializeMercenaryButtons() -> bool:
	_ClearSelectionButtons()

	if _startData.availableMercenaryKeys.is_empty():
		push_error("DefenseScene: 배치 가능한 용병이 없습니다.")
		return false

	for mercenaryKey: int in _startData.availableMercenaryKeys:
		var mercenaryData: MercenaryData = GameDataManager.GetMercenaryData(mercenaryKey)
		if mercenaryData == null:
			push_error("DefenseScene: MercenaryData가 없습니다. key: " + str(mercenaryKey))
			return false

		var button: DefenseMercenaryButton = DEFENSE_MERCENARY_BUTTON_SCENE.instantiate()
		_characterButtonContainer.add_child(button)
		button.Initialize(mercenaryData, GameDataManager.GetMercenaryBuffData(mercenaryKey))
		button.SetButtonGroup(_characterButtonGroup)
		button.selected.connect(_OnMercenaryButtonPressed.bind(mercenaryData.mercenaryKey))
		button.drag_started.connect(_OnMercenaryDragStarted)

		_mercenaryButtonByKey[mercenaryKey] = button

	_selectedMercenaryKey = _startData.availableMercenaryKeys[0]

	var firstButton: DefenseMercenaryButton = _mercenaryButtonByKey.get(_selectedMercenaryKey)
	if firstButton != null:
		firstButton.SetSelected(true)

	return true


func _ConnectDeploymentSelectionSignals() -> void:
	_deploymentDock.recruit_ratio_changed.connect(_OnRecruitRatioChanged)
	_deploymentDock.back_pressed.connect(_OnDeploymentBackPressed)
	_deploymentDock.confirm_pressed.connect(_OnConfirmDeploymentPressed)


func _InitializeUI() -> void:
	_pauseButton.pressed.connect(_OnPauseButtonPressed)
	_resultConfirmButton.pressed.connect(_OnResultConfirmPressed)

#endregion


#region Deployment Events

func _OnDeploymentCellClicked(cell: Vector2i) -> void:
	_PlaceCurrentSelectionAtCell(cell)


func _OnDeploymentCellRightClicked(cell: Vector2i) -> void:
	match _defenseSceneManager.GetPhase():
		DefenseSceneManager.DefensePhase.UNIT_DEPLOYMENT:
			_RemoveUnitDeploymentByRightClick(cell)

		DefenseSceneManager.DefensePhase.INSTALLABLE_DEPLOYMENT:
			_RemoveInstallableByRightClick(cell)

		DefenseSceneManager.DefensePhase.MERCENARY_ASSIGNMENT:
			_RemoveMercenaryAssignmentByRightClick(cell)


func _OnDeploymentBackPressed() -> void:
	_StopDeploymentDrag()

	if not _defenseSceneManager.ReturnToPreviousDeploymentPhase():
		return

	if _deploymentGridView.has_method("ClearFocusedCell"):
		_deploymentGridView.ClearFocusedCell()

	match _defenseSceneManager.GetPhase():
		DefenseSceneManager.DefensePhase.UNIT_DEPLOYMENT:
			_BeginUnitDeploymentUI()

		DefenseSceneManager.DefensePhase.INSTALLABLE_DEPLOYMENT:
			_BeginInstallableDeploymentUI()


func _OnConfirmDeploymentPressed() -> void:
	match _defenseSceneManager.GetPhase():
		DefenseSceneManager.DefensePhase.UNIT_DEPLOYMENT:
			if not _defenseSceneManager.ConfirmDeployment():
				return

			_BeginInstallableDeploymentUI()

		DefenseSceneManager.DefensePhase.INSTALLABLE_DEPLOYMENT:
			if not _defenseSceneManager.ConfirmInstallableDeployment():
				return

			_BeginMercenaryAssignmentUI()

		DefenseSceneManager.DefensePhase.MERCENARY_ASSIGNMENT:
			if not _defenseSceneManager.ConfirmMercenaryAssignment():
				return

			_FinishDeploymentUI()


func _OnCharacterButtonPressed(characterKey: int) -> void:
	_selectedCharacterKey = characterKey
	_RefreshPlacementPreview()


func _OnRecruitRatioChanged(value: float) -> void:
	_selectedRecruitRatio = Math.PercentToRatio(int(value))
	_UpdateRecruitPopulationLabel()
	_UpdateUnitDeploymentStatus()
	_RefreshPlacementPreview()


func _OnCharacterDragStarted(characterKey: int, previewTexture: Texture2D) -> void:
	_selectedCharacterKey = characterKey

	var button: DefenseCharacterButton = _characterButtonByKey.get(characterKey)
	if button != null:
		button.SetSelected(true)

	_RefreshPlacementPreview()
	_StartDeploymentDrag(previewTexture)


func _OnMercenaryDragStarted(mercenaryKey: int, previewTexture: Texture2D) -> void:
	_selectedMercenaryKey = mercenaryKey

	var button: DefenseMercenaryButton = _mercenaryButtonByKey.get(mercenaryKey)
	if button != null:
		button.SetSelected(true)

	_RefreshPlacementPreview()
	_StartDeploymentDrag(previewTexture)


func _PlaceCurrentSelectionAtCell(cell: Vector2i) -> bool:
	match _defenseSceneManager.GetPhase():
		DefenseSceneManager.DefensePhase.UNIT_DEPLOYMENT:
			return _PlaceSelectedUnitAtCell(cell)

		DefenseSceneManager.DefensePhase.INSTALLABLE_DEPLOYMENT:
			return _PlaceSelectedInstallableAtCell(cell)

		DefenseSceneManager.DefensePhase.MERCENARY_ASSIGNMENT:
			return _AssignSelectedMercenaryToCell(cell)

	return false

#endregion


#region Drag And Drop

func _StartDeploymentDrag(previewTexture: Texture2D) -> void:
	if previewTexture == null:
		return

	_isDeploymentDragActive = true

	if _dragPreview == null:
		_dragPreview = TextureRect.new()
		_dragPreview.custom_minimum_size = DRAG_PREVIEW_SIZE
		_dragPreview.size = DRAG_PREVIEW_SIZE
		_dragPreview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_dragPreview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_dragPreview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_dragPreview.modulate = Color(1.0, 1.0, 1.0, 0.82)
		_dragPreview.z_index = 100
		_deploymentUI.add_child(_dragPreview)

	_dragPreview.texture = previewTexture
	_dragPreview.visible = true
	_UpdateDragPreviewPosition()


func _StopDeploymentDrag() -> void:
	_isDeploymentDragActive = false

	if _dragPreview != null:
		_dragPreview.visible = false


func _UpdateDragPreviewPosition() -> void:
	if _dragPreview == null:
		return

	_dragPreview.position = get_viewport().get_mouse_position() - DRAG_PREVIEW_SIZE * 0.5


func _TryDropDeployment(screenPosition: Vector2) -> void:
	if _deploymentDock.get_global_rect().has_point(screenPosition):
		return

	var cell: Vector2i = _deploymentGrid.WorldToCell(
		_deploymentGridView.get_global_mouse_position()
	)
	if not _CanPlaceCurrentSelectionAtCell(cell):
		return

	_PlaceCurrentSelectionAtCell(cell)

#endregion


#region Unit Deployment

func _BeginUnitDeploymentUI() -> bool:
	_StopDeploymentDrag()
	_ClearSelectionButtons()
	_deploymentInfoView.ClearMercenaries()

	var unitDataList: Array[CharacterData] = GameDataManager.GetCharacterDataByType(
		CharacterData.CharacterType.UNIT
	)
	if unitDataList.is_empty():
		push_error("DefenseScene: 배치 가능한 UNIT 데이터가 없습니다.")
		return false

	_InitializeCharacterButtons(unitDataList)

	if not _characterButtonByKey.has(_selectedCharacterKey):
		_selectedCharacterKey = unitDataList[0].characterKey

	var selectedButton: DefenseCharacterButton = _characterButtonByKey.get(_selectedCharacterKey)
	if selectedButton != null:
		selectedButton.SetSelected(true)

	_deploymentDock.SetUnitControlsVisible(true)
	_deploymentDock.SetBackButtonVisible(false)

	_deploymentDock.SetRecruitRatioMax(
		Math.RatioToPercent(_defenseSceneManager.GetMaxRecruitRatio())
	)
	_deploymentDock.SetRecruitRatioValue(Math.RatioToPercent(_selectedRecruitRatio))

	_UpdateRecruitPopulationLabel()

	_deploymentDock.SetConfirmText("다음: 병기/함정")

	_UpdateUnitDeploymentSummary()
	_SetUnitDeploymentHint()
	_UpdateUnitDeploymentStatus()
	_RefreshPlacementPreview()

	_deploymentGridView.queue_redraw()
	return true


func _PlaceSelectedUnitAtCell(cell: Vector2i) -> bool:
	if _selectedCharacterKey < 0:
		return false

	if _selectedRecruitRatio <= 0:
		_deploymentDock.SetStatusText("배치 병력을 1% 이상 설정하세요.")
		return false

	var maxRecruitRatio: int = _defenseSceneManager.GetMaxRecruitRatioForCell(cell)
	if _selectedRecruitRatio > maxRecruitRatio:
		_deploymentDock.SetStatusText(
			"남은 징집률이 부족합니다.\n"
			+ "이 셀에는 최대 %d%%까지 배치할 수 있습니다." % Math.RatioToPercent(maxRecruitRatio)
		)
		return false

	var deployment: DefenseDeploymentManager.DefenseDeployment = _defenseSceneManager.GetDeploymentByCell(
		cell
	)
	var success: bool

	if deployment == null:
		var spawnPosition: Vector2 = _deploymentGrid.CellToWorldCenter(cell)
		success = _defenseSceneManager.AddDeployment(
			cell,
			_selectedCharacterKey,
			_selectedRecruitRatio,
			spawnPosition,
		)
	else:
		success = _defenseSceneManager.UpdateDeployment(
			cell,
			_selectedCharacterKey,
			_selectedRecruitRatio,
		)

	if not success:
		_deploymentDock.SetHintText("해당 셀에 병력을 배치할 수 없습니다.")
		return false

	_deploymentInfoView.SetRecruitRatio(cell, _selectedRecruitRatio)
	_UpdateUnitDeploymentSummary()
	_UpdateUnitDeploymentStatus()
	return true


func _RemoveUnitDeploymentByRightClick(cell: Vector2i) -> void:
	if not _defenseSceneManager.RemoveDeployment(cell):
		return

	_deploymentInfoView.RemoveRecruitRatio(cell)
	_UpdateUnitDeploymentSummary()
	_UpdateUnitDeploymentStatus()


func _UpdateRecruitPopulationLabel() -> void:
	var population: int = _defenseSceneManager.CalculateRecruitedPopulation(_selectedRecruitRatio)
	_deploymentDock.SetRecruitPopulation(population)


func _UpdateUnitDeploymentSummary() -> void:
	var totalRecruitRatio: int = _defenseSceneManager.GetTotalRecruitRatio()
	var maxRecruitRatio: int = _defenseSceneManager.GetMaxRecruitRatio()

	var totalPercent: int = Math.RatioToPercent(totalRecruitRatio)
	var maxPercent: int = Math.RatioToPercent(maxRecruitRatio)
	var recruitedPopulation: int = _defenseSceneManager.GetTotalRecruitedPopulation()

	_recruitSummaryLabel.text = "징집: %d%% / %d%%  (%d명 / %d명)" % [
		totalPercent,
		maxPercent,
		recruitedPopulation,
		_startData.population,
	]

	_deploymentDock.SetConfirmDisabled(recruitedPopulation <= 0)


func _SetUnitDeploymentHint() -> void:
	_deploymentDock.SetHintText("병과 선택 → 배치 병력 설정 → 셀 클릭 또는 드래그\n" + "우클릭: 배치 회수")


func _UpdateUnitDeploymentStatus() -> void:
	var population: int = _defenseSceneManager.CalculateRecruitedPopulation(_selectedRecruitRatio)

	var remainingRatio: int = _defenseSceneManager.GetMaxRecruitRatio() - _defenseSceneManager.GetTotalRecruitRatio()

	_deploymentDock.SetStatusText(
		"현재 %d%% · %d명    남은 징집률 %d%%"
		% [
			Math.RatioToPercent(_selectedRecruitRatio),
			population,
			Math.RatioToPercent(remainingRatio),
		]
	)

#endregion


#region Installable Deployment

func _BeginInstallableDeploymentUI() -> void:
	_StopDeploymentDrag()
	_ClearSelectionButtons()

	_deploymentInfoView.ClearMercenaries()

	var installableDataList: Array[CharacterData] = []
	var sourceDataList: Array[CharacterData] = []

	sourceDataList.append_array(
		GameDataManager.GetCharacterDataByType(CharacterData.CharacterType.MACHINE)
	)
	sourceDataList.append_array(
		GameDataManager.GetCharacterDataByType(CharacterData.CharacterType.TRAP)
	)

	for characterData: CharacterData in sourceDataList:
		if _defenseSceneManager.GetInstallableAvailableCount(characterData.characterKey) <= 0:
			continue

		installableDataList.append(characterData)

	_InitializeCharacterButtons(installableDataList)

	_selectedCharacterKey = -1
	for characterData: CharacterData in installableDataList:
		_selectedCharacterKey = characterData.characterKey
		var firstButton: DefenseCharacterButton = _characterButtonByKey.get(_selectedCharacterKey)
		if firstButton != null:
			firstButton.SetSelected(true)
		break

	_deploymentDock.SetUnitControlsVisible(false)
	_deploymentDock.SetBackButtonVisible(true)
	_deploymentDock.SetConfirmDisabled(false)
	_deploymentDock.SetConfirmText("다음: 용병")
	_deploymentDock.SetHintText("병기/함정을 선택한 뒤 셀을 클릭하거나 드래그하세요.\n" + "우클릭하면 회수합니다.")

	_UpdateInstallableButtonStates()
	_UpdateInstallableSummary()
	_UpdateInstallableStatus()
	_RefreshPlacementPreview()
	_deploymentGridView.queue_redraw()


func _UpdateInstallableButtonStates() -> void:
	var firstAvailableKey: int = -1

	for characterKey: int in _characterButtonByKey:
		var characterButton: DefenseCharacterButton = _characterButtonByKey.get(characterKey)
		if characterButton == null:
			continue

		var remainingCount: int = _defenseSceneManager.GetInstallableRemainingCount(characterKey)
		characterButton.ShowRemainingCount(remainingCount)
		characterButton.SetDisabled(remainingCount <= 0)

		if remainingCount > 0 and firstAvailableKey < 0:
			firstAvailableKey = characterKey

	if _selectedCharacterKey >= 0:
		var selectedRemainingCount: int = _defenseSceneManager.GetInstallableRemainingCount(
			_selectedCharacterKey
		)
		if selectedRemainingCount > 0:
			_RefreshPlacementPreview()
			return

	var previousButton: DefenseCharacterButton = _characterButtonByKey.get(_selectedCharacterKey)
	if previousButton != null:
		previousButton.SetSelected(false)

	_selectedCharacterKey = firstAvailableKey
	if _selectedCharacterKey >= 0:
		var nextButton: DefenseCharacterButton = _characterButtonByKey.get(_selectedCharacterKey)
		if nextButton != null:
			nextButton.SetSelected(true)

	_RefreshPlacementPreview()


func _PlaceSelectedInstallableAtCell(cell: Vector2i) -> bool:
	if _selectedCharacterKey < 0:
		_deploymentDock.SetHintText("배치 가능한 병기/함정이 없습니다.")
		return false

	if _defenseSceneManager.GetInstallableRemainingCount(_selectedCharacterKey) <= 0:
		_UpdateInstallableButtonStates()
		return false

	var deployment: DefenseInstallableDeploymentManager.DefenseInstallableDeployment = _defenseSceneManager.GetInstallableDeploymentByCell(
		cell
	)
	var success: bool

	if deployment == null:
		var position: Vector2 = _deploymentGrid.CellToWorldCenter(cell)
		success = _defenseSceneManager.AddInstallableDeployment(
			cell,
			_selectedCharacterKey,
			position,
		)
	else:
		success = _defenseSceneManager.UpdateInstallableDeployment(cell, _selectedCharacterKey)

	if not success:
		_deploymentDock.SetHintText("해당 셀에 병기/함정을 배치할 수 없습니다.")
		return false

	_UpdateInstallableButtonStates()
	_UpdateInstallableSummary()
	_deploymentDock.SetHintText("좌클릭/드래그 배치 · 우클릭 회수")
	return true


func _RemoveInstallableByRightClick(cell: Vector2i) -> void:
	if not _defenseSceneManager.RemoveInstallableDeployment(cell):
		return

	_UpdateInstallableButtonStates()
	_UpdateInstallableSummary()


func _UpdateInstallableSummary() -> void:
	var machineCount: int = 0
	var trapCount: int = 0

	for characterData: CharacterData in GameDataManager.GetCharacterDataByType(
		CharacterData.CharacterType.MACHINE
	):
		machineCount += _defenseSceneManager.GetInstallableDeployedCount(characterData.characterKey)

	for characterData: CharacterData in GameDataManager.GetCharacterDataByType(
		CharacterData.CharacterType.TRAP
	):
		trapCount += _defenseSceneManager.GetInstallableDeployedCount(characterData.characterKey)

	_recruitSummaryLabel.text = "병기: %d개 / 함정: %d개" % [machineCount, trapCount]


func _UpdateInstallableStatus() -> void:
	var machineCount: int = 0
	var trapCount: int = 0

	for characterData: CharacterData in GameDataManager.GetCharacterDataByType(
		CharacterData.CharacterType.MACHINE
	):
		machineCount += _defenseSceneManager.GetInstallableDeployedCount(characterData.characterKey)

	for characterData: CharacterData in GameDataManager.GetCharacterDataByType(
		CharacterData.CharacterType.TRAP
	):
		trapCount += _defenseSceneManager.GetInstallableDeployedCount(characterData.characterKey)

	_deploymentDock.SetStatusText("현재 배치 · 병기 %d개 · 함정 %d개" % [machineCount, trapCount])

#endregion


#region Mercenary Assignment

func _BeginMercenaryAssignmentUI() -> void:
	_StopDeploymentDrag()

	if not _InitializeMercenaryButtons():
		return

	_deploymentDock.SetUnitControlsVisible(false)
	_deploymentDock.SetBackButtonVisible(true)
	_deploymentDock.SetConfirmText("전투 시작")
	_deploymentDock.SetHintText("용병 선택 → 부대 또는 지휘소 클릭/드래그\n" + "우클릭: 용병 배치 해제")

	_RefreshMercenaryAssignmentUI()
	_RefreshPlacementPreview()
	_deploymentGridView.queue_redraw()


func _OnMercenaryButtonPressed(mercenaryKey: int) -> void:
	_selectedMercenaryKey = mercenaryKey

	_UpdateSelectedMercenaryTargetFocus()
	_RefreshPlacementPreview()


func _AssignSelectedMercenaryToCell(cell: Vector2i) -> bool:
	if _selectedMercenaryKey < 0:
		return false

	var success: bool
	if cell == CP_CELL:
		success = _defenseSceneManager.AssignMercenaryToCP(_selectedMercenaryKey)
	else:
		success = _defenseSceneManager.AssignMercenaryToUnit(_selectedMercenaryKey, cell)

	if not success:
		_deploymentDock.SetHintText("선택한 대상에 용병을 배치할 수 없습니다.")
		return false

	_RefreshMercenaryAssignmentUI()
	_deploymentDock.SetHintText("용병 선택 → 부대/지휘소 좌클릭 또는 드래그\n" + "우클릭: 배치 회수")
	return true


func _RemoveMercenaryAssignmentByRightClick(cell: Vector2i) -> void:
	var mercenaryKey: int

	if cell == CP_CELL:
		mercenaryKey = _defenseSceneManager.GetCPMercenaryKey()
	else:
		mercenaryKey = _defenseSceneManager.GetMercenaryKeyByUnitCell(cell)

	if mercenaryKey < 0:
		return

	if not _defenseSceneManager.UnassignMercenary(mercenaryKey):
		return

	_RefreshMercenaryAssignmentUI()


func _RefreshMercenaryAssignmentUI() -> void:
	_RefreshMercenaryAssignmentLabels()
	_UpdateMercenaryButtonStates()
	_UpdateMercenarySummary()
	_UpdateSelectedMercenaryTargetFocus()


func _RefreshMercenaryAssignmentLabels() -> void:
	_deploymentInfoView.ClearMercenaries()

	for mercenaryKey: int in _startData.availableMercenaryKeys:
		var assignment: DefenseMercenaryAssignmentManager.DefenseMercenaryAssignment = _defenseSceneManager.GetMercenaryAssignment(
			mercenaryKey
		)
		if assignment == null:
			continue

		var mercenaryData: MercenaryData = GameDataManager.GetMercenaryData(mercenaryKey)
		if mercenaryData == null:
			continue

		var cell: Vector2i
		match assignment.targetType:
			DefenseMercenaryAssignmentManager.TargetType.UNIT_GROUP:
				cell = assignment.unitCell

			DefenseMercenaryAssignmentManager.TargetType.CP:
				cell = CP_CELL

		_deploymentInfoView.SetMercenary(cell, mercenaryData)


func _UpdateSelectedMercenaryTargetFocus() -> void:
	if _selectedMercenaryKey < 0:
		_deploymentGridView.ClearFocusedCell()
		return

	var assignment: DefenseMercenaryAssignmentManager.DefenseMercenaryAssignment = _defenseSceneManager.GetMercenaryAssignment(
		_selectedMercenaryKey
	)
	if assignment == null:
		_deploymentGridView.ClearFocusedCell()
		return

	var targetCell: Vector2i
	match assignment.targetType:
		DefenseMercenaryAssignmentManager.TargetType.UNIT_GROUP:
			targetCell = assignment.unitCell
		DefenseMercenaryAssignmentManager.TargetType.CP:
			targetCell = CP_CELL
		_:
			_deploymentGridView.ClearFocusedCell()
			return

	_deploymentGridView.SetFocusedCell(targetCell)


func _UpdateMercenaryButtonStates() -> void:
	for mercenaryKey: int in _mercenaryButtonByKey:
		var button: DefenseMercenaryButton = _mercenaryButtonByKey.get(mercenaryKey)
		if button == null:
			continue

		var isAssigned: bool = _defenseSceneManager.IsMercenaryAssigned(mercenaryKey)
		button.SetAssigned(isAssigned)


func _UpdateMercenarySummary() -> void:
	var heroAssigned: bool = false

	for mercenaryKey: int in _startData.availableMercenaryKeys:
		var data: MercenaryData = GameDataManager.GetMercenaryData(mercenaryKey)
		if data == null or not data.isHero:
			continue

		heroAssigned = _defenseSceneManager.IsMercenaryAssigned(mercenaryKey)
		break

	var cpAssigned: bool = _defenseSceneManager.GetCPMercenaryKey() >= 0

	var heroText: String = "완료" if heroAssigned else "미배치"
	var cpText: String = "완료" if cpAssigned else "미배치"
	_deploymentDock.SetStatusText("주인공 %s    지휘소 %s" % [heroText, cpText])

	_deploymentDock.SetConfirmDisabled(not _defenseSceneManager.CanConfirmMercenaryAssignment())

#endregion


#region Deployment UI

func _RefreshPlacementPreview() -> void:
	var previewTexture: Texture2D

	match _defenseSceneManager.GetPhase():
		DefenseSceneManager.DefensePhase.UNIT_DEPLOYMENT:
			if _selectedRecruitRatio > 0:
				var characterButton: DefenseCharacterButton = _characterButtonByKey.get(
					_selectedCharacterKey
				)
				if characterButton != null:
					previewTexture = characterButton.GetIconTexture()

		DefenseSceneManager.DefensePhase.INSTALLABLE_DEPLOYMENT:
			if (
				_selectedCharacterKey >= 0
				and _defenseSceneManager.GetInstallableRemainingCount(_selectedCharacterKey) > 0
			):
				var characterButton: DefenseCharacterButton = _characterButtonByKey.get(
					_selectedCharacterKey
				)
				if characterButton != null:
					previewTexture = characterButton.GetIconTexture()

		DefenseSceneManager.DefensePhase.MERCENARY_ASSIGNMENT:
			var mercenaryButton: DefenseMercenaryButton = _mercenaryButtonByKey.get(
				_selectedMercenaryKey
			)
			if mercenaryButton != null:
				previewTexture = mercenaryButton.GetIconTexture()

	_deploymentGridView.SetPlacementPreview(previewTexture)


func _ClearSelectionButtons() -> void:
	for child: Node in _characterButtonContainer.get_children():
		child.queue_free()

	_characterButtonByKey.clear()
	_mercenaryButtonByKey.clear()

	_characterButtonGroup = ButtonGroup.new()
	_characterButtonGroup.allow_unpress = false


func _CanPlaceCurrentSelectionAtCell(cell: Vector2i) -> bool:
	if not _CanInteractDeploymentCell(cell):
		return false

	match _defenseSceneManager.GetPhase():
		DefenseSceneManager.DefensePhase.UNIT_DEPLOYMENT:
			if _selectedCharacterKey < 0 or _selectedRecruitRatio <= 0:
				return false

			return _selectedRecruitRatio <= _defenseSceneManager.GetMaxRecruitRatioForCell(cell)

		DefenseSceneManager.DefensePhase.INSTALLABLE_DEPLOYMENT:
			return (
				_selectedCharacterKey >= 0
				and _defenseSceneManager.GetInstallableRemainingCount(_selectedCharacterKey) > 0
			)

		DefenseSceneManager.DefensePhase.MERCENARY_ASSIGNMENT:
			return _selectedMercenaryKey >= 0

	return false


func _CanInteractDeploymentCell(cell: Vector2i) -> bool:
	match _defenseSceneManager.GetPhase():
		DefenseSceneManager.DefensePhase.UNIT_DEPLOYMENT:
			if cell == CP_CELL:
				return false

			if _defenseSceneManager.GetInstallableDeploymentByCell(cell) != null:
				return false

			if _defenseSceneManager.GetDeploymentByCell(cell) != null:
				return true

		DefenseSceneManager.DefensePhase.INSTALLABLE_DEPLOYMENT:
			if cell == CP_CELL:
				return false

			if _defenseSceneManager.GetInstallableDeploymentByCell(cell) != null:
				return true

			if _defenseSceneManager.GetDeploymentByCell(cell) != null:
				return false

		DefenseSceneManager.DefensePhase.MERCENARY_ASSIGNMENT:
			if cell == CP_CELL:
				return true

			return _defenseSceneManager.GetDeploymentByCell(cell) != null

	var position: Vector2 = _deploymentGrid.CellToWorldCenter(cell)
	return _defenseSceneManager.CanPlaceStatic(position, DEPLOYMENT_UNIT_HALF_SIZE)


func _FinishDeploymentUI() -> void:
	_StopDeploymentDrag()
	_deploymentGridView.SetPlacementPreview(null)

	_deploymentGridView.visible = false
	_deploymentGridView.process_mode = Node.PROCESS_MODE_DISABLED

	_deploymentInfoView.Clear()
	_deploymentInfoView.visible = false

	_deploymentUI.visible = false
	_battleHUD.visible = true

	_displayedBattleTimeSeconds = -1
	_UpdateBattleTimeLabel()

#endregion


#region Battle Events

func _OnPauseButtonPressed() -> void:
	if _isBattlePaused:
		_defenseSceneManager.ResumeBattle()
		_isBattlePaused = false
		_pauseButton.text = "일시정지"
	else:
		_defenseSceneManager.PauseBattle()
		_isBattlePaused = true
		_pauseButton.text = "계속"


func _OnDefenseFinished(result: DefenseResult) -> void:
	_ShowResultUI(result)

#endregion


#region Battle UI

func _UpdateBattleHUD() -> void:
	_UpdateBattleTimeLabel()
	_UpdateCPStatus()
	_UpdatePopulationStatus()


func _UpdateBattleTimeLabel() -> void:
	var elapsedTimeMs: int = _defenseSceneManager.GetElapsedTimeMs()
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
	var currentHp: int = _defenseSceneManager.GetCPCurrentHp()
	var maxHp: int = _defenseSceneManager.GetCPMaxHp()
	if currentHp == _displayedCPHp and maxHp == _displayedCPMaxHp:
		return

	_displayedCPHp = currentHp
	_displayedCPMaxHp = maxHp

	_cpHpBar.max_value = maxHp
	_cpHpBar.value = currentHp

	_cpHpLabel.text = "HP %d / %d" % [currentHp, maxHp]


func _UpdateCPMp() -> void:
	var currentMp: int = _defenseSceneManager.GetCPCurrentMp()
	var maxMp: int = _defenseSceneManager.GetCPMaxMp()
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
	var recruitedPopulation: int = _defenseSceneManager.GetRecruitedPopulation()
	var survivingPopulation: int = _defenseSceneManager.GetSurvivingPopulation()
	var deadPopulation: int = _defenseSceneManager.GetDeadPopulation()

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


#region Result Events

func _OnResultConfirmPressed() -> void:
	if _pendingDefenseResult == null:
		return

	var result: DefenseResult = _pendingDefenseResult
	_pendingDefenseResult = null

	_resultConfirmButton.disabled = true

	DefenseFinished.emit(result)

#endregion


#region Result UI

func _ShowResultUI(result: DefenseResult) -> void:
	_pendingDefenseResult = result

	_isBattlePaused = false
	_pauseButton.disabled = true
	_pauseButton.text = "일시정지"

	_battleHUD.visible = false
	_resultUI.visible = true

	_resultLabel.text = "승리" if result.isVictory else "패배"

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
