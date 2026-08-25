class_name MovementController
extends Node

@export var simulator: MovementSimulator
@export var selectController: SelectController

var _nextOrderId: int = 1
var _commandLog: Array = []


func _ready() -> void:
	var parent: Node = get_parent()

	if parent == null:
		return

	if simulator == null:
		var simulatorNode: Node = parent.get_node_or_null("MovementSimulator")

		if simulatorNode is MovementSimulator:
			simulator = simulatorNode as MovementSimulator

	if selectController == null:
		var selectNode: Node = parent.get_node_or_null("SelectController")

		if selectNode is SelectController:
			selectController = selectNode as SelectController


func IssueMoveOrder(
	units: Array[Unit],
	targetWorld: Vector2,
	requestMoveState: bool = true,
	recordCommand: bool = true,
) -> int:
	if simulator == null:
		push_error("MovementSimulator가 지정되지 않았습니다.")
		return -1

	if simulator.navigationService == null:
		push_error("NavigationService가 지정되지 않았습니다.")
		return -1

	var acceptedUnits: Array[Unit] = []
	var unitIds: Array[int] = []
	var seen: Dictionary[int, bool] = { }

	for unit: Unit in units:
		if not _CanIssueCommandTo(unit):
			continue

		if seen.has(unit.unitId):
			continue

		seen[unit.unitId] = true
		acceptedUnits.append(unit)
		unitIds.append(unit.unitId)

	unitIds.sort()

	if unitIds.is_empty():
		return -1

	var orderId: int = _nextOrderId
	_nextOrderId += 1

	var order: MoveOrder = MoveOrder.new(
		orderId,
		simulator.simulationTick + 1,
		targetWorld,
		unitIds,
		simulator.navigationService,
	)

	simulator.AddMoveOrder(order)

	if requestMoveState:
		for unit: Unit in acceptedUnits:
			unit.fsm.RequestMove()

	if recordCommand:
		_commandLog.append(
			{
				"type": "move",
				"order_id": orderId,
				"tick": simulator.simulationTick + 1,
				"unit_ids": unitIds.duplicate(),
				"target": targetWorld,
			}
		)

	return orderId


func IssueSelectedMoveOrder(targetWorld: Vector2) -> int:
	if selectController == null:
		return -1

	return IssueMoveOrder(selectController.GetSelectedFriendlyUnits(), targetWorld)


func IssueTrackingMoveOrder(units: Array[Unit], targetWorld: Vector2) -> int:
	return IssueMoveOrder(units, targetWorld, false, false)


func IssueStopOrder(units: Array[Unit]) -> int:
	if simulator == null:
		push_error("MovementSimulator가 지정되지 않았습니다.")
		return -1

	var acceptedUnits: Array[Unit] = []
	var unitIds: Array[int] = []
	var seen: Dictionary[int, bool] = { }

	for unit: Unit in units:
		if not _CanIssueCommandTo(unit):
			continue

		if seen.has(unit.unitId):
			continue

		seen[unit.unitId] = true
		acceptedUnits.append(unit)
		unitIds.append(unit.unitId)

	unitIds.sort()

	if unitIds.is_empty():
		return -1

	var commandId: int = _nextOrderId
	_nextOrderId += 1

	simulator.StopUnits(unitIds)

	for unit: Unit in acceptedUnits:
		unit.fsm.RequestIdle()

	_commandLog.append(
		{
			"type": "stop",
			"order_id": commandId,
			"tick": simulator.simulationTick + 1,
			"unit_ids": unitIds.duplicate(),
		}
	)

	return commandId


func IssueSelectedStopOrder() -> int:
	if selectController == null:
		return -1

	return IssueStopOrder(selectController.GetSelectedFriendlyUnits())


func _CanIssueCommandTo(unit: Unit) -> bool:
	if unit == null:
		return false

	if not is_instance_valid(unit):
		return false

	if not unit.playerControllable:
		return false

	return unit.CanReceiveCommands()
