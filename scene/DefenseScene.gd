extends Node2D

const DEPLOYMENT_CELL_SIZE: int = 128
const DEPLOYMENT_UNIT_HALF_SIZE: int = 16
const CP_CELL: Vector2i = Vector2i(4, 1)

signal DefenseFinished(result: DefenseResult)

@onready var _deploymentView: DefenseDeploymentView = %DeploymentView
@onready var _battleHUDView: DefenseBattleHUDView = %BattleHUDView
@onready var _resultView: DefenseResultView = %ResultView

@onready var _defenseSceneManager: DefenseSceneManager = $DefenseSceneManager
@onready var _cp: DefenseCP = $CP
@onready var _deploymentGridView: DefenseDeploymentGridView = $DeploymentGridView
@onready var _deploymentInfoView: DefenseDeploymentInfoView = $DeploymentInfoView

var _deploymentGrid: DefenseDeploymentGrid
var _startData: DefenseStartData

var _selectedCharacterKey: int = -1
var _selectedRecruitRatio: int = 0
var _installableCharacterKeys: Array[int] = []

var _selectedMercenaryKey: int = -1
var _isBattlePaused: bool = false


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
	if _defenseSceneManager.GetPhase() == DefenseSceneManager.DefensePhase.BATTLE:
		_UpdateBattleHUD()


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
	if not _EnterCurrentPhaseUI():
		return false

	_ConnectDeploymentSelectionSignals()
	return true


func _ConnectDeploymentSelectionSignals() -> void:
	_deploymentView.character_selected.connect(_OnCharacterButtonPressed)
	_deploymentView.character_drag_started.connect(_OnCharacterDragStarted)
	_deploymentView.mercenary_selected.connect(_OnMercenaryButtonPressed)
	_deploymentView.mercenary_drag_started.connect(_OnMercenaryDragStarted)
	_deploymentView.recruit_ratio_changed.connect(_OnRecruitRatioChanged)
	_deploymentView.back_pressed.connect(_OnDeploymentBackPressed)
	_deploymentView.confirm_pressed.connect(_OnConfirmDeploymentPressed)
	_deploymentView.drag_released.connect(_OnDeploymentDragReleased)


func _InitializeUI() -> void:
	_battleHUDView.pause_pressed.connect(_OnPauseButtonPressed)
	_resultView.Confirmed.connect(_OnResultConfirmed)

#endregion


#region Deployment Actions

func _TryPlaceCurrentSelectionAtCell(cell: Vector2i) -> bool:
	if not _CanInteractDeploymentCell(cell):
		return false

	return _PlaceCurrentSelectionAtCell(cell)


func _PlaceCurrentSelectionAtCell(cell: Vector2i) -> bool:
	match _defenseSceneManager.GetPhase():
		DefenseSceneManager.DefensePhase.UNIT_DEPLOYMENT:
			return _PlaceSelectedUnitAtCell(cell)
		DefenseSceneManager.DefensePhase.INSTALLABLE_DEPLOYMENT:
			return _PlaceSelectedInstallableAtCell(cell)
		DefenseSceneManager.DefensePhase.MERCENARY_ASSIGNMENT:
			return _AssignSelectedMercenaryToCell(cell)

	return false


func _RemoveCurrentPhaseAtCell(cell: Vector2i) -> void:
	match _defenseSceneManager.GetPhase():
		DefenseSceneManager.DefensePhase.UNIT_DEPLOYMENT:
			_RemoveUnitDeploymentAtCell(cell)
		DefenseSceneManager.DefensePhase.INSTALLABLE_DEPLOYMENT:
			_RemoveInstallableAtCell(cell)
		DefenseSceneManager.DefensePhase.MERCENARY_ASSIGNMENT:
			_UnassignMercenaryAtCell(cell)

#endregion


#region Deployment Events

func _OnDeploymentCellClicked(cell: Vector2i) -> void:
	_TryPlaceCurrentSelectionAtCell(cell)


func _OnDeploymentCellRightClicked(cell: Vector2i) -> void:
	_RemoveCurrentPhaseAtCell(cell)


func _OnDeploymentBackPressed() -> void:
	_deploymentView.StopDrag()

	if not _defenseSceneManager.ReturnToPreviousDeploymentPhase():
		return

	_deploymentGridView.ClearFocusedCell()
	_EnterCurrentPhaseUI()


