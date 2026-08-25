class_name CommandController
extends Node


enum CommandMode {
	SMART,
	MOVE,
	ATTACK,
	SKILL,
}


enum TrackingMode {
	FOLLOW,
	CHASE,
}


signal command_mode_changed(mode: CommandMode)
signal follow_command_issued(units, target)
signal chase_command_issued(units, target)
signal attack_move_command_issued(units, target_world)
signal skill_command_issued(units, target_world, target_unit, skill_slot)


@export var movement_controller: MovementController
@export var select_controller: SelectController
@export var move_click_effect_scene: PackedScene
@export var tracking_refresh_interval: float = 0.1
@export var tracking_repath_distance: float = 8.0


var command_mode: CommandMode = CommandMode.SMART
var active_skill_slot: int = 0

var _tracking_elapsed: float = 0.0
var _tracking_target_by_unit: Dictionary[int, Unit] = {}
var _tracking_mode_by_unit: Dictionary[int, int] = {}
var _tracking_last_goal_by_unit: Dictionary[int, Vector2] = {}


func _ready() -> void:
	var parent: Node = get_parent()

	if parent != null:
		if movement_controller == null:
			var movement_node: Node = parent.get_node_or_null(
				"MovementController"
			)

			if movement_node is MovementController:
				movement_controller = movement_node as MovementController

		if select_controller == null:
			var select_node: Node = parent.get_node_or_null(
				"SelectController"
			)

			if select_node is SelectController:
				select_controller = select_node as SelectController

	if select_controller != null:
		if not select_controller.selection_changed.is_connected(
			_onSelectionChanged
		):
			select_controller.selection_changed.connect(
				_onSelectionChanged
			)


func _physics_process(delta: float) -> void:
	_tracking_elapsed += delta

	if _tracking_elapsed < maxf(tracking_refresh_interval, 0.01):
		return

	_tracking_elapsed = 0.0
	_refreshTrackingOrders()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		_handleKeyInput(
			event as InputEventKey
		)
		return

	if event is InputEventMouseButton:
		_handleMouseInput(
			event as InputEventMouseButton
		)


func GetCommandMode() -> CommandMode:
	return command_mode


func IsTargetingCommand() -> bool:
	return command_mode != CommandMode.SMART


func BeginMoveCommand() -> bool:
	return _beginTargetingMode(
		CommandMode.MOVE
	)


func BeginAttackCommand() -> bool:
	return _beginTargetingMode(
		CommandMode.ATTACK
	)


func BeginSkillCommand(
	skill_slot: int = 0
) -> bool:
	if not _hasCommandableSelection():
		return false

	active_skill_slot = maxi(skill_slot, 0)
	_setCommandMode(
		CommandMode.SKILL
	)
	return true


func CancelTargetingCommand() -> void:
	active_skill_slot = 0
	_setCommandMode(
		CommandMode.SMART
	)


func IssueSmartCommandAt(
	target_world: Vector2
) -> bool:
	if select_controller == null:
		return false

	var clicked_unit: Unit = (
		select_controller.GetUnitAtWorldPosition(
			target_world
		)
	)

	if clicked_unit != null:
		if _isFriendlyTarget(clicked_unit):
			return IssueFollowCommand(
				clicked_unit
			)

		if _isHostileTarget(clicked_unit):
			return IssueChaseCommand(
				clicked_unit
			)

		return false

	return IssueMoveCommand(
		target_world
	) >= 0


func IssueMoveCommand(
	target_world: Vector2
) -> int:
	if movement_controller == null:
		return -1

	var units: Array[Unit] = _getCommandableSelectedUnits()

	if units.is_empty():
		return -1

	_clearTrackingForUnits(
		units
	)

	var order_id: int = movement_controller.IssueMoveOrder(
		units,
		target_world
	)

	if order_id >= 0:
		_showMoveClickEffect(
			target_world
		)

	return order_id


func IssueStopCommand() -> int:
	CancelTargetingCommand()

	if movement_controller == null:
		return -1

	var units: Array[Unit] = _getCommandableSelectedUnits()

	if units.is_empty():
		return -1

	_clearTrackingForUnits(
		units
	)

	return movement_controller.IssueStopOrder(
		units
	)


