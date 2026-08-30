class_name CommandPanel
extends CanvasLayer

@export var commandController: CommandController
@export var selectController: SelectController
@export var hideWithoutSelection: bool = true
@export var skillSlot: int = 0
@export var panelWidth: float = 440.0
@export var panelHeight: float = 72.0
@export var bottomMargin: float = 20.0
@export var buttonMinimumSize: Vector2 = Vector2(96.0, 48.0)

var _panel: PanelContainer
var _moveButton: Button
var _stopButton: Button
var _attackButton: Button
var _skillButton: Button


func _ready() -> void:
	_ResolveControllers()
	_BuildPanel()
	_ConnectSignals()
	_Refresh()


func _ResolveControllers() -> void:
	var parent: Node = get_parent()

	if parent == null:
		return

	if commandController == null:
		var commandNode: Node = parent.get_node_or_null("CommandController")

		if commandNode is CommandController:
			commandController = commandNode as CommandController

	if selectController == null:
		var selectNode: Node = parent.get_node_or_null("SelectController")

		if selectNode is SelectController:
			selectController = selectNode as SelectController


func _BuildPanel() -> void:
	_panel = PanelContainer.new()
	_panel.name = "CommandPanelContainer"
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.offset_left = -panelWidth * 0.5
	_panel.offset_top = -panelHeight - bottomMargin
	_panel.offset_right = panelWidth * 0.5
	_panel.offset_bottom = -bottomMargin
	add_child(_panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_panel.add_child(margin)

	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)

	_moveButton = _CreateButton("이동 [M]", true)
	_stopButton = _CreateButton("정지 [S]", false)
	_attackButton = _CreateButton("공격 [A]", true)
	_skillButton = _CreateButton("스킬 [Q]", true)

	row.add_child(_moveButton)
	row.add_child(_stopButton)
	row.add_child(_attackButton)
	row.add_child(_skillButton)

	_moveButton.pressed.connect(_OnMovePressed)
	_stopButton.pressed.connect(_OnStopPressed)
	_attackButton.pressed.connect(_OnAttackPressed)
	_skillButton.pressed.connect(_OnSkillPressed)


func _CreateButton(label: String, toggle: bool) -> Button:
	var button: Button = Button.new()
	button.text = label
	button.custom_minimum_size = buttonMinimumSize
	button.toggle_mode = toggle
	button.focus_mode = Control.FOCUS_NONE
	return button


func _ConnectSignals() -> void:
	if commandController != null:
		if not commandController.commandModeChanged.is_connected(_OnCommandModeChanged):
			commandController.commandModeChanged.connect(_OnCommandModeChanged)

	if selectController != null:
		if not selectController.selection_changed.is_connected(_OnSelectionChanged):
			selectController.selection_changed.connect(_OnSelectionChanged)


func _OnMovePressed() -> void:
	if commandController == null:
		return

	if commandController.GetCommandMode() == CommandController.CommandMode.MOVE:
		commandController.CancelTargetingCommand()
	else:
		commandController.BeginMoveCommand()

	_Refresh()


func _OnStopPressed() -> void:
	if commandController == null:
		return

	commandController.IssueStopCommand()
	_Refresh()


func _OnAttackPressed() -> void:
	if commandController == null:
		return

	if commandController.GetCommandMode() == CommandController.CommandMode.ATTACK:
		commandController.CancelTargetingCommand()
	else:
		commandController.BeginAttackCommand()

	_Refresh()


func _OnSkillPressed() -> void:
	if commandController == null:
		return

	if commandController.GetCommandMode() == CommandController.CommandMode.SKILL:
		commandController.CancelTargetingCommand()
	else:
		commandController.BeginSkillCommand(skillSlot)

	_Refresh()


func _OnCommandModeChanged(_mode: int) -> void:
	_Refresh()


func _OnSelectionChanged(_selectedUnits: Variant) -> void:
	_Refresh()


func _Refresh() -> void:
	if _panel == null:
		return

	var hasSelection: bool = false

	if selectController != null:
		hasSelection = selectController.HasFriendlySelection()

	_panel.visible = hasSelection or not hideWithoutSelection
	_moveButton.disabled = not hasSelection
	_stopButton.disabled = not hasSelection
	_attackButton.disabled = not hasSelection
	_skillButton.disabled = not hasSelection

	var mode: int = CommandController.CommandMode.SMART

	if commandController != null:
		mode = commandController.GetCommandMode()

	_moveButton.button_pressed = mode == CommandController.CommandMode.MOVE
	_attackButton.button_pressed = mode == CommandController.CommandMode.ATTACK
	_skillButton.button_pressed = mode == CommandController.CommandMode.SKILL