func _OnConfirmDeploymentPressed() -> void:
	var success: bool = false
	match _defenseSceneManager.GetPhase():
		DefenseSceneManager.DefensePhase.UNIT_DEPLOYMENT:
			success = _defenseSceneManager.ConfirmDeployment()
		DefenseSceneManager.DefensePhase.INSTALLABLE_DEPLOYMENT:
			success = _defenseSceneManager.ConfirmInstallableDeployment()
		DefenseSceneManager.DefensePhase.MERCENARY_ASSIGNMENT:
			success = _defenseSceneManager.ConfirmMercenaryAssignment()
		_:
			return

	if not success:
		return

	_EnterCurrentPhaseUI()


func _OnCharacterButtonPressed(characterKey: int) -> void:
	_selectedCharacterKey = characterKey

	_RefreshPlacementPreview()


func _OnRecruitRatioChanged(value: float) -> void:
	_selectedRecruitRatio = Math.PercentToRatio(int(value))

	_RefreshUnitDeploymentInfo()
	_RefreshPlacementPreview()


func _OnCharacterDragStarted(characterKey: int) -> void:
	_selectedCharacterKey = characterKey

	_RefreshPlacementPreview()


func _OnMercenaryButtonPressed(mercenaryKey: int) -> void:
	_selectedMercenaryKey = mercenaryKey

	_UpdateSelectedMercenaryTargetFocus()
	_RefreshPlacementPreview()


func _OnMercenaryDragStarted(mercenaryKey: int) -> void:
	_selectedMercenaryKey = mercenaryKey

	_UpdateSelectedMercenaryTargetFocus()
	_RefreshPlacementPreview()


func _OnDeploymentDragReleased(viewportPosition: Vector2) -> void:
	if _deploymentView.IsPointInsideDock(viewportPosition):
		return

	var cell: Vector2i = _deploymentGrid.WorldToCell(
		_deploymentGridView.get_global_mouse_position()
	)
	_TryPlaceCurrentSelectionAtCell(cell)

#endregion


#region Unit Deployment

func _BeginUnitDeploymentUI() -> bool:
	_deploymentView.StopDrag()
	_deploymentView.ShowView()
	_deploymentInfoView.ClearMercenaries()

	var unitDataList: Array[CharacterData] = GameDataManager.GetCharacterDataByType(
		CharacterData.CharacterType.UNIT
	)
	if unitDataList.is_empty():
		push_error("DefenseScene: 배치 가능한 UNIT 데이터가 없습니다.")
		return false

	_selectedCharacterKey = _deploymentView.SetCharacterButtons(unitDataList, _selectedCharacterKey)

	_deploymentView.ConfigureUnitPhase(
		Math.RatioToPercent(_defenseSceneManager.GetMaxRecruitRatio()),
		Math.RatioToPercent(_selectedRecruitRatio),
	)

	_RefreshUnitDeploymentInfo()
	_RefreshPlacementPreview()
	_deploymentGridView.queue_redraw()
	return true


func _PlaceSelectedUnitAtCell(cell: Vector2i) -> bool:
	if _selectedCharacterKey < 0:
		return false

	if _selectedRecruitRatio <= 0:
		_deploymentView.SetStatusText("배치 병력을 1% 이상 설정하세요.")
		return false

	var maxRecruitRatio: int = _defenseSceneManager.GetMaxRecruitRatioForCell(cell)
	if _selectedRecruitRatio > maxRecruitRatio:
		_deploymentView.SetStatusText(
			"남은 징집률이 부족합니다.\n"
			+ "이 셀에는 최대 %d%%까지 배치할 수 있습니다." % Math.RatioToPercent(maxRecruitRatio)
		)
		return false

	var success: bool

	var deployment: DefenseDeploymentManager.DefenseDeployment = (
		_defenseSceneManager.GetDeploymentByCell(cell)
	)
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
		_deploymentView.SetStatusText("해당 셀에 병력을 배치할 수 없습니다.")
		return false

	_deploymentInfoView.SetRecruitRatio(cell, _selectedRecruitRatio)
	_RefreshUnitDeploymentInfo()
	return true


