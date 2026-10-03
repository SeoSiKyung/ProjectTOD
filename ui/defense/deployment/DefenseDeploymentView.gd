class_name DefenseDeploymentView
extends Control

signal character_selected(characterKey: int)
signal character_drag_started(characterKey: int)
signal mercenary_selected(mercenaryKey: int)
signal mercenary_drag_started(mercenaryKey: int)
signal recruit_ratio_changed(percent: float)
signal back_pressed
signal confirm_pressed
signal drag_released(viewportPosition: Vector2)

const DRAG_PREVIEW_SIZE: Vector2 = Vector2(72, 72)
const DEFENSE_CHARACTER_BUTTON_SCENE: PackedScene = preload(
	"res://ui/defense/deployment/DefenseCharacterButton.tscn"
)
const DEFENSE_MERCENARY_BUTTON_SCENE: PackedScene = preload(
	"res://ui/defense/deployment/DefenseMercenaryButton.tscn"
)

@onready var _deploymentDock: DefenseDeploymentDock = $DeploymentDock
@onready var _selectionButtonContainer: HBoxContainer = _deploymentDock.GetButtonContainer()
@onready var _phaseLabel: Label = $DeploymentHUD/HUDContainer/PhaseLabel
@onready var _recruitSummaryLabel: Label = $DeploymentHUD/HUDContainer/RecruitSummaryLabel
@onready var _stepLabel: Label = $DeploymentHUD/HUDContainer/StepLabel

var _characterButtonGroup: ButtonGroup = ButtonGroup.new()
var _characterButtonByKey: Dictionary[int, DefenseCharacterButton] = { }
var _mercenaryButtonByKey: Dictionary[int, DefenseMercenaryButton] = { }

var _isDragActive: bool = false
var _dragPreview: TextureRect


func _ready() -> void:
	_characterButtonGroup.allow_unpress = false

	_deploymentDock.recruit_ratio_changed.connect(_OnRecruitRatioChanged)
	_deploymentDock.back_pressed.connect(_OnBackPressed)
	_deploymentDock.confirm_pressed.connect(_OnConfirmPressed)

	set_process(false)
	set_process_input(false)


func _process(_delta: float) -> void:
	_UpdateDragPreviewPosition()


func _input(event: InputEvent) -> void:
	if not _isDragActive:
		return

	if event.is_action_pressed("ui_cancel"):
		StopDrag()
		return

	if event is not InputEventMouseButton:
		return

	var mouseEvent: InputEventMouseButton = event
	if mouseEvent.button_index != MOUSE_BUTTON_LEFT or mouseEvent.pressed:
		return

	drag_released.emit(mouseEvent.position)
	StopDrag()


func ConfigureUnitPhase(maxRecruitPercent: int, recruitPercent: int) -> void:
	_SetPhaseHeader("병력 배치", "1 / 3")
	_ConfigureDock(true, false, "다음: 병기/함정", "병과 선택 → 병력 설정 → 셀 클릭/드래그\n우클릭: 회수")
	_deploymentDock.SetRecruitRatioMax(maxRecruitPercent)
	_deploymentDock.SetRecruitRatioValue(recruitPercent)


func ConfigureInstallablePhase() -> void:
	_SetPhaseHeader("병기 · 함정 배치", "2 / 3")
	_ConfigureDock(false, true, "다음: 용병", "병기/함정 선택 → 셀 클릭/드래그\n우클릭: 회수")
	_deploymentDock.SetConfirmDisabled(false)


func ConfigureMercenaryPhase() -> void:
	_SetPhaseHeader("용병 배치", "3 / 3")
	_ConfigureDock(false, true, "전투 시작", "용병 선택 → 부대/지휘소 클릭/드래그\n우클릭: 배치 해제")


func UpdateUnitInfo(
	totalRecruitPercent: int,
	maxRecruitPercent: int,
	recruitedPopulation: int,
	totalPopulation: int,
	selectedRecruitPercent: int,
	selectedPopulation: int,
	remainingRecruitPercent: int,
) -> void:
	_recruitSummaryLabel.text = "징집: %d%% / %d%%  (%d명 / %d명)" % [
		totalRecruitPercent,
		maxRecruitPercent,
		recruitedPopulation,
		totalPopulation,
	]
	_deploymentDock.SetRecruitPopulation(selectedPopulation)
	_deploymentDock.SetStatusText(
		"현재 %d%% · %d명    남은 징집률 %d%%"
		% [selectedRecruitPercent, selectedPopulation, remainingRecruitPercent]
	)
	_deploymentDock.SetConfirmDisabled(recruitedPopulation <= 0)


