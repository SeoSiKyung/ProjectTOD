class_name SelectController
extends Node2D


signal selection_changed(selected_units)


@export var drag_threshold: float = 6.0
@export var selection_fill_color: Color = Color(0.2, 0.8, 0.3, 0.12)
@export var selection_border_color: Color = Color(0.3, 1.0, 0.4, 0.95)
@export var selection_border_width: float = 2.0
@export var friendly_select_color: Color = Color(0.2, 1.0, 0.2, 1.0)
@export var enemy_select_color: Color = Color(1.0, 0.2, 0.2, 1.0)
@export var command_controller: Node


var _selected_units: Array[Unit] = []
var _control_groups: Dictionary = {}

var _left_pressed: bool = false
var _drag_active: bool = false
var _additive_selection: bool = false

var _drag_start_world: Vector2 = Vector2.ZERO
var _drag_current_world: Vector2 = Vector2.ZERO


func _ready() -> void:
	if command_controller == null:
		var parent: Node = get_parent()

		if parent != null:
			command_controller = parent.get_node_or_null(
				"CommandController"
			)

	get_tree().node_added.connect(_onNodeAdded)
	call_deferred("_initializeUnits")


func _unhandled_input(event: InputEvent) -> void:
	if _commandTargetingActive():
		if event is InputEventMouseButton or event is InputEventMouseMotion:
			_left_pressed = false
			_drag_active = false
			_additive_selection = false
			queue_redraw()
			return

	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey

		if not key_event.pressed:
			return

		if key_event.echo:
			return

		var slot: int = _getControlGroupSlot(
			key_event
		)

		if slot > 0:
			if key_event.ctrl_pressed:
				_assignControlGroup(
					slot
				)
			else:
				_selectControlGroup(
					slot
				)

			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton

		if mouse_event.button_index != MOUSE_BUTTON_LEFT:
			return

		var world_position: Vector2 = _screenToWorld(
			mouse_event.position
		)

		if mouse_event.pressed:
			_left_pressed = true
			_drag_active = false
			_additive_selection = mouse_event.ctrl_pressed
			_drag_start_world = world_position
			_drag_current_world = world_position

			queue_redraw()
			get_viewport().set_input_as_handled()
			return

		if not _left_pressed:
			return

		_drag_current_world = world_position

		if _drag_active:
			_handleDragSelection(
				_additive_selection
			)
		else:
			_handleClickSelection(
				_drag_start_world,
				_additive_selection
			)

		_left_pressed = false
		_drag_active = false
		_additive_selection = false

		queue_redraw()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion:
		if not _left_pressed:
			return

		var motion_event: InputEventMouseMotion = event as InputEventMouseMotion

		_drag_current_world = _screenToWorld(
			motion_event.position
		)

		if (
			_drag_start_world.distance_to(
				_drag_current_world
			)
			>= drag_threshold
		):
			_drag_active = true

		queue_redraw()
		get_viewport().set_input_as_handled()


func _commandTargetingActive() -> bool:
	if command_controller == null:
		return false

	if not command_controller.has_method(
		"is_targeting_command"
	):
		return false

	return bool(
		command_controller.call(
			"is_targeting_command"
		)
	)


func GetSelectedUnits() -> Array[Unit]:
	var result: Array[Unit] = []
	var valid_units: Array[Unit] = []

	for unit: Unit in _selected_units:
		if not is_instance_valid(unit):
			continue

		if not unit.is_inside_tree():
			continue

		valid_units.append(unit)
		result.append(unit)

	_selected_units = valid_units

	return result


func GetSelectedFriendlyUnits() -> Array[Unit]:
	var result: Array[Unit] = []

	for unit: Unit in GetSelectedUnits():
		if not unit.player_controllable:
			continue

		result.append(unit)

	return result


func HasFriendlySelection() -> bool:
	return not GetSelectedFriendlyUnits().is_empty()


func GetControlGroupUnits(
	slot: int
) -> Array[Unit]:
	if slot < 1 or slot > 9:
		return []

	if not _control_groups.has(slot):
		return []

	var stored_units: Array = _control_groups[slot]
	var valid_units: Array[Unit] = []

	for value: Variant in stored_units:
		if not value is Unit:
			continue

		var unit: Unit = value as Unit

		if not is_instance_valid(unit):
			continue

		if not unit.is_inside_tree():
			continue

		valid_units.append(unit)

	var refreshed_group: Array = []

	for unit: Unit in valid_units:
		refreshed_group.append(unit)

	_control_groups[slot] = refreshed_group

	return valid_units


