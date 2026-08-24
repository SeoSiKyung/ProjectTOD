class_name MovementController
extends Node


@export var simulator: MovementSimulator
@export var select_controller: SelectController


var _next_order_id: int = 1
var command_log: Array = []


func _ready() -> void:
	var parent: Node = get_parent()

	if parent == null:
		return

	if simulator == null:
		var simulator_node: Node = parent.get_node_or_null(
			"MovementSimulator"
		)

		if simulator_node is MovementSimulator:
			simulator = simulator_node as MovementSimulator

	if select_controller == null:
		var select_node: Node = parent.get_node_or_null(
			"SelectController"
		)

		if select_node is SelectController:
			select_controller = select_node as SelectController


func issue_move_order(
	units: Array[Unit],
	target_world: Vector2
) -> int:
	if simulator == null:
		push_error("MovementSimulator가 지정되지 않았습니다.")
		return -1

	if simulator.navigation_service == null:
		push_error("NavigationService가 지정되지 않았습니다.")
		return -1

	var accepted_units: Array[Unit] = []
	var unit_ids: Array[int] = []
	var seen: Dictionary[int, bool] = {}

	for unit: Unit in units:
		if not _can_issue_command_to(unit):
			continue

		if seen.has(unit.unit_id):
			continue

		seen[unit.unit_id] = true
		accepted_units.append(unit)
		unit_ids.append(unit.unit_id)

	unit_ids.sort()

	if unit_ids.is_empty():
		return -1

	var order_id: int = _next_order_id
	_next_order_id += 1

	var order: MoveOrder = MoveOrder.new(
		order_id,
		simulator.simulation_tick + 1,
		target_world,
		unit_ids,
		simulator.navigation_service
	)

	simulator.add_move_order(
		order
	)

	for unit: Unit in accepted_units:
		unit.fsm.request_move()

	command_log.append({
		"type": "move",
		"order_id": order_id,
		"tick": simulator.simulation_tick + 1,
		"unit_ids": unit_ids.duplicate(),
		"target": target_world,
	})

	return order_id


func issue_selected_move_order(
	target_world: Vector2
) -> int:
	if select_controller == null:
		return -1

	return issue_move_order(
		select_controller.get_selected_friendly_units(),
		target_world
	)


func issue_stop_order(
	units: Array[Unit]
) -> int:
	if simulator == null:
		push_error("MovementSimulator가 지정되지 않았습니다.")
		return -1

	var accepted_units: Array[Unit] = []
	var unit_ids: Array[int] = []
	var seen: Dictionary[int, bool] = {}

	for unit: Unit in units:
		if not _can_issue_command_to(unit):
			continue

		if seen.has(unit.unit_id):
			continue

		seen[unit.unit_id] = true
		accepted_units.append(unit)
		unit_ids.append(unit.unit_id)

	unit_ids.sort()

	if unit_ids.is_empty():
		return -1

	var command_id: int = _next_order_id
	_next_order_id += 1

	simulator.stop_units(
		unit_ids
	)

	for unit: Unit in accepted_units:
		unit.fsm.request_idle()

	command_log.append({
		"type": "stop",
		"order_id": command_id,
		"tick": simulator.simulation_tick + 1,
		"unit_ids": unit_ids.duplicate(),
	})

	return command_id


func issue_selected_stop_order() -> int:
	if select_controller == null:
		return -1

	return issue_stop_order(
		select_controller.get_selected_friendly_units()
	)


func _can_issue_command_to(unit: Unit) -> bool:
	if unit == null:
		return false

	if not is_instance_valid(unit):
		return false

	if not unit.player_controllable:
		return false

	return unit.can_receive_commands()
