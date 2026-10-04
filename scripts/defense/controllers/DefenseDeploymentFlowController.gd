class_name DefenseDeploymentFlowController
extends RefCounted

signal DeploymentFinished

const DEPLOYMENT_CELL_SIZE: int = 128
const DEPLOYMENT_UNIT_HALF_SIZE: int = 16

const CP_CELL: Vector2i = Vector2i(4, 1)

var _defenseSceneManager: DefenseSceneManager
var _startData: DefenseStartData

var _cp: DefenseCP
var _deploymentGridView: DefenseDeploymentGridView
var _deploymentInfoView: DefenseDeploymentInfoView
var _deploymentView: DefenseDeploymentView

var _deploymentGrid: DefenseDeploymentGrid

var _unitDeploymentPhase: DefenseUnitDeploymentPhase
var _installableDeploymentPhase: DefenseInstallableDeploymentPhase
var _mercenaryAssignmentPhase: DefenseMercenaryAssignmentPhase


#region Lifecycle

func _init(
	defenseSceneManager: DefenseSceneManager,
	startData: DefenseStartData,
	cp: DefenseCP,
	deploymentGridView: DefenseDeploymentGridView,
	deploymentInfoView: DefenseDeploymentInfoView,
	deploymentView: DefenseDeploymentView,
) -> void:
	_defenseSceneManager = defenseSceneManager
	_startData = startData

	_cp = cp
	_deploymentGridView = deploymentGridView
	_deploymentInfoView = deploymentInfoView
	_deploymentView = deploymentView


func Start() -> bool:
	return _EnterCurrentPhaseUI()

#endregion


#region Initialize

func CreateDeploymentGrid() -> void:
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

	_cp.global_position = _deploymentGrid.CellToWorldCenter(CP_CELL)

	_unitDeploymentPhase = DefenseUnitDeploymentPhase.new(
		_defenseSceneManager,
		_startData,
		_deploymentGrid,
		_deploymentGridView,
		_deploymentInfoView,
		_deploymentView,
		CP_CELL,
		DEPLOYMENT_UNIT_HALF_SIZE,
	)

	_installableDeploymentPhase = DefenseInstallableDeploymentPhase.new(
		_defenseSceneManager,
		_startData,
		_deploymentGrid,
		_deploymentGridView,
		_deploymentInfoView,
		_deploymentView,
		CP_CELL,
		DEPLOYMENT_UNIT_HALF_SIZE,
	)

	_mercenaryAssignmentPhase = DefenseMercenaryAssignmentPhase.new(
		_defenseSceneManager,
		_startData,
		_deploymentGrid,
		_deploymentGridView,
		_deploymentInfoView,
		_deploymentView,
		CP_CELL,
		DEPLOYMENT_UNIT_HALF_SIZE,
	)


func InitializeGridView() -> void:
	_deploymentGridView.Initialize(
		_deploymentGrid,
		Callable(self, "_CanInteractDeploymentCell"),
		Callable(self, "_CanPlaceCurrentSelectionAtCell"),
	)

	_deploymentInfoView.Initialize(_deploymentGrid)

	_deploymentGridView.CellClicked.connect(_OnDeploymentCellClicked)
	_deploymentGridView.CellRightClicked.connect(_OnDeploymentCellRightClicked)


func ConnectSignals() -> void:
	_deploymentView.character_selected.connect(_OnCharacterButtonPressed)
	_deploymentView.character_drag_started.connect(_OnCharacterDragStarted)
	_deploymentView.recruit_ratio_changed.connect(_OnRecruitRatioChanged)

	_deploymentView.mercenary_selected.connect(_OnMercenaryButtonPressed)
	_deploymentView.mercenary_drag_started.connect(_OnMercenaryDragStarted)

	_deploymentView.back_pressed.connect(_OnDeploymentBackPressed)
	_deploymentView.confirm_pressed.connect(_OnConfirmDeploymentPressed)
	_deploymentView.drag_released.connect(_OnDeploymentDragReleased)

#endregion


#region Deployment Input

func _OnDeploymentCellClicked(cell: Vector2i) -> void:
	_TryPlaceCurrentSelectionAtCell(cell)


func _OnDeploymentCellRightClicked(cell: Vector2i) -> void:
	_RemoveCurrentPhaseAtCell(cell)


func _TryPlaceCurrentSelectionAtCell(cell: Vector2i) -> bool:
	if not _CanInteractDeploymentCell(cell):
		return false

	return _PlaceCurrentSelectionAtCell(cell)


func _PlaceCurrentSelectionAtCell(cell: Vector2i) -> bool:
	var phaseHandler: DefenseDeploymentPhaseHandler = _GetCurrentPhaseHandler()
	if phaseHandler == null:
		return false

	return phaseHandler.Place(cell)