func IssueFollowCommand(
	target: Unit
) -> bool:
	if not _isValidUnitTarget(target):
		return false

	if movement_controller == null:
		return false

	var units: Array[Unit] = _getCommandableSelectedUnits()
	var followers: Array[Unit] = []

	for unit: Unit in units:
		if unit == target:
			continue

		followers.append(unit)

	if followers.is_empty():
		return false

	_clearTrackingForUnits(
		followers
	)

	var order_id: int = movement_controller.IssueTrackingMoveOrder(
		followers,
		target.global_position
	)

	if order_id < 0:
		return false

	var accepted_units: Array[Unit] = []

	for unit: Unit in followers:
		if unit.fsm == null:
			continue

		if not unit.fsm.RequestFollow(target):
			continue

		_registerTracking(
			unit,
			target,
			TrackingMode.FOLLOW
		)
		accepted_units.append(unit)

	if accepted_units.is_empty():
		return false

	follow_command_issued.emit(
		accepted_units.duplicate(),
		target
	)
	return true


func IssueChaseCommand(
	target: Unit
) -> bool:
	if not _isHostileTarget(target):
		return false

	if movement_controller == null:
		return false

	var units: Array[Unit] = _getCommandableSelectedUnits()

	if units.is_empty():
		return false

	_clearTrackingForUnits(
		units
	)

	var order_id: int = movement_controller.IssueTrackingMoveOrder(
		units,
		target.global_position
	)

	if order_id < 0:
		return false

	var accepted_units: Array[Unit] = []

	for unit: Unit in units:
		if unit.fsm == null:
			continue

		if not unit.fsm.RequestChase(target):
			continue

		_registerTracking(
			unit,
			target,
			TrackingMode.CHASE
		)
		accepted_units.append(unit)

	if accepted_units.is_empty():
		return false

	chase_command_issued.emit(
		accepted_units.duplicate(),
		target
	)
	return true


func IssueAttackCommand(
	target: Unit
) -> bool:
	return IssueChaseCommand(
		target
	)


func IssueAttackMoveCommand(
	target_world: Vector2
) -> bool:
	if movement_controller == null:
		return false

	var units: Array[Unit] = _getCommandableSelectedUnits()

	if units.is_empty():
		return false

	_clearTrackingForUnits(
		units
	)

	var order_id: int = movement_controller.IssueTrackingMoveOrder(
		units,
		target_world
	)

	if order_id < 0:
		return false

	var accepted_units: Array[Unit] = []

	for unit: Unit in units:
		if unit.fsm == null:
			continue

		if not unit.fsm.RequestAttackMove():
			continue

		accepted_units.append(unit)

	if accepted_units.is_empty():
		return false

	_showMoveClickEffect(
		target_world
	)
	attack_move_command_issued.emit(
		accepted_units.duplicate(),
		target_world
	)
	return true


func IssueSkillCommand(
	target_world: Vector2,
	target_unit: Unit = null
) -> bool:
	var units: Array[Unit] = _getCommandableSelectedUnits()

	if units.is_empty():
		return false

	skill_command_issued.emit(
		units.duplicate(),
		target_world,
		target_unit,
		active_skill_slot
	)
	return true


func _handleKeyInput(
	key_event: InputEventKey
) -> void:
	if not key_event.pressed:
		return

	if key_event.echo:
		return

	if _isCancelKey(key_event):
		if not IsTargetingCommand():
			return

		CancelTargetingCommand()
		get_viewport().set_input_as_handled()
		return

	if _isStopKey(key_event):
		if IssueStopCommand() < 0:
			return

		get_viewport().set_input_as_handled()
		return

	if _isMoveKey(key_event):
		if not BeginMoveCommand():
			return

		get_viewport().set_input_as_handled()
		return

	if _isAttackKey(key_event):
		if not BeginAttackCommand():
			return

		get_viewport().set_input_as_handled()
		return

	if _isSkillKey(key_event):
		if not BeginSkillCommand():
			return

		get_viewport().set_input_as_handled()


