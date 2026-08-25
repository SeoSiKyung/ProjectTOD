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
		var command_node: Node = parent.get_node_or_null("CommandController")

		if command_node is CommandController:
			commandController = command_node as CommandController

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

	_moveButton = _createButton("이동 [M]", true)
	_stopButton = _createButton("정지 [S]", false)
	_attackButton = _createButton("공격 [A]", true)
	_skillButton = _createButton("스킬 [Q]", true)

	row.add_child(_moveButton)
	row.add_child(_stopButton)
	row.add_child(_attackButton)
	row.add_child(_skillButton)

	_moveButton.pressed.connect(_OnMovePressed)
	_stopButton.pressed.connect(_OnStopPressed)
	_attackButton.pressed.connect(_OnAttackPressed)
	_skillButton.pressed.connect(_OnSkillPressed)


func _createButton(label: String, toggle: bool) -> Button:
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

	if commandController.get_command_mode() == CommandController.CommandMode.MOVE:
		commandController.cancel_targeting_command()
	else:
		commandController.begin_move_command()

	_Refresh()


func _OnStopPressed() -> void:
	if commandController == null:
		return

	commandController.issue_stop_command()
	_Refresh()


func _OnAttackPressed() -> void:
	if commandController == null:
		return

	if commandController.get_command_mode() == CommandController.CommandMode.ATTACK:
		commandController.cancel_targeting_command()
	else:
		commandController.begin_attack_command()

	_Refresh()


func _OnSkillPressed() -> void:
	if commandController == null:
		return

	if commandController.get_command_mode() == CommandController.CommandMode.SKILL:
		commandController.cancel_targeting_command()
	else:
		commandController.begin_skill_command(skillSlot)

	_Refresh()


func _OnCommandModeChanged(_mode: int) -> void:
	_Refresh()


func _OnSelectionChanged(_selected_units: Variant) -> void:
	_Refresh()


func _Refresh() -> void:
	if _panel == null:
		return

	var has_selection: bool = false

	if selectController != null:
		has_selection = selectController.HasFriendlySelection()

	_panel.visible = has_selection or not hideWithoutSelection
	_moveButton.disabled = not has_selection
	_stopButton.disabled = not has_selection
	_attackButton.disabled = not has_selection
	_skillButton.disabled = not has_selection

	var mode: int = CommandController.CommandMode.SMART

	if commandController != null:
		mode = commandController.GetCommandMode()
	_moveButton.button_pressed = mode == CommandController.CommandMode.MOVE
	_attackButton.button_pressed = mode == CommandController.CommandMode.ATTACK
	_skillButton.button_pressed = mode == CommandController.CommandMode.SKILL