func _RemoveUnitDeploymentAtCell(cell: Vector2i) -> void:
	if not _defenseSceneManager.RemoveDeployment(cell):
		return

	_deploymentInfoView.RemoveRecruitRatio(cell)
	_RefreshUnitDeploymentInfo()


func _RefreshUnitDeploymentInfo() -> void:
	var totalRecruitRatio: int = _defenseSceneManager.GetTotalRecruitRatio()
	var maxRecruitRatio: int = _defenseSceneManager.GetMaxRecruitRatio()
	var recruitedPopulation: int = _defenseSceneManager.GetTotalRecruitedPopulation()
	var selectedPopulation: int = _defenseSceneManager.CalculateRecruitedPopulation(
		_selectedRecruitRatio
	)
	var remainingRatio: int = maxRecruitRatio - totalRecruitRatio

	_deploymentView.UpdateUnitInfo(
		Math.RatioToPercent(totalRecruitRatio),
		Math.RatioToPercent(maxRecruitRatio),
		recruitedPopulation,
		_startData.population,
		Math.RatioToPercent(_selectedRecruitRatio),
		selectedPopulation,
		Math.RatioToPercent(remainingRatio),
	)

#endregion


#region Installable Deployment

func _BeginInstallableDeploymentUI() -> void:
	_deploymentView.StopDrag()
	_deploymentView.ShowView()
	_deploymentInfoView.ClearMercenaries()

	var installableDataList: Array[CharacterData] = []
	var sourceDataList: Array[CharacterData] = []
	sourceDataList.append_array(
		GameDataManager.GetCharacterDataByType(CharacterData.CharacterType.MACHINE)
	)
	sourceDataList.append_array(
		GameDataManager.GetCharacterDataByType(CharacterData.CharacterType.TRAP)
	)

	_installableCharacterKeys.clear()
	for characterData: CharacterData in sourceDataList:
		if _defenseSceneManager.GetInstallableAvailableCount(characterData.characterKey) <= 0:
			continue

		installableDataList.append(characterData)
		_installableCharacterKeys.append(characterData.characterKey)

	_selectedCharacterKey = _deploymentView.SetCharacterButtons(
		installableDataList,
		_selectedCharacterKey,
	)
	_deploymentView.ConfigureInstallablePhase()

	_UpdateInstallableButtonStates()
	_RefreshInstallableInfo()
	_RefreshPlacementPreview()
	_deploymentGridView.queue_redraw()


func _UpdateInstallableButtonStates() -> void:
	var remainingCountByCharacterKey: Dictionary[int, int] = { }
	for characterKey: int in _installableCharacterKeys:
		remainingCountByCharacterKey[characterKey] = (
			_defenseSceneManager.GetInstallableRemainingCount(characterKey)
		)

	_selectedCharacterKey = _deploymentView.UpdateInstallableButtonStates(
		remainingCountByCharacterKey,
		_selectedCharacterKey,
	)


func _PlaceSelectedInstallableAtCell(cell: Vector2i) -> bool:
	if _selectedCharacterKey < 0:
		_deploymentView.SetStatusText("배치 가능한 병기/함정이 없습니다.")
		return false

	if _defenseSceneManager.GetInstallableRemainingCount(_selectedCharacterKey) <= 0:
		_UpdateInstallableButtonStates()
		_RefreshPlacementPreview()
		return false

	var success: bool

	var deployment: DefenseInstallableDeploymentManager.DefenseInstallableDeployment = (
		_defenseSceneManager.GetInstallableDeploymentByCell(cell)
	)
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
		_deploymentView.SetStatusText("해당 셀에 병기/함정을 배치할 수 없습니다.")
		return false

	_UpdateInstallableButtonStates()
	_RefreshInstallableInfo()
	_RefreshPlacementPreview()
	return true


func _RemoveInstallableAtCell(cell: Vector2i) -> void:
	if not _defenseSceneManager.RemoveInstallableDeployment(cell):
		return

	_UpdateInstallableButtonStates()
	_RefreshInstallableInfo()
	_RefreshPlacementPreview()


func _RefreshInstallableInfo() -> void:
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

	_deploymentView.UpdateInstallableInfo(machineCount, trapCount)

#endregion


#region Mercenary Assignment