func GetUnitAtWorldPosition(
	world_position: Vector2
) -> Unit:
	var best_unit: Unit = null
	var best_distance: float = INF

	for unit: Unit in _getUnits():
		if not _unitContainsPoint(
			unit,
			world_position
		):
			continue

		var distance: float = (
			unit.global_position.distance_squared_to(
				world_position
			)
		)

		if distance < best_distance:
			best_distance = distance
			best_unit = unit
			continue

		if (
			absf(
				distance - best_distance
			) <= 0.001
			and best_unit != null
			and unit.unit_id < best_unit.unit_id
		):
			best_unit = unit

	return best_unit


func ClearSelection() -> void:
	for unit: Unit in _selected_units:
		if not is_instance_valid(unit):
			continue

		_setSelectionVisual(
			unit,
			false
		)

	_selected_units.clear()

	selection_changed.emit(
		GetSelectedUnits()
	)


func _assignControlGroup(
	slot: int
) -> void:
	var selected_units: Array[Unit] = GetSelectedUnits()

	if selected_units.is_empty():
		return

	var group: Array = []

	for unit: Unit in selected_units:
		if not is_instance_valid(unit):
			continue

		group.append(unit)

	_control_groups[slot] = group


func _selectControlGroup(
	slot: int
) -> void:
	var units: Array[Unit] = GetControlGroupUnits(
		slot
	)

	if units.is_empty():
		return

	_applySelection(
		units,
		false
	)


func _getControlGroupSlot(
	event: InputEventKey
) -> int:
	match event.keycode:
		KEY_1:
			return 1
		KEY_2:
			return 2
		KEY_3:
			return 3
		KEY_4:
			return 4
		KEY_5:
			return 5
		KEY_6:
			return 6
		KEY_7:
			return 7
		KEY_8:
			return 8
		KEY_9:
			return 9

	match event.physical_keycode:
		KEY_1:
			return 1
		KEY_2:
			return 2
		KEY_3:
			return 3
		KEY_4:
			return 4
		KEY_5:
			return 5
		KEY_6:
			return 6
		KEY_7:
			return 7
		KEY_8:
			return 8
		KEY_9:
			return 9

	return 0


func _handleClickSelection(
	world_position: Vector2,
	additive: bool
) -> void:
	var unit: Unit = GetUnitAtWorldPosition(
		world_position
	)

	if unit == null:
		return

	var units: Array[Unit] = [
		unit,
	]

	_applySelection(
		units,
		additive
	)


func _handleDragSelection(
	additive: bool
) -> void:
	var selection_rect: Rect2 = _makeRect(
		_drag_start_world,
		_drag_current_world
	)

	var friendly_units: Array[Unit] = []
	var enemy_units: Array[Unit] = []

	for unit: Unit in _getUnits():
		if not _unitInsideSelectionRect(
			unit,
			selection_rect
		):
			continue

		if unit.player_controllable:
			friendly_units.append(unit)
		else:
			enemy_units.append(unit)

	if not friendly_units.is_empty():
		friendly_units.sort_custom(
			func(a: Unit, b: Unit) -> bool:
				return a.unit_id < b.unit_id
		)

		_applySelection(
			friendly_units,
			additive
		)

		return

	if enemy_units.is_empty():
		return

	var center: Vector2 = (
		selection_rect.position
		+ selection_rect.size * 0.5
	)

	var selected_enemy: Unit = null
	var best_distance: float = INF

	for unit: Unit in enemy_units:
		var distance: float = (
			unit.global_position.distance_squared_to(
				center
			)
		)

		if distance < best_distance:
			best_distance = distance
			selected_enemy = unit
			continue

		if (
			absf(
				distance - best_distance
			) <= 0.001
			and selected_enemy != null
			and unit.unit_id < selected_enemy.unit_id
		):
			selected_enemy = unit

	if selected_enemy == null:
		return

	var units: Array[Unit] = [
		selected_enemy,
	]

	_applySelection(
		units,
		additive
	)


