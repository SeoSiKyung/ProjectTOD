class_name DefenseDeploymentDock
extends PanelContainer

signal recruit_ratio_changed(percent: float)
signal back_pressed
signal confirm_pressed

@onready var _buttonContainer: HBoxContainer = $ParchmentFrame/Margin/DockRow/ButtonScroll/ButtonContainer
@onready var _unitControls: VBoxContainer = $ParchmentFrame/Margin/DockRow/InfoColumn/UnitControls
@onready var _recruitRatioSpinBox: SpinBox = $ParchmentFrame/Margin/DockRow/InfoColumn/UnitControls/RecruitRatio/RecruitRatioSpinBox
@onready var _recruitRatioSlider: HSlider = $ParchmentFrame/Margin/DockRow/InfoColumn/UnitControls/RecruitRatio/RecruitRatioSlider
@onready var _recruitPopulationLabel: Label = $ParchmentFrame/Margin/DockRow/InfoColumn/UnitControls/RecruitPopulationLabel
@onready var _hintLabel: Label = $ParchmentFrame/Margin/DockRow/InfoColumn/HintLabel
@onready var _statusLabel: Label = $ParchmentFrame/Margin/DockRow/InfoColumn/StatusLabel
@onready var _backButton: BasicButton = $ParchmentFrame/Margin/DockRow/ActionColumn/BackSlot/BackButton
@onready var _confirmButton: BasicButton = $ParchmentFrame/Margin/DockRow/ActionColumn/ConfirmButton


func _ready() -> void:
	_recruitRatioSpinBox.value_changed.connect(_OnRecruitRatioSpinBoxChanged)
	_recruitRatioSlider.value_changed.connect(_OnRecruitRatioSliderChanged)
	_backButton.pressed.connect(_OnBackPressed)
	_confirmButton.pressed.connect(_OnConfirmPressed)


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
	_statusLabel.visible = not text.is_empty()


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
