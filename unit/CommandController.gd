class_name CommandController
extends Node

@export var movement_controller: MovementController
@export var select_controller: SelectController
@export var move_click_effect_scene: PackedScene


func _ready() -> void:
	var parent: Node = get_parent()

	if parent == null:
		return

	if movement_controller == null:
		var movement_node: Node = parent.get_node_or_null("MovementController")

		if movement_node is MovementController:
			movement_controller = movement_node as MovementController

	if select_controller == null:
		var select_node: Node = parent.get_node_or_null("SelectController")

		if select_node is SelectController:
			select_controller = select_node as SelectController


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		_handleKeyInput(event as InputEventKey)
		return

	if event is InputEventMouseButton:
		_handleMouseInput(event as InputEventMouseButton)


func IssueSmartCommandAt(target_world: Vector2) -> bool:
	if select_controller == null:
		return false

	var clicked_unit: Unit = (select_controller.GetUnitAtWorldPosition(target_world))

	if clicked_unit != null:
		return false

	return IssueMoveCommand(target_world) >= 0


func IssueMoveCommand(target_world: Vector2) -> int:
	if movement_controller == null:
		return -1

	var order_id: int = (movement_controller.IssueSelectedMoveOrder(target_world))

	if order_id >= 0:
		_showMoveClickEffect(target_world)

	return order_id


func IssueStopCommand() -> int:
	if movement_controller == null:
		return -1

	return movement_controller.IssueSelectedStopOrder()


func _handleKeyInput(key_event: InputEventKey) -> void:
	if not key_event.pressed:
		return

	if key_event.echo:
		return

	if not _isStopKey(key_event):
		return

	if IssueStopCommand() < 0:
		return

	get_viewport().set_input_as_handled()


func _handleMouseInput(mouse_event: InputEventMouseButton) -> void:
	if mouse_event.button_index != MOUSE_BUTTON_RIGHT:
		return

	if not mouse_event.pressed:
		return

	var target_world: Vector2 = _screenToWorld(mouse_event.position)

	if not IssueSmartCommandAt(target_world):
		return

	get_viewport().set_input_as_handled()


func _isStopKey(event: InputEventKey) -> bool:
	return (event.keycode == KEY_S or event.physical_keycode == KEY_S)


func _showMoveClickEffect(target_world: Vector2) -> void:
	if move_click_effect_scene == null:
		return

	var node: Node = move_click_effect_scene.instantiate()

	if not node is Node2D:
		node.queue_free()
		return

	var effect: Node2D = node as Node2D
	var scene: Node = get_tree().current_scene

	if scene == null:
		effect.queue_free()
		return

	scene.add_child(effect)

	effect.global_position = target_world


func _screenToWorld(screen_position: Vector2) -> Vector2:
	return (get_viewport().get_canvas_transform().affine_inverse() * screen_position)
