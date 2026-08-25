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

signal commandModeChanged(mode: CommandMode)
signal followCommandIssued(units, target)
signal chaseCommandIssued(units, target)
signal attackMoveCommandIssued(units, target_world)
signal skillCommandIssued(units, target_world, target_unit, skill_slot)

@export var movementController: MovementController
@export var selectController: SelectController
@export var moveClickEffectScene: PackedScene
@export var trackingRefreshInterval: float = 0.1
@export var trackingRepathDistance: float = 8.0

var commandMode: CommandMode = CommandMode.SMART
var activeSkillSlot: int = 0

var _trackingElapsed: float = 0.0
var _TrackingTargetByUnit: Dictionary[int, Unit] = { }
var _TrackingModeByUnit: Dictionary[int, int] = { }
var _TrackingLastGoalByUnit: Dictionary[int, Vector2] = { }


func _ready() -> void:
	var parent: Node = get_parent()

	if parent != null:
		if movementController == null:
			var movement_node: Node = parent.get_node_or_null("MovementController")

			if movement_node is MovementController:
				movementController = movement_node as MovementController

		if selectController == null:
			var select_node: Node = parent.get_node_or_null("SelectController")

			if select_node is SelectController:
				selectController = select_node as SelectController

	if selectController != null:
		if not selectController.selection_changed.is_connected(_OnSelectionChanged):
			selectController.selection_changed.connect(_OnSelectionChanged)


func _physics_process(delta: float) -> void:
	_trackingElapsed += delta

	if _trackingElapsed < maxf(trackingRefreshInterval, 0.01):
		return

	_trackingElapsed = 0.0
	_RefreshTrackingOrders()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		_HandleKeyInput(event as InputEventKey)
		return

	if event is InputEventMouseButton:
		_HandleMouseInput(event as InputEventMouseButton)


func GetCommandMode() -> CommandMode:
	return commandMode


func IsTargetingCommand() -> bool:
	return commandMode != CommandMode.SMART


func BeginMoveCommand() -> bool:
	return _BeginTargetingMode(CommandMode.MOVE)


func BeginAttackCommand() -> bool:
	return _BeginTargetingMode(CommandMode.ATTACK)


func BeginSkillCommand(skill_slot: int = 0) -> bool:
	if not _HasCommandableSelection():
		return false

	activeSkillSlot = maxi(skill_slot, 0)
	_SetCommandMode(CommandMode.SKILL)
	return true


func CancelTargetingCommand() -> void:
	activeSkillSlot = 0
	_SetCommandMode(CommandMode.SMART)


func IssueSmartCommandAt(target_world: Vector2) -> bool:
	if selectController == null:
		return false

	var clicked_unit: Unit = (selectController.GetUnitAtWorldPosition(target_world))

	if clicked_unit != null:
		if _IsFriendlyTarget(clicked_unit):
			return IssueFollowCommand(clicked_unit)

		if _IsHostileTarget(clicked_unit):
			return IssueChaseCommand(clicked_unit)

		return false

	return IssueMoveCommand(target_world) >= 0


func IssueMoveCommand(targetWorld: Vector2) -> int:
	if movementController == null:
		return -1

	var units: Array[Unit] = _GetCommandableSelectedUnits()

	if units.is_empty():
		return -1

	_ClearTrackingForUnits(units)

	var orderId: int = movementController.IssueMoveOrder(units, targetWorld)

	if orderId >= 0:
		_ShowMoveClickEffect(targetWorld)

	return orderId


func IssueStopCommand() -> int:
	CancelTargetingCommand()

	if movementController == null:
		return -1

	var units: Array[Unit] = _GetCommandableSelectedUnits()

	if units.is_empty():
		return -1

	_ClearTrackingForUnits(units)

	return movementController.IssueStopOrder(units)


func IssueFollowCommand(target: Unit) -> bool:
	if not _IsValidUnitTarget(target):
		return false

	if movementController == null:
		return false

	var units: Array[Unit] = _GetCommandableSelectedUnits()
	var followers: Array[Unit] = []

	for unit: Unit in units:
		if unit == target:
			continue

		followers.append(unit)

	if followers.is_empty():
		return false

	_ClearTrackingForUnits(followers)

	var orderId: int = movementController.IssueTrackingMoveOrder(followers, target.global_position)

	if orderId < 0:
		return false

	var acceptedUnits: Array[Unit] = []

	for unit: Unit in followers:
		if unit.fsm == null:
			continue

		if not unit.fsm.RequestFollow(target):
			continue

		_RegisterTracking(unit, target, TrackingMode.FOLLOW)
		acceptedUnits.append(unit)

	if acceptedUnits.is_empty():
		return false

	followCommandIssued.emit(acceptedUnits.duplicate(), target)
	return true