func UpdateInstallableInfo(machineCount: int, trapCount: int) -> void:
	_recruitSummaryLabel.text = "병기: %d개 / 함정: %d개" % [machineCount, trapCount]
	_deploymentDock.SetStatusText("현재 배치 · 병기 %d개 · 함정 %d개" % [machineCount, trapCount])


func UpdateMercenaryInfo(heroAssigned: bool, cpAssigned: bool, canConfirm: bool) -> void:
	var heroText: String = "완료" if heroAssigned else "미배치"
	var cpText: String = "완료" if cpAssigned else "미배치"
	_recruitSummaryLabel.text = "주인공: %s    지휘소: %s" % [heroText, cpText]
	_deploymentDock.SetStatusText("주인공 %s    지휘소 %s" % [heroText, cpText])
	_deploymentDock.SetConfirmDisabled(not canConfirm)


func SetCharacterButtons(
	characterDataList: Array[CharacterData],
	preferredCharacterKey: int = -1,
) -> int:
	_ClearSelectionButtons()

	if characterDataList.is_empty():
		return -1

	for characterData: CharacterData in characterDataList:
		var characterButton: DefenseCharacterButton = DEFENSE_CHARACTER_BUTTON_SCENE.instantiate()
		_selectionButtonContainer.add_child(characterButton)
		characterButton.Initialize(characterData)
		characterButton.button_group = _characterButtonGroup
		characterButton.pressed.connect(_OnCharacterButtonPressed.bind(characterData.characterKey))
		characterButton.drag_started.connect(_OnCharacterDragStarted)

		_characterButtonByKey[characterData.characterKey] = characterButton

	var selectedKey: int = preferredCharacterKey
	if not _characterButtonByKey.has(selectedKey):
		selectedKey = characterDataList[0].characterKey

	var selectedButton: DefenseCharacterButton = _characterButtonByKey.get(selectedKey)
	if selectedButton != null:
		selectedButton.SetSelected(true)

	return selectedKey


func SetMercenaryButtons(
	availableMercenaryKeys: Array[int],
	preferredMercenaryKey: int = -1,
) -> int:
	_ClearSelectionButtons()

	if availableMercenaryKeys.is_empty():
		push_error("DefenseDeploymentView: 배치 가능한 용병이 없습니다.")
		return -1

	for mercenaryKey: int in availableMercenaryKeys:
		var mercenaryData: MercenaryData = GameDataManager.GetMercenaryData(mercenaryKey)
		if mercenaryData == null:
			push_error("DefenseDeploymentView: MercenaryData가 없습니다. key: " + str(mercenaryKey))
			return -1

		var button: DefenseMercenaryButton = DEFENSE_MERCENARY_BUTTON_SCENE.instantiate()
		_selectionButtonContainer.add_child(button)
		button.Initialize(mercenaryData, GameDataManager.GetMercenaryBuffData(mercenaryKey))
		button.SetButtonGroup(_characterButtonGroup)
		button.selected.connect(_OnMercenaryButtonPressed.bind(mercenaryKey))
		button.drag_started.connect(_OnMercenaryDragStarted)

		_mercenaryButtonByKey[mercenaryKey] = button

	var selectedKey: int = preferredMercenaryKey
	if not _mercenaryButtonByKey.has(selectedKey):
		selectedKey = availableMercenaryKeys[0]

	var selectedButton: DefenseMercenaryButton = _mercenaryButtonByKey.get(selectedKey)
	if selectedButton == null:
		return -1

	selectedButton.SetSelected(true)
	return selectedKey


func UpdateInstallableButtonStates(
	remainingCountByCharacterKey: Dictionary[int, int],
	selectedCharacterKey: int,
) -> int:
	var firstAvailableKey: int = -1

	for characterKey: int in _characterButtonByKey:
		var button: DefenseCharacterButton = _characterButtonByKey.get(characterKey)
		if button == null:
			continue

		var remainingCount: int = remainingCountByCharacterKey.get(characterKey, 0)
		button.ShowRemainingCount(remainingCount)
		button.SetDisabled(remainingCount <= 0)

		if remainingCount > 0 and firstAvailableKey < 0:
			firstAvailableKey = characterKey

	if (
		_characterButtonByKey.has(selectedCharacterKey)
		and remainingCountByCharacterKey.get(selectedCharacterKey, 0) > 0
	):
		return selectedCharacterKey

	var previousButton: DefenseCharacterButton = _characterButtonByKey.get(selectedCharacterKey)
	if previousButton != null:
		previousButton.SetSelected(false)

	if firstAvailableKey < 0:
		return -1

	var nextButton: DefenseCharacterButton = _characterButtonByKey.get(firstAvailableKey)
	if nextButton != null:
		nextButton.SetSelected(true)

	return firstAvailableKey


