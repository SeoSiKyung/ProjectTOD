class_name DefenseDeploymentDock
extends PanelContainer

signal recruit_ratio_changed(percent: float)
signal back_pressed
signal confirm_pressed

@onready var _buttonContainer: HBoxContainer = $ParchmentPanel/DockRow/ButtonScroll/ButtonContainer
@onready var _unitControls: VBoxContainer = $ParchmentPanel/DockRow/InfoColumn/UnitControls
@onready var _recruitRatioSpinBox: SpinBox = $ParchmentPanel/DockRow/InfoColumn/UnitControls/RecruitRatio/RecruitRatioSpinBox
@onready var _recruitRatioSlider: HSlider = $ParchmentPanel/DockRow/InfoColumn/UnitControls/RecruitRatio/RecruitRatioSlider
@onready var _recruitPopulationLabel: Label = $ParchmentPanel/DockRow/InfoColumn/UnitControls/RecruitPopulationLabel
@onready var _hintLabel: Label = $ParchmentPanel/DockRow/InfoColumn/HintLabel
@onready var _statusPanel: PanelContainer = $ParchmentPanel/DockRow/InfoColumn/StatusPanel
@onready var _statusLabel: Label = $ParchmentPanel/DockRow/InfoColumn/StatusPanel/StatusLabel
@onready var _backButton: BasicButton = $ParchmentPanel/DockRow/ActionColumn/BackSlot/BackButton
@onready var _confirmButton: BasicButton = $ParchmentPanel/DockRow/ActionColumn/ConfirmButton


func _ready() -> void:
	_StyleRecruitRatioInput()
	_recruitRatioSpinBox.value_changed.connect(_OnRecruitRatioSpinBoxChanged)
	_recruitRatioSlider.value_changed.connect(_OnRecruitRatioSliderChanged)
	_backButton.pressed.connect(_OnBackPressed)
	_confirmButton.pressed.connect(_OnConfirmPressed)


func _StyleRecruitRatioInput() -> void:
	var lineEdit: LineEdit = _recruitRatioSpinBox.get_line_edit()
	lineEdit.add_theme_color_override("font_color", Color(0.22745098, 0.12941177, 0.05882353, 1.0))
	lineEdit.add_theme_color_override("caret_color", Color(0.32156864, 0.22745098, 0.13333334, 1.0))
	lineEdit.add_theme_font_size_override("font_size", 18)

	var normalStyle: StyleBoxFlat = StyleBoxFlat.new()
	normalStyle.bg_color = Color(0.82, 0.72, 0.54, 0.34)
	normalStyle.border_color = Color(0.42, 0.29, 0.15, 0.55)
	normalStyle.border_width_left = 1
	normalStyle.border_width_top = 1
	normalStyle.border_width_right = 1
	normalStyle.border_width_bottom = 1
	normalStyle.corner_radius_top_left = 3
	normalStyle.corner_radius_top_right = 3
	normalStyle.corner_radius_bottom_right = 3
	normalStyle.corner_radius_bottom_left = 3

	var focusStyle: StyleBoxFlat = StyleBoxFlat.new()
	focusStyle.bg_color = Color(0.88, 0.78, 0.58, 0.42)
	focusStyle.border_color = Color(0.72, 0.52, 0.20, 0.88)
	focusStyle.border_width_left = 2
	focusStyle.border_width_top = 2
	focusStyle.border_width_right = 2
	focusStyle.border_width_bottom = 2
	focusStyle.corner_radius_top_left = 3
	focusStyle.corner_radius_top_right = 3
	focusStyle.corner_radius_bottom_right = 3
	focusStyle.corner_radius_bottom_left = 3

	lineEdit.add_theme_stylebox_override("normal", normalStyle)
	lineEdit.add_theme_stylebox_override("focus", focusStyle)


func GetButtonContainer() -> HBoxContainer:
	return _buttonContainer


func SetUnitControlsVisible(isVisible: bool) -> void:
	_unitControls.visible = isVisible


func SetRecruitRatioValue(percent: int) -> void:
	_recruitRatioSpinBox.set_value_no_signal(percent)
	_recruitRatioSlider.set_value_no_signal(percent)


func SetRecruitRatioMax(maxPercent: int) -> void:
	var clampedMax: int = maxi(maxPercent, 0)
	_recruitRatioSpinBox.max_value = clampedMax
	_recruitRatioSlider.max_value = clampedMax

	if _recruitRatioSpinBox.value > clampedMax:
		SetRecruitRatioValue(clampedMax)


func SetRecruitPopulation(population: int) -> void:
	_recruitPopulationLabel.text = "배치 인구: %d명" % population


func SetHintText(text: String) -> void:
	_hintLabel.text = text


func SetStatusText(text: String) -> void:
	_statusLabel.text = text
	_statusPanel.visible = not text.is_empty()


func SetConfirmText(text: String) -> void:
	_confirmButton.textKey = text


func SetBackButtonVisible(isVisible: bool) -> void:
	_backButton.visible = isVisible


func SetConfirmDisabled(isDisabled: bool) -> void:
	_confirmButton.SetDisabled(isDisabled)


func _OnRecruitRatioSpinBoxChanged(value: float) -> void:
	_recruitRatioSlider.set_value_no_signal(value)
	recruit_ratio_changed.emit(value)


func _OnRecruitRatioSliderChanged(value: float) -> void:
	_recruitRatioSpinBox.set_value_no_signal(value)
	recruit_ratio_changed.emit(value)


func _OnBackPressed() -> void:
	back_pressed.emit()


func _OnConfirmPressed() -> void:
	confirm_pressed.emit()