func _BeginMercenaryAssignmentUI() -> bool:
	_deploymentView.StopDrag()
	_deploymentView.ShowView()

	_selectedMercenaryKey = _deploymentView.SetMercenaryButtons(
		_startData.availableMercenaryKeys,
		_selectedMercenaryKey,
	)
	if _selectedMercenaryKey < 0:
		return false

	_deploymentView.ConfigureMercenaryPhase()

	_RefreshMercenaryAssignmentUI()
	_RefreshPlacementPreview()
	_deploymentGridView.queue_redraw()
	return true


func _AssignSelectedMercenaryToCell(cell: Vector2i) -> bool:
	if _selectedMercenaryKey < 0:
		return false

	var success: bool
	if cell == CP_CELL:
		success = _defenseSceneManager.AssignMercenaryToCP(_selectedMercenaryKey)
	else:
		success = _defenseSceneManager.AssignMercenaryToUnit(_selectedMercenaryKey, cell)

	if not success:
		_deploymentView.SetStatusText("선택한 대상에 용병을 배치할 수 없습니다.")
		return false

	_RefreshMercenaryAssignmentUI()
	return true


func _UnassignMercenaryAtCell(cell: Vector2i) -> void:
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
		var assignment: DefenseMercenaryAssignmentManager.DefenseMercenaryAssignment = (
			_defenseSceneManager.GetMercenaryAssignment(mercenaryKey)
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
			_:
				continue

		_deploymentInfoView.SetMercenary(cell, mercenaryData)


func _UpdateSelectedMercenaryTargetFocus() -> void:
	if _selectedMercenaryKey < 0:
		_deploymentGridView.ClearFocusedCell()
		return

	var assignment: DefenseMercenaryAssignmentManager.DefenseMercenaryAssignment = (
		_defenseSceneManager.GetMercenaryAssignment(_selectedMercenaryKey)
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
	for mercenaryKey: int in _startData.availableMercenaryKeys:
		_deploymentView.SetMercenaryAssigned(
			mercenaryKey,
			_defenseSceneManager.IsMercenaryAssigned(mercenaryKey),
		)


func _UpdateMercenarySummary() -> void:
	var heroAssigned: bool = false
	for mercenaryKey: int in _startData.availableMercenaryKeys:
		var data: MercenaryData = GameDataManager.GetMercenaryData(mercenaryKey)
		if data == null or not data.isHero:
			continue

		heroAssigned = _defenseSceneManager.IsMercenaryAssigned(mercenaryKey)
		break

	var cpAssigned: bool = _defenseSceneManager.GetCPMercenaryKey() >= 0
	_deploymentView.UpdateMercenaryInfo(
		heroAssigned,
		cpAssigned,
		_defenseSceneManager.CanConfirmMercenaryAssignment(),
	)

#endregion


#region Deployment Validation

func _CanPlaceCurrentSelectionAtCell(cell: Vector2i) -> bool:
	if not _CanInteractDeploymentCell(cell):
		return false

	match _defenseSceneManager.GetPhase():
		DefenseSceneManager.DefensePhase.UNIT_DEPLOYMENT:
			return (
				_selectedCharacterKey >= 0 and _selectedRecruitRatio > 0
				and _selectedRecruitRatio <= _defenseSceneManager.GetMaxRecruitRatioForCell(cell)
			)
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
			return _CanInteractUnitCell(cell)
		DefenseSceneManager.DefensePhase.INSTALLABLE_DEPLOYMENT:
			return _CanInteractInstallableCell(cell)
		DefenseSceneManager.DefensePhase.MERCENARY_ASSIGNMENT:
			return _CanInteractMercenaryTargetCell(cell)

	return false


func _CanInteractUnitCell(cell: Vector2i) -> bool:
	if cell == CP_CELL:
		return false

	if _defenseSceneManager.GetInstallableDeploymentByCell(cell) != null:
		return false

	if _defenseSceneManager.GetDeploymentByCell(cell) != null:
		return true

	return _CanPlaceStaticAtCell(cell)


func _CanInteractInstallableCell(cell: Vector2i) -> bool:
	if cell == CP_CELL:
		return false

	if _defenseSceneManager.GetInstallableDeploymentByCell(cell) != null:
		return true

	if _defenseSceneManager.GetDeploymentByCell(cell) != null:
		return false

	return _CanPlaceStaticAtCell(cell)


func _CanInteractMercenaryTargetCell(cell: Vector2i) -> bool:
	if cell == CP_CELL:
		return true

	return _defenseSceneManager.GetDeploymentByCell(cell) != null


func _CanPlaceStaticAtCell(cell: Vector2i) -> bool:
	var position: Vector2 = _deploymentGrid.CellToWorldCenter(cell)
	return _defenseSceneManager.CanPlaceStatic(position, DEPLOYMENT_UNIT_HALF_SIZE)

#endregion


#region Deployment UI

func _EnterCurrentPhaseUI() -> bool:
	match _defenseSceneManager.GetPhase():
		DefenseSceneManager.DefensePhase.UNIT_DEPLOYMENT:
			return _BeginUnitDeploymentUI()
		DefenseSceneManager.DefensePhase.INSTALLABLE_DEPLOYMENT:
			_BeginInstallableDeploymentUI()
			return true
		DefenseSceneManager.DefensePhase.MERCENARY_ASSIGNMENT:
			return _BeginMercenaryAssignmentUI()
		DefenseSceneManager.DefensePhase.BATTLE:
			_FinishDeploymentUI()
			return true

	return false


func _RefreshPlacementPreview() -> void:
	var previewTexture: Texture2D
	match _defenseSceneManager.GetPhase():
		DefenseSceneManager.DefensePhase.UNIT_DEPLOYMENT:
			if _selectedCharacterKey >= 0 and _selectedRecruitRatio > 0:
				previewTexture = _deploymentView.GetCharacterIconTexture(_selectedCharacterKey)
		DefenseSceneManager.DefensePhase.INSTALLABLE_DEPLOYMENT:
			if (
				_selectedCharacterKey >= 0
				and _defenseSceneManager.GetInstallableRemainingCount(_selectedCharacterKey) > 0
			):
				previewTexture = _deploymentView.GetCharacterIconTexture(_selectedCharacterKey)
		DefenseSceneManager.DefensePhase.MERCENARY_ASSIGNMENT:
			if _selectedMercenaryKey >= 0:
				previewTexture = _deploymentView.GetMercenaryIconTexture(_selectedMercenaryKey)

	_deploymentGridView.SetPlacementPreview(previewTexture)


func _FinishDeploymentUI() -> void:
	_deploymentView.HideView()
	_deploymentGridView.SetPlacementPreview(null)
	_deploymentGridView.visible = false
	_deploymentGridView.process_mode = Node.PROCESS_MODE_DISABLED

	_deploymentInfoView.Clear()
	_deploymentInfoView.visible = false

	_battleHUDView.ShowBattle()
	_UpdateBattleHUD()

#endregion


#region Battle Events

func _OnPauseButtonPressed() -> void:
	if _isBattlePaused:
		_defenseSceneManager.ResumeBattle()
		_isBattlePaused = false
	else:
		_defenseSceneManager.PauseBattle()
		_isBattlePaused = true

	_battleHUDView.SetPaused(_isBattlePaused)


func _OnDefenseFinished(result: DefenseResult) -> void:
	_isBattlePaused = false
	_battleHUDView.SetPaused(false)
	_battleHUDView.SetPauseDisabled(true)
	_battleHUDView.HideBattle()
	_resultView.ShowResult(result)

#endregion


#region Battle UI

func _UpdateBattleHUD() -> void:
	_battleHUDView.UpdateBattleTime(_defenseSceneManager.GetElapsedTimeMs())
	_battleHUDView.UpdateCP(
		_defenseSceneManager.GetCPCurrentHp(),
		_defenseSceneManager.GetCPMaxHp(),
		_defenseSceneManager.GetCPCurrentMp(),
		_defenseSceneManager.GetCPMaxMp(),
	)
	_battleHUDView.UpdatePopulation(
		_defenseSceneManager.GetRecruitedPopulation(),
		_defenseSceneManager.GetSurvivingPopulation(),
		_defenseSceneManager.GetDeadPopulation(),
	)

#endregion


#region Result Events

func _OnResultConfirmed(result: DefenseResult) -> void:
	DefenseFinished.emit(result)

#endregion