func _handleMouseInput(
	mouse_event: InputEventMouseButton
) -> void:
	if not mouse_event.pressed:
		return

	if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		if IsTargetingCommand():
			CancelTargetingCommand()
			get_viewport().set_input_as_handled()
			return

		var smart_target_world: Vector2 = _screenToWorld(
			mouse_event.position
		)

		if not IssueSmartCommandAt(smart_target_world):
			return

		get_viewport().set_input_as_handled()
		return

	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return

	if not IsTargetingCommand():
		return

	var target_world: Vector2 = _screenToWorld(
		mouse_event.position
	)
	var target_unit: Unit = null

	if select_controller != null:
		target_unit = select_controller.GetUnitAtWorldPosition(
			target_world
		)

	var command_succeeded: bool = false

	match command_mode:
		CommandMode.MOVE:
			if target_unit != null:
				command_succeeded = IssueFollowCommand(
					target_unit
				)
			else:
				command_succeeded = IssueMoveCommand(
					target_world
				) >= 0
		CommandMode.ATTACK:
			if _isHostileTarget(target_unit):
				command_succeeded = IssueChaseCommand(
					target_unit
				)
			else:
				command_succeeded = IssueAttackMoveCommand(
					target_world
				)
		CommandMode.SKILL:
			command_succeeded = IssueSkillCommand(
				target_world,
				target_unit
			)

	if not command_succeeded:
		return

	CancelTargetingCommand()
	get_viewport().set_input_as_handled()


func _refreshTrackingOrders() -> void:
	if movement_controller == null:
		return

	if movement_controller.simulator == null:
		return

	var groups: Dictionary[String, Array] = {}
	var target_by_group: Dictionary[String, Unit] = {}
	var remove_ids: Array[int] = []
	var invalid_target_units: Array[Unit] = []
	var repath_distance: float = maxf(
		tracking_repath_distance,
		1.0
	)

	for unit_id: int in _tracking_target_by_unit:
		var unit: Unit = movement_controller.simulator.GetUnit(
			unit_id
		)
		var target: Unit = _tracking_target_by_unit[unit_id]

		if unit == null or not is_instance_valid(unit):
			remove_ids.append(unit_id)
			continue

		if not _isValidUnitTarget(target):
			remove_ids.append(unit_id)
			invalid_target_units.append(unit)
			continue

		if not _trackingStateActive(unit, unit_id):
			remove_ids.append(unit_id)
			continue

		if unit.fsm.current_state == UnitFSM.State.STUN:
			continue

		if unit.fsm.current_state == UnitFSM.State.ATTACK:
			continue

		var last_goal: Vector2 = _tracking_last_goal_by_unit.get(
			unit_id,
			target.global_position
		)

		if last_goal.distance_to(target.global_position) < repath_distance:
			continue

		var mode: int = _tracking_mode_by_unit[unit_id]
		var group_key: String = "%d:%d" % [
			mode,
			target.unit_id,
		]

		if not groups.has(group_key):
			groups[group_key] = []
			target_by_group[group_key] = target

		groups[group_key].append(unit)

	for unit_id: int in remove_ids:
		_removeTracking(unit_id)

	if not invalid_target_units.is_empty():
		var invalid_unit_ids: Array[int] = []

		for unit: Unit in invalid_target_units:
			invalid_unit_ids.append(unit.unit_id)
			unit.fsm.RequestIdle()

		movement_controller.simulator.StopUnits(
			invalid_unit_ids
		)

	for group_key: String in groups:
		var target: Unit = target_by_group[group_key]
		var units: Array[Unit] = []

		for value: Variant in groups[group_key]:
			if value is Unit:
				units.append(value as Unit)

		if units.is_empty():
			continue

		var order_id: int = movement_controller.IssueTrackingMoveOrder(
			units,
			target.global_position
		)

		if order_id < 0:
			continue

		for unit: Unit in units:
			_tracking_last_goal_by_unit[unit.unit_id] = target.global_position