func _applySelection(
	units: Array[Unit],
	additive: bool
) -> void:
	if units.is_empty():
		return

	_cleanupSelectedUnits()

	if not additive:
		for unit: Unit in _selected_units:
			_setSelectionVisual(
				unit,
				false
			)

		_selected_units.clear()

		for unit: Unit in units:
			if unit == null:
				continue

			if not is_instance_valid(unit):
				continue

			if _selected_units.has(unit):
				continue

			_selected_units.append(unit)

			_setSelectionVisual(
				unit,
				true
			)

		selection_changed.emit(
			GetSelectedUnits()
		)

		return

	var all_selected: bool = true
	var has_valid_unit: bool = false

	for unit: Unit in units:
		if unit == null:
			continue

		if not is_instance_valid(unit):
			continue

		has_valid_unit = true

		if not _selected_units.has(unit):
			all_selected = false
			break

	if not has_valid_unit:
		return

	if all_selected:
		for unit: Unit in units:
			if unit == null:
				continue

			if not is_instance_valid(unit):
				continue

			var index: int = _selected_units.find(
				unit
			)

			if index < 0:
				continue

			_selected_units.remove_at(
				index
			)

			_setSelectionVisual(
				unit,
				false
			)
	else:
		for unit: Unit in units:
			if unit == null:
				continue

			if not is_instance_valid(unit):
				continue

			if _selected_units.has(unit):
				continue

			_selected_units.append(unit)

			_setSelectionVisual(
				unit,
				true
			)

	selection_changed.emit(
		GetSelectedUnits()
	)


func _cleanupSelectedUnits() -> void:
	var valid_units: Array[Unit] = []

	for unit: Unit in _selected_units:
		if not is_instance_valid(unit):
			continue

		if not unit.is_inside_tree():
			continue

		valid_units.append(unit)

	_selected_units = valid_units


func _unitContainsPoint(
	unit: Unit,
	world_position: Vector2
) -> bool:
	var half_size: Vector2 = unit.GetHalfSize()

	var unit_rect: Rect2 = Rect2(
		unit.global_position - half_size,
		half_size * 2.0
	)

	return unit_rect.has_point(
		world_position
	)


func _unitInsideSelectionRect(
	unit: Unit,
	selection_rect: Rect2
) -> bool:
	var half_size: Vector2 = unit.GetHalfSize()

	var unit_rect: Rect2 = Rect2(
		unit.global_position - half_size,
		half_size * 2.0
	)

	return selection_rect.intersects(
		unit_rect
	)


func _getUnits() -> Array[Unit]:
	var result: Array[Unit] = []

	var nodes: Array[Node] = (
		get_tree().get_nodes_in_group("unit")
	)

	for node: Node in nodes:
		if node is Unit:
			result.append(
				node as Unit
			)

	return result


func _initializeUnits() -> void:
	for unit: Unit in _getUnits():
		_initializeUnit(
			unit
		)


func _initializeUnit(
	unit: Unit
) -> void:
	if unit == null:
		return

	var select_node: Sprite2D = (
		unit.get_node_or_null("select")
		as Sprite2D
	)

	if select_node == null:
		return

	if unit.player_controllable:
		select_node.self_modulate = (
			friendly_select_color
		)
	else:
		select_node.self_modulate = (
			enemy_select_color
		)

	select_node.visible = (
		_selected_units.has(unit)
	)


func _setSelectionVisual(
	unit: Unit,
	selected: bool
) -> void:
	var select_node: Sprite2D = (
		unit.get_node_or_null("select")
		as Sprite2D
	)

	if select_node == null:
		return

	select_node.visible = selected


func _onNodeAdded(
	node: Node
) -> void:
	if not node is Unit:
		return

	call_deferred(
		"_initializeUnit",
		node as Unit
	)


func _screenToWorld(
	screen_position: Vector2
) -> Vector2:
	return (
		get_viewport()
		.get_canvas_transform()
		.affine_inverse()
		* screen_position
	)


func _makeRect(
	a: Vector2,
	b: Vector2
) -> Rect2:
	var left: float = minf(
		a.x,
		b.x
	)

	var top: float = minf(
		a.y,
		b.y
	)

	var right: float = maxf(
		a.x,
		b.x
	)

	var bottom: float = maxf(
		a.y,
		b.y
	)

	return Rect2(
		Vector2(
			left,
			top
		),
		Vector2(
			right - left,
			bottom - top
		)
	)


func _draw() -> void:
	if not _left_pressed:
		return

	if not _drag_active:
		return

	var start_local: Vector2 = to_local(
		_drag_start_world
	)

	var current_local: Vector2 = to_local(
		_drag_current_world
	)

	var rect: Rect2 = _makeRect(
		start_local,
		current_local
	)

	draw_rect(
		rect,
		selection_fill_color,
		true
	)

	draw_rect(
		rect,
		selection_border_color,
		false,
		selection_border_width
	)