func IssueChaseCommand(target: Unit) -> bool:
	if not _IsHostileTarget(target):
		return false

	if movementController == null:
		return false

	var units: Array[Unit] = _GetCommandableSelectedUnits()

	if units.is_empty():
		return false

	_ClearTrackingForUnits(units)

	var order_id: int = movementController.IssueTrackingMoveOrder(units, target.global_position)

	if order_id < 0:
		return false

	var acceptedUnits: Array[Unit] = []

	for unit: Unit in units:
		if unit.fsm == null:
			continue

		if not unit.fsm.RequestChase(target):
			continue

		_RegisterTracking(unit, target, TrackingMode.CHASE)
		acceptedUnits.append(unit)

	if acceptedUnits.is_empty():
		return false

	chaseCommandIssued.emit(acceptedUnits.duplicate(), target)
	return true


func IssueAttackCommand(target: Unit) -> bool:
	return IssueChaseCommand(target)


func IssueAttackMoveCommand(target_world: Vector2) -> bool:
	if movementController == null:
		return false

	var units: Array[Unit] = _GetCommandableSelectedUnits()

	if units.is_empty():
		return false

	_ClearTrackingForUnits(units)

	var order_id: int = movementController.IssueTrackingMoveOrder(units, target_world)

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

	_ShowMoveClickEffect(target_world)
	attackMoveCommandIssued.emit(accepted_units.duplicate(), target_world)
	return true


func IssueSkillCommand(target_world: Vector2, target_unit: Unit = null) -> bool:
	var units: Array[Unit] = _GetCommandableSelectedUnits()

	if units.is_empty():
		return false

	skillCommandIssued.emit(units.duplicate(), target_world, target_unit, activeSkillSlot)
	return true


func _HandleKeyInput(key_event: InputEventKey) -> void:
	if not key_event.pressed:
		return

	if key_event.echo:
		return

	if _IsCancelKey(key_event):
		if not IsTargetingCommand():
			return

		CancelTargetingCommand()
		get_viewport().set_input_as_handled()
		return

	if _IsStopKey(key_event):
		if IssueStopCommand() < 0:
			return

		get_viewport().set_input_as_handled()
		return

	if _IsMoveKey(key_event):
		if not BeginMoveCommand():
			return

		get_viewport().set_input_as_handled()
		return

	if _IsAttackKey(key_event):
		if not BeginAttackCommand():
			return

		get_viewport().set_input_as_handled()
		return

	if _IsSkillKey(key_event):
		if not BeginSkillCommand():
			return

		get_viewport().set_input_as_handled()


func _HandleMouseInput(mouse_event: InputEventMouseButton) -> void:
	if not mouse_event.pressed:
		return

	if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		if IsTargetingCommand():
			CancelTargetingCommand()
			get_viewport().set_input_as_handled()
			return

		var smart_target_world: Vector2 = _ScreenToWorld(mouse_event.position)

		if not IssueSmartCommandAt(smart_target_world):
			return

		get_viewport().set_input_as_handled()
		return

	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return

	if not IsTargetingCommand():
		return

	var target_world: Vector2 = _ScreenToWorld(mouse_event.position)
	var targetUnit: Unit = null

	if selectController != null:
		targetUnit = selectController.GetUnitAtWorldPosition(target_world)

	var commandSucceeded: bool = false

	match commandMode:
		CommandMode.MOVE:
			if targetUnit != null:
				commandSucceeded = IssueFollowCommand(targetUnit)
			else:
				commandSucceeded = IssueMoveCommand(target_world) >= 0
		CommandMode.ATTACK:
			if _IsHostileTarget(targetUnit):
				commandSucceeded = IssueChaseCommand(targetUnit)
			else:
				commandSucceeded = IssueAttackMoveCommand(target_world)
		CommandMode.SKILL:
			commandSucceeded = IssueSkillCommand(target_world, targetUnit)

	if not commandSucceeded:
		return

	CancelTargetingCommand()
	get_viewport().set_input_as_handled()


func _RefreshTrackingOrders() -> void:
	if movementController == null:
		return

	if movementController.simulator == null:
		return

	var groups: Dictionary[String, Array] = { }
	var targetByGroup: Dictionary[String, Unit] = { }
	var removeIds: Array[int] = []
	var invalidTargetUnits: Array[Unit] = []
	var repathDistance: float = maxf(trackingRepathDistance, 1.0)

	for unitId: int in _TrackingTargetByUnit:
		var unit: Unit = movementController.simulator.GetUnit(unitId)
		var target: Unit = _TrackingTargetByUnit[unitId]

		if unit == null or not is_instance_valid(unit):
			removeIds.append(unitId)
			continue

		if not _IsValidUnitTarget(target):
			removeIds.append(unitId)
			invalidTargetUnits.append(unit)
			continue

		if not _TrackingStateActive(unit, unitId):
			removeIds.append(unitId)
			continue

		if unit.fsm.currentState == UnitFSM.State.STUN:
			continue

		if unit.fsm.currentState == UnitFSM.State.ATTACK:
			continue

		var lastGoal: Vector2 = _TrackingLastGoalByUnit.get(unitId, target.global_position)

		if lastGoal.distance_to(target.global_position) < repathDistance:
			continue

		var mode: int = _TrackingModeByUnit[unitId]
		var groupKey: String = "%d:%d" % [mode, target.unitId]

		if not groups.has(groupKey):
			groups[groupKey] = []
			targetByGroup[groupKey] = target

		groups[groupKey].append(unit)

	for unitId: int in removeIds:
		_RemoveTracking(unitId)

	if not invalidTargetUnits.is_empty():
		var invalidUnitIds: Array[int] = []

		for unit: Unit in invalidTargetUnits:
			invalidUnitIds.append(unit.unitId)
			unit.fsm.RequestIdle()

		movementController.simulator.StopUnits(invalidUnitIds)

	for groupKey: String in groups:
		var target: Unit = targetByGroup[groupKey]
		var units: Array[Unit] = []

		for value: Variant in groups[groupKey]:
			if value is Unit:
				units.append(value as Unit)

		if units.is_empty():
			continue

		var orderId: int = movementController.IssueTrackingMoveOrder(units, target.global_position)

		if orderId < 0:
			continue

		for unit: Unit in units:
			_TrackingLastGoalByUnit[unit.unitId] = target.global_position