func _RemoveCurrentPhaseAtCell(cell: Vector2i) -> void:
	var phaseHandler: DefenseDeploymentPhaseHandler = _GetCurrentPhaseHandler()
	if phaseHandler == null:
		return

	phaseHandler.Remove(cell)


func _RefreshPlacementPreview() -> void:
	var phaseHandler: DefenseDeploymentPhaseHandler = _GetCurrentPhaseHandler()
	if phaseHandler == null:
		return

	phaseHandler.RefreshPlacementPreview()

#endregion


#region Unit Deployment

func _OnCharacterButtonPressed(characterKey: int) -> void:
	var phaseHandler: DefenseDeploymentPhaseHandler = _GetCurrentPhaseHandler()
	if phaseHandler == null:
		return

	phaseHandler.OnCharacterSelected(characterKey)


func _OnRecruitRatioChanged(value: float) -> void:
	var phaseHandler: DefenseDeploymentPhaseHandler = _GetCurrentPhaseHandler()
	if phaseHandler == null:
		return

	phaseHandler.OnRecruitRatioChanged(value)


func _OnCharacterDragStarted(characterKey: int) -> void:
	var phaseHandler: DefenseDeploymentPhaseHandler = _GetCurrentPhaseHandler()
	if phaseHandler == null:
		return

	phaseHandler.OnCharacterDragStarted(characterKey)

#endregion


#region Mercenary Assignment

func _OnMercenaryButtonPressed(mercenaryKey: int) -> void:
	var phaseHandler: DefenseDeploymentPhaseHandler = _GetCurrentPhaseHandler()
	if phaseHandler == null:
		return

	phaseHandler.OnMercenarySelected(mercenaryKey)


func _OnMercenaryDragStarted(mercenaryKey: int) -> void:
	var phaseHandler: DefenseDeploymentPhaseHandler = _GetCurrentPhaseHandler()
	if phaseHandler == null:
		return

	phaseHandler.OnMercenaryDragStarted(mercenaryKey)

#endregion


#region Deployment Flow

func _OnDeploymentBackPressed() -> void:
	_deploymentView.StopDrag()

	if not _defenseSceneManager.ReturnToPreviousDeploymentPhase():
		return

	_deploymentGridView.ClearFocusedCell()
	_EnterCurrentPhaseUI()


func _OnConfirmDeploymentPressed() -> void:
	var phaseHandler: DefenseDeploymentPhaseHandler = _GetCurrentPhaseHandler()
	if phaseHandler == null:
		return

	if not phaseHandler.Confirm():
		return

	_EnterCurrentPhaseUI()


func _OnDeploymentDragReleased(viewportPosition: Vector2) -> void:
	if _deploymentView.IsPointInsideDock(viewportPosition):
		return

	var cell: Vector2i = _deploymentGrid.WorldToCell(
		_deploymentGridView.get_global_mouse_position()
	)

	_TryPlaceCurrentSelectionAtCell(cell)


func _EnterCurrentPhaseUI() -> bool:
	var phaseHandler: DefenseDeploymentPhaseHandler = _GetCurrentPhaseHandler()
	if phaseHandler != null:
		return phaseHandler.Enter()

	if _defenseSceneManager.GetPhase() == DefenseSceneManager.DefensePhase.BATTLE:
		_FinishDeploymentUI()
		return true

	return false


func _FinishDeploymentUI() -> void:
	_deploymentView.HideView()

	_deploymentGridView.SetPlacementPreview(null)
	_deploymentGridView.visible = false
	_deploymentGridView.process_mode = Node.PROCESS_MODE_DISABLED

	_deploymentInfoView.Clear()
	_deploymentInfoView.visible = false

	DeploymentFinished.emit()

#endregion


#region Validation

func _CanPlaceCurrentSelectionAtCell(cell: Vector2i) -> bool:
	var phaseHandler: DefenseDeploymentPhaseHandler = _GetCurrentPhaseHandler()
	if phaseHandler == null:
		return false

	return phaseHandler.CanPlace(cell)


func _CanInteractDeploymentCell(cell: Vector2i) -> bool:
	var phaseHandler: DefenseDeploymentPhaseHandler = _GetCurrentPhaseHandler()
	if phaseHandler == null:
		return false

	return phaseHandler.CanInteract(cell)

#endregion


func _GetCurrentPhaseHandler() -> DefenseDeploymentPhaseHandler:
	match _defenseSceneManager.GetPhase():
		DefenseSceneManager.DefensePhase.UNIT_DEPLOYMENT:
			return _unitDeploymentPhase
		DefenseSceneManager.DefensePhase.INSTALLABLE_DEPLOYMENT:
			return _installableDeploymentPhase
		DefenseSceneManager.DefensePhase.MERCENARY_ASSIGNMENT:
			return _mercenaryAssignmentPhase

	return null