func SetMercenaryAssigned(mercenaryKey: int, isAssigned: bool) -> void:
	var button: DefenseMercenaryButton = _mercenaryButtonByKey.get(mercenaryKey)
	if button == null:
		return

	button.SetAssigned(isAssigned)


func GetCharacterIconTexture(characterKey: int) -> Texture2D:
	var button: DefenseCharacterButton = _characterButtonByKey.get(characterKey)
	if button == null:
		return null

	return button.GetIconTexture()


func GetMercenaryIconTexture(mercenaryKey: int) -> Texture2D:
	var button: DefenseMercenaryButton = _mercenaryButtonByKey.get(mercenaryKey)
	if button == null:
		return null

	return button.GetIconTexture()


func SetStatusText(text: String) -> void:
	_deploymentDock.SetStatusText(text)


func IsPointInsideDock(viewportPosition: Vector2) -> bool:
	return _deploymentDock.get_global_rect().has_point(viewportPosition)


func StartDrag(previewTexture: Texture2D) -> void:
	if previewTexture == null:
		return

	_isDragActive = true
	set_process(true)
	set_process_input(true)

	if _dragPreview == null:
		_dragPreview = TextureRect.new()
		_dragPreview.custom_minimum_size = DRAG_PREVIEW_SIZE
		_dragPreview.size = DRAG_PREVIEW_SIZE
		_dragPreview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_dragPreview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_dragPreview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_dragPreview.modulate = Color(1.0, 1.0, 1.0, 0.82)
		_dragPreview.z_index = 100
		add_child(_dragPreview)

	_dragPreview.texture = previewTexture
	_dragPreview.visible = true
	_UpdateDragPreviewPosition()


func StopDrag() -> void:
	_isDragActive = false
	set_process(false)
	set_process_input(false)

	if _dragPreview != null:
		_dragPreview.visible = false


func HideView() -> void:
	StopDrag()
	visible = false


func ShowView() -> void:
	visible = true


func _SetPhaseHeader(title: String, stepText: String) -> void:
	_phaseLabel.text = title
	_stepLabel.text = stepText


func _ConfigureDock(
	showUnitControls: bool,
	showBackButton: bool,
	confirmText: String,
	hintText: String,
) -> void:
	_deploymentDock.SetUnitControlsVisible(showUnitControls)
	_deploymentDock.SetBackButtonVisible(showBackButton)
	_deploymentDock.SetConfirmText(confirmText)
	_deploymentDock.SetHintText(hintText)


func _ClearSelectionButtons() -> void:
	for child: Node in _selectionButtonContainer.get_children():
		child.queue_free()

	_characterButtonByKey.clear()
	_mercenaryButtonByKey.clear()

	_characterButtonGroup = ButtonGroup.new()
	_characterButtonGroup.allow_unpress = false


func _UpdateDragPreviewPosition() -> void:
	if _dragPreview == null:
		return

	_dragPreview.position = get_viewport().get_mouse_position() - DRAG_PREVIEW_SIZE * 0.5


func _OnCharacterButtonPressed(characterKey: int) -> void:
	character_selected.emit(characterKey)


func _OnCharacterDragStarted(characterKey: int, previewTexture: Texture2D) -> void:
	StartDrag(previewTexture)
	character_drag_started.emit(characterKey)


func _OnMercenaryButtonPressed(mercenaryKey: int) -> void:
	mercenary_selected.emit(mercenaryKey)


func _OnMercenaryDragStarted(mercenaryKey: int, previewTexture: Texture2D) -> void:
	StartDrag(previewTexture)
	mercenary_drag_started.emit(mercenaryKey)


func _OnRecruitRatioChanged(percent: float) -> void:
	recruit_ratio_changed.emit(percent)


func _OnBackPressed() -> void:
	back_pressed.emit()


func _OnConfirmPressed() -> void:
	confirm_pressed.emit()