func _TrackingStateActive(unit: Unit, unit_id: int) -> bool:
	if unit.fsm == null:
		return false

	if unit.fsm.currentState == UnitFSM.State.STUN:
		return true

	var mode: int = _TrackingModeByUnit.get(unit_id, -1)

	if mode == TrackingMode.FOLLOW:
		return unit.fsm.currentState == UnitFSM.State.FOLLOW

	if mode != TrackingMode.CHASE:
		return false

	if unit.fsm.currentState == UnitFSM.State.CHASE:
		return true

	return (
		unit.fsm.currentState == UnitFSM.State.ATTACK
		and unit.fsm.attack_return_state == UnitFSM.State.CHASE
	)


func _RegisterTracking(unit: Unit, target: Unit, mode: TrackingMode) -> void:
	_TrackingTargetByUnit[unit.unitId] = target
	_TrackingModeByUnit[unit.unitId] = mode
	_TrackingLastGoalByUnit[unit.unitId] = target.global_position


func _ClearTrackingForUnits(units: Array[Unit]) -> void:
	for unit: Unit in units:
		_RemoveTracking(unit.unitId)


func _RemoveTracking(unit_id: int) -> void:
	_TrackingTargetByUnit.erase(unit_id)
	_TrackingModeByUnit.erase(unit_id)
	_TrackingLastGoalByUnit.erase(unit_id)


func _BeginTargetingMode(mode: CommandMode) -> bool:
	if not _HasCommandableSelection():
		return false

	activeSkillSlot = 0
	_SetCommandMode(mode)
	return true


func _SetCommandMode(mode: CommandMode) -> void:
	if commandMode == mode:
		return

	commandMode = mode
	commandModeChanged.emit(commandMode)


func _HasCommandableSelection() -> bool:
	return not _GetCommandableSelectedUnits().is_empty()


func _GetCommandableSelectedUnits() -> Array[Unit]:
	var result: Array[Unit] = []

	if selectController == null:
		return result

	for unit: Unit in selectController.GetSelectedFriendlyUnits():
		if unit == null:
			continue

		if not is_instance_valid(unit):
			continue

		if not unit.CanReceiveCommands():
			continue

		result.append(unit)

	return result


func _IsValidUnitTarget(target: Unit) -> bool:
	if target == null:
		return false

	if not is_instance_valid(target):
		return false

	if not target.is_inside_tree():
		return false

	if target.fsm != null:
		if target.fsm.currentState == UnitFSM.State.DIE:
			return false

	return true


func _IsFriendlyTarget(target: Unit) -> bool:
	return (_IsValidUnitTarget(target) and target.player_controllable)


func _IsHostileTarget(target: Unit) -> bool:
	return (_IsValidUnitTarget(target) and not target.player_controllable)


func _OnSelectionChanged(_selected_units: Variant) -> void:
	if _HasCommandableSelection():
		return

	CancelTargetingCommand()


func _IsMoveKey(event: InputEventKey) -> bool:
	return _MatchesKey(event, KEY_M)


func _IsStopKey(event: InputEventKey) -> bool:
	return _MatchesKey(event, KEY_S)


func _IsAttackKey(event: InputEventKey) -> bool:
	return _MatchesKey(event, KEY_A)


func _IsSkillKey(event: InputEventKey) -> bool:
	return _MatchesKey(event, KEY_Q)


func _IsCancelKey(event: InputEventKey) -> bool:
	return _MatchesKey(event, KEY_ESCAPE)


func _MatchesKey(event: InputEventKey, key: int) -> bool:
	return (event.keycode == key or event.physical_keycode == key)


func _ShowMoveClickEffect(target_world: Vector2) -> void:
	if moveClickEffectScene == null:
		return

	var node: Node = moveClickEffectScene.instantiate()

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


func _ScreenToWorld(screen_position: Vector2) -> Vector2:
	return (get_viewport().get_canvas_transform().affine_inverse() * screen_position)
