class_name EventPopup
extends Control

# =========================================================
# Signals
# =========================================================

signal ChoiceSelected(choiceId: StringName)

signal ContinueRequested

# =========================================================
# Resource
# =========================================================

const BASIC_BUTTON_SCENE: PackedScene = preload("res://ui/BasicButton.tscn")

# =========================================================
# Nodes
# =========================================================

@onready var _titleLabel: Label = (
	$CenterContainer/PanelContainer/MarginContainer/VBoxContainer/TitleLabel
)

@onready var _descriptionLabel: Label = (
	$CenterContainer/PanelContainer/MarginContainer/VBoxContainer/DescriptionLabel
)

@onready var _choicesContainer: VBoxContainer = (
	$CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ChoicesContainer
)

@onready var _resultLabel: Label = (
	$CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ResultLabel
)

@onready var _continueButton: BasicButton = (
	$CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ContinueButton
)

# =========================================================
# Lifecycle
# =========================================================


func _ready() -> void:
	visible = false

	_resultLabel.visible = false
	_continueButton.visible = false

	if not _continueButton.action_pressed.is_connected(_OnContinuePressed):
		_continueButton.action_pressed.connect(_OnContinuePressed)

# =========================================================
# Event 표시
# =========================================================


func ShowEvent(eventData: EventData) -> void:
	if eventData == null:
		return

	_ClearChoices()

	_titleLabel.text = eventData.displayName

	_descriptionLabel.text = (eventData.description)

	_resultLabel.text = ""
	_resultLabel.visible = false

	_choicesContainer.visible = true

	_continueButton.visible = false

	for choiceData in eventData.choices:
		_CreateChoiceButton(choiceData)

	visible = true

# =========================================================
# Result 표시
# =========================================================


func ShowResult(choiceData: EventChoiceData) -> void:
	if choiceData == null:
		return

	_choicesContainer.visible = false

	_resultLabel.text = (choiceData.resultText)

	_resultLabel.visible = true

	_continueButton.visible = true

# =========================================================
# Popup 닫기
# =========================================================


func Close() -> void:
	_ClearChoices()

	_titleLabel.text = ""
	_descriptionLabel.text = ""
	_resultLabel.text = ""

	_resultLabel.visible = false
	_choicesContainer.visible = true
	_continueButton.visible = false

	visible = false

# =========================================================
# Choice
# =========================================================


func _CreateChoiceButton(choiceData: EventChoiceData) -> void:
	if choiceData == null:
		return

	var choiceButton: BasicButton = (BASIC_BUTTON_SCENE.instantiate() as BasicButton)

	if choiceButton == null:
		push_error("EventPopup: BasicButton 생성 실패")

		return

	choiceButton.textKey = (choiceData.displayText)

	choiceButton.actionKey = (choiceData.id)

	choiceButton.action_pressed.connect(_OnChoicePressed)

	_choicesContainer.add_child(choiceButton)


func _ClearChoices() -> void:
	for child in _choicesContainer.get_children():
		child.queue_free()

# =========================================================
# Input
# =========================================================


func _OnChoicePressed(choiceId: StringName) -> void:
	ChoiceSelected.emit(choiceId)


func _OnContinuePressed(_actionKey: StringName) -> void:
	ContinueRequested.emit()
