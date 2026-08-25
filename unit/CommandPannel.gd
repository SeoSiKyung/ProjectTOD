class_name CommandPanel
extends CanvasLayer


@export var command_controller: CommandController
@export var select_controller: SelectController
@export var hide_without_selection: bool = true
@export var skill_slot: int = 0
@export var panel_width: float = 440.0
@export var panel_height: float = 72.0
@export var bottom_margin: float = 20.0
@export var button_minimum_size: Vector2 = Vector2(96.0, 48.0)


var _panel: PanelContainer
var _move_button: Button
var _stop_button: Button
var _attack_button: Button
var _skill_button: Button


func _ready() -> void:
	_resolve_controllers()
	_build_panel()
	_connect_signals()
	_refresh()


func _resolve_controllers() -> void:
	var parent: Node = get_parent()

	if parent == null:
		return

	if command_controller == null:
		var command_node: Node = parent.get_node_or_null(
			"CommandController"
		)

		if command_node is CommandController:
			command_controller = command_node as CommandController

	if select_controller == null:
		var select_node: Node = parent.get_node_or_null(
			"SelectController"
		)

		if select_node is SelectController:
			select_controller = select_node as SelectController


func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.name = "CommandPanelContainer"
	_panel.set_anchors_preset(
		Control.PRESET_CENTER_BOTTOM
	)
	_panel.offset_left = -panel_width * 0.5
	_panel.offset_top = -panel_height - bottom_margin
	_panel.offset_right = panel_width * 0.5
	_panel.offset_bottom = -bottom_margin
	add_child(
		_panel
	)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override(
		"margin_left",
		8
	)
	margin.add_theme_constant_override(
		"margin_top",
		8
	)
	margin.add_theme_constant_override(
		"margin_right",
		8
	)
	margin.add_theme_constant_override(
		"margin_bottom",
		8
	)
	_panel.add_child(
		margin
	)

	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(
		"separation",
		8
	)
	margin.add_child(
		row
	)

	_move_button = _create_button(
		"이동 [M]",
		true
	)
	_stop_button = _create_button(
		"정지 [S]",
		false
	)
	_attack_button = _create_button(
		"공격 [A]",
		true
	)
	_skill_button = _create_button(
		"스킬 [Q]",
		true
	)

	row.add_child(
		_move_button
	)
	row.add_child(
		_stop_button
	)
	row.add_child(
		_attack_button
	)
	row.add_child(
		_skill_button
	)

	_move_button.pressed.connect(
		_on_move_pressed
	)
	_stop_button.pressed.connect(
		_on_stop_pressed
	)
	_attack_button.pressed.connect(
		_on_attack_pressed
	)
	_skill_button.pressed.connect(
		_on_skill_pressed
	)


func _create_button(
	label: String,
	toggle: bool
) -> Button:
	var button: Button = Button.new()
	button.text = label
	button.custom_minimum_size = button_minimum_size
	button.toggle_mode = toggle
	button.focus_mode = Control.FOCUS_NONE
	return button


func _connect_signals() -> void:
	if command_controller != null:
		if not command_controller.command_mode_changed.is_connected(
			_on_command_mode_changed
		):
			command_controller.command_mode_changed.connect(
				_on_command_mode_changed
			)

	if select_controller != null:
		if not select_controller.selection_changed.is_connected(
			_on_selection_changed
		):
			select_controller.selection_changed.connect(
				_on_selection_changed
			)


func _on_move_pressed() -> void:
	if command_controller == null:
		return

	if command_controller.get_command_mode() == CommandController.CommandMode.MOVE:
		command_controller.cancel_targeting_command()
	else:
		command_controller.begin_move_command()

	_refresh()


func _on_stop_pressed() -> void:
	if command_controller == null:
		return

	command_controller.issue_stop_command()
	_refresh()


func _on_attack_pressed() -> void:
	if command_controller == null:
		return

	if command_controller.get_command_mode() == CommandController.CommandMode.ATTACK:
		command_controller.cancel_targeting_command()
	else:
		command_controller.begin_attack_command()

	_refresh()


func _on_skill_pressed() -> void:
	if command_controller == null:
		return

	if command_controller.get_command_mode() == CommandController.CommandMode.SKILL:
		command_controller.cancel_targeting_command()
	else:
		command_controller.begin_skill_command(
			skill_slot
		)

	_refresh()


func _on_command_mode_changed(
	_mode: int
) -> void:
	_refresh()


func _on_selection_changed(
	_selected_units: Variant
) -> void:
	_refresh()


func _refresh() -> void:
	if _panel == null:
		return

	var has_selection: bool = false

	if select_controller != null:
		has_selection = select_controller.HasFriendlySelection()

	_panel.visible = has_selection or not hide_without_selection
	_move_button.disabled = not has_selection
	_stop_button.disabled = not has_selection
	_attack_button.disabled = not has_selection
	_skill_button.disabled = not has_selection

	var mode: int = CommandController.CommandMode.SMART

	if command_controller != null:
		mode = command_controller.GetCommandMode()
	_move_button.button_pressed = mode == CommandController.CommandMode.MOVE
	_attack_button.button_pressed = mode == CommandController.CommandMode.ATTACK
	_skill_button.button_pressed = mode == CommandController.CommandMode.SKILL