func _trackingStateActive(
	unit: Unit,
	unit_id: int
) -> bool:
	if unit.fsm == null:
		return false

	if unit.fsm.current_state == UnitFSM.State.STUN:
		return true

	var mode: int = _tracking_mode_by_unit.get(
		unit_id,
		-1
	)

	if mode == TrackingMode.FOLLOW:
		return unit.fsm.current_state == UnitFSM.State.FOLLOW

	if mode != TrackingMode.CHASE:
		return false

	if unit.fsm.current_state == UnitFSM.State.CHASE:
		return true

	return (
		unit.fsm.current_state == UnitFSM.State.ATTACK
		and unit.fsm.attack_return_state == UnitFSM.State.CHASE
	)


func _registerTracking(
	unit: Unit,
	target: Unit,
	mode: TrackingMode
) -> void:
	_tracking_target_by_unit[unit.unit_id] = target
	_tracking_mode_by_unit[unit.unit_id] = mode
	_tracking_last_goal_by_unit[unit.unit_id] = target.global_position


func _clearTrackingForUnits(
	units: Array[Unit]
) -> void:
	for unit: Unit in units:
		_removeTracking(
			unit.unit_id
		)


func _removeTracking(unit_id: int) -> void:
	_tracking_target_by_unit.erase(unit_id)
	_tracking_mode_by_unit.erase(unit_id)
	_tracking_last_goal_by_unit.erase(unit_id)


func _beginTargetingMode(
	mode: CommandMode
) -> bool:
	if not _hasCommandableSelection():
		return false

	active_skill_slot = 0
	_setCommandMode(mode)
	return true


func _setCommandMode(
	mode: CommandMode
) -> void:
	if command_mode == mode:
		return

	command_mode = mode
	command_mode_changed.emit(
		command_mode
	)


func _hasCommandableSelection() -> bool:
	return not _getCommandableSelectedUnits().is_empty()


func _getCommandableSelectedUnits() -> Array[Unit]:
	var result: Array[Unit] = []

	if select_controller == null:
		return result

	for unit: Unit in select_controller.GetSelectedFriendlyUnits():
		if unit == null:
			continue

		if not is_instance_valid(unit):
			continue

		if not unit.CanReceiveCommands():
			continue

		result.append(unit)

	return result


func _isValidUnitTarget(
	target: Unit
) -> bool:
	if target == null:
		return false

	if not is_instance_valid(target):
		return false

	if not target.is_inside_tree():
		return false

	if target.fsm != null:
		if target.fsm.current_state == UnitFSM.State.DIE:
			return false

	return true


func _isFriendlyTarget(
	target: Unit
) -> bool:
	return (
		_isValidUnitTarget(target)
		and target.player_controllable
	)


func _isHostileTarget(
	target: Unit
) -> bool:
	return (
		_isValidUnitTarget(target)
		and not target.player_controllable
	)


func _onSelectionChanged(
	_selected_units: Variant
) -> void:
	if _hasCommandableSelection():
		return

	CancelTargetingCommand()


func _isMoveKey(
	event: InputEventKey
) -> bool:
	return _matchesKey(
		event,
		KEY_M
	)


func _isStopKey(
	event: InputEventKey
) -> bool:
	return _matchesKey(
		event,
		KEY_S
	)


func _isAttackKey(
	event: InputEventKey
) -> bool:
	return _matchesKey(
		event,
		KEY_A
	)


func _isSkillKey(
	event: InputEventKey
) -> bool:
	return _matchesKey(
		event,
		KEY_Q
	)


func _isCancelKey(
	event: InputEventKey
) -> bool:
	return _matchesKey(
		event,
		KEY_ESCAPE
	)


func _matchesKey(
	event: InputEventKey,
	key: int
) -> bool:
	return (
		event.keycode == key
		or event.physical_keycode == key
	)


func _showMoveClickEffect(
	target_world: Vector2
) -> void:
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

	scene.add_child(
		effect
	)
	effect.global_position = target_world


func _screenToWorld(
	screen_position: Vector2
) -> Vector2:
	return (
		get_viewport()
		.get_canvas_transform()
		.affine_inverse()
		* screen_position
	)
