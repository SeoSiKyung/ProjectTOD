class_name MovementController
extends Node


@export var simulator: MovementSimulator


var _next_order_id: int = 1
var command_log: Array = []


func _ready() -> void:
	if simulator != null:
		return

	var parent: Node = get_parent()

	if parent == null:
		return

	var node: Node = parent.get_node_or_null("MovementSimulator")

	if node is MovementSimulator:
		simulator = node as MovementSimulator


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

	var unit_ids: Array[int] = []
	var seen: Dictionary[int, bool] = {}

	for unit: Unit in units:
		if unit == null:
			continue

		if seen.has(unit.unit_id):
			continue

		seen[unit.unit_id] = true
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

	simulator.add_move_order(order)

	command_log.append({
		"type": "move",
		"order_id": order_id,
		"tick": simulator.simulation_tick + 1,
		"unit_ids": unit_ids.duplicate(),
		"target": target_world,
	})

	return order_id


func issue_stop_order(
	units: Array[Unit]
) -> int:
	if simulator == null:
		push_error("MovementSimulator가 지정되지 않았습니다.")
		return -1

	var unit_ids: Array[int] = []
	var seen: Dictionary[int, bool] = {}

	for unit: Unit in units:
		if unit == null:
			continue

		if seen.has(unit.unit_id):
			continue

		seen[unit.unit_id] = true
		unit_ids.append(unit.unit_id)

	unit_ids.sort()

	if unit_ids.is_empty():
		return -1

	var command_id: int = _next_order_id
	_next_order_id += 1

	simulator.stop_units(unit_ids)

	command_log.append({
		"type": "stop",
		"order_id": command_id,
		"tick": simulator.simulation_tick + 1,
		"unit_ids": unit_ids.duplicate(),
	})

	return command_id
