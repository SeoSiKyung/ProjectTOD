class_name SelectController
extends Node2D

signal selection_changed(selectedUnits)

@export var dragThreshold: float = 6.0
@export var selectionFillColor: Color = Color(0.2, 0.8, 0.3, 0.12)
@export var selectionBorderColor: Color = Color(0.3, 1.0, 0.4, 0.95)
@export var selectionBorderWidth: float = 2.0
@export var friendlySelectColor: Color = Color(0.2, 1.0, 0.2, 1.0)
@export var enemySelectColor: Color = Color(1.0, 0.2, 0.2, 1.0)
@export var commandController: Node

var _selectedUnits: Array[Unit] = []
var _controlGroups: Dictionary = { }

var _leftPressed: bool = false
var _dragActive: bool = false
var _additiveSelection: bool = false

var _dragStartWorld: Vector2 = Vector2.ZERO
var _dragCurrentWorld: Vector2 = Vector2.ZERO


func _ready() -> void:
	if commandController == null:
		var parent: Node = get_parent()

		if parent != null:
			commandController = parent.get_node_or_null("CommandController")

	get_tree().node_added.connect(_OnNodeAdded)
	call_deferred("_InitializeUnits")


func _unhandled_input(event: InputEvent) -> void:
	if _CommandTargetingActive():
		if event is InputEventMouseButton or event is InputEventMouseMotion:
			_leftPressed = false
			_dragActive = false
			_additiveSelection = false
			queue_redraw()
			return

	if event is InputEventKey:
		var keyEvent: InputEventKey = event as InputEventKey

		if not keyEvent.pressed:
			return

		if keyEvent.echo:
			return

		var slot: int = _GetControlGroupSlot(keyEvent)

		if slot > 0:
			if keyEvent.ctrl_pressed:
				_AssignControlGroup(slot)
			else:
				_SelectControlGroup(slot)

			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton:
		var mouseEvent: InputEventMouseButton = event as InputEventMouseButton

		if mouseEvent.button_index != MOUSE_BUTTON_LEFT:
			return

		var worldPosition: Vector2 = _ScreenToWorld(mouseEvent.position)

		if mouseEvent.pressed:
			_leftPressed = true
			_dragActive = false
			_additiveSelection = mouseEvent.ctrl_pressed
			_dragStartWorld = worldPosition
			_dragCurrentWorld = worldPosition

			queue_redraw()
			get_viewport().set_input_as_handled()
			return

		if not _leftPressed:
			return

		_dragCurrentWorld = worldPosition

		if _dragActive:
			_HandleDragSelection(_additiveSelection)
		else:
			_HandleClickSelection(_dragStartWorld, _additiveSelection)

		_leftPressed = false
		_dragActive = false
		_additiveSelection = false

		queue_redraw()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion:
		if not _leftPressed:
			return

		var motionEvent: InputEventMouseMotion = event as InputEventMouseMotion

		_dragCurrentWorld = _ScreenToWorld(motionEvent.position)

		if _dragStartWorld.distance_to(_dragCurrentWorld) >= dragThreshold:
			_dragActive = true

		queue_redraw()
		get_viewport().set_input_as_handled()


func _CommandTargetingActive() -> bool:
	if commandController == null:
		return false

	if not commandController.has_method("IsTargetingCommand"):
		return false

	return bool(commandController.call("IsTargetingCommand"))


func GetSelectedUnits() -> Array[Unit]:
	var result: Array[Unit] = []
	var validUnits: Array[Unit] = []

	for unit: Unit in _selectedUnits:
		if not is_instance_valid(unit):
			continue

		if not unit.is_inside_tree():
			continue

		validUnits.append(unit)
		result.append(unit)

	_selectedUnits = validUnits

	return result


func GetSelectedFriendlyUnits() -> Array[Unit]:
	var result: Array[Unit] = []

	for unit: Unit in GetSelectedUnits():
		if not unit.playerControllable:
			continue

		result.append(unit)

	return result


func HasFriendlySelection() -> bool:
	return not GetSelectedFriendlyUnits().is_empty()


func GetControlGroupUnits(slot: int) -> Array[Unit]:
	if slot < 1 or slot > 9:
		return []

	if not _controlGroups.has(slot):
		return []

	var storedUnits: Array = _controlGroups[slot]
	var validUnits: Array[Unit] = []

	for value: Variant in storedUnits:
		if not value is Unit:
			continue

		var unit: Unit = value as Unit

		if not is_instance_valid(unit):
			continue

		if not unit.is_inside_tree():
			continue

		validUnits.append(unit)

	var refreshedGroup: Array = []

	for unit: Unit in validUnits:
		refreshedGroup.append(unit)

	_controlGroups[slot] = refreshedGroup

	return validUnits


func GetUnitAtWorldPosition(worldPosition: Vector2) -> Unit:
	var bestUnit: Unit = null
	var bestDistance: float = INF

	for unit: Unit in _GetUnits():
		if not _UnitContainsPoint(unit, worldPosition):
			continue

		var distance: float = unit.global_position.distance_squared_to(worldPosition)

		if distance < bestDistance:
			bestDistance = distance
			bestUnit = unit
			continue

		if (
			absf(distance - bestDistance) <= 0.001
			and bestUnit != null and unit.unitId < bestUnit.unitId
		):
			bestUnit = unit

	return bestUnit


func ClearSelection() -> void:
	for unit: Unit in _selectedUnits:
		if not is_instance_valid(unit):
			continue

		_SetSelectionVisual(unit, false)

	_selectedUnits.clear()

	selection_changed.emit(GetSelectedUnits())


func _AssignControlGroup(slot: int) -> void:
	var selectedUnits: Array[Unit] = GetSelectedUnits()

	if selectedUnits.is_empty():
		return

	var group: Array = []

	for unit: Unit in selectedUnits:
		if not is_instance_valid(unit):
			continue

		group.append(unit)

	_controlGroups[slot] = group


func _SelectControlGroup(slot: int) -> void:
	var units: Array[Unit] = GetControlGroupUnits(slot)

	if units.is_empty():
		return

	_ApplySelection(units, false)


func _GetControlGroupSlot(event: InputEventKey) -> int:
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


func _HandleClickSelection(worldPosition: Vector2, additive: bool) -> void:
	var unit: Unit = GetUnitAtWorldPosition(worldPosition)

	if unit == null:
		return

	var units: Array[Unit] = [unit]

	_ApplySelection(units, additive)


func _HandleDragSelection(additive: bool) -> void:
	var selectionRect: Rect2 = _MakeRect(_dragStartWorld, _dragCurrentWorld)

	var friendlyUnits: Array[Unit] = []
	var enemyUnits: Array[Unit] = []

	for unit: Unit in _GetUnits():
		if not _UnitInsideSelectionRect(unit, selectionRect):
			continue

		if unit.playerControllable:
			friendlyUnits.append(unit)
		else:
			enemyUnits.append(unit)

	if not friendlyUnits.is_empty():
		friendlyUnits.sort_custom(
			func(a: Unit, b: Unit) -> bool:
				return a.unitId < b.unitId,
		)

		_ApplySelection(friendlyUnits, additive)
		return

	if enemyUnits.is_empty():
		return

	var center: Vector2 = selectionRect.position + selectionRect.size * 0.5

	var selectedEnemy: Unit = null
	var bestDistance: float = INF

	for unit: Unit in enemyUnits:
		var distance: float = unit.global_position.distance_squared_to(center)

		if distance < bestDistance:
			bestDistance = distance
			selectedEnemy = unit
			continue

		if (
			absf(distance - bestDistance) <= 0.001 and selectedEnemy != null
			and unit.unitId < selectedEnemy.unitId
		):
			selectedEnemy = unit

	if selectedEnemy == null:
		return

	var units: Array[Unit] = [selectedEnemy]

	_ApplySelection(units, additive)


func _ApplySelection(units: Array[Unit], additive: bool) -> void:
	if units.is_empty():
		return

	_CleanupSelectedUnits()

	if not additive:
		for unit: Unit in _selectedUnits:
			_SetSelectionVisual(unit, false)

		_selectedUnits.clear()

		for unit: Unit in units:
			if unit == null:
				continue

			if not is_instance_valid(unit):
				continue

			if _selectedUnits.has(unit):
				continue

			_selectedUnits.append(unit)
			_SetSelectionVisual(unit, true)

		selection_changed.emit(GetSelectedUnits())
		return

	var allSelected: bool = true
	var hasValidUnit: bool = false

	for unit: Unit in units:
		if unit == null:
			continue

		if not is_instance_valid(unit):
			continue

		hasValidUnit = true

		if not _selectedUnits.has(unit):
			allSelected = false
			break

	if not hasValidUnit:
		return

	if allSelected:
		for unit: Unit in units:
			if unit == null:
				continue

			if not is_instance_valid(unit):
				continue

			var index: int = _selectedUnits.find(unit)

			if index < 0:
				continue

			_selectedUnits.remove_at(index)
			_SetSelectionVisual(unit, false)
	else:
		for unit: Unit in units:
			if unit == null:
				continue

			if not is_instance_valid(unit):
				continue

			if _selectedUnits.has(unit):
				continue

			_selectedUnits.append(unit)
			_SetSelectionVisual(unit, true)

	selection_changed.emit(GetSelectedUnits())


func _CleanupSelectedUnits() -> void:
	var validUnits: Array[Unit] = []

	for unit: Unit in _selectedUnits:
		if not is_instance_valid(unit):
			continue

		if not unit.is_inside_tree():
			continue

		validUnits.append(unit)

	_selectedUnits = validUnits


func _UnitContainsPoint(unit: Unit, worldPosition: Vector2) -> bool:
	var halfSize: int = unit.GetHalfSize()
	var half: Vector2 = Vector2(halfSize, halfSize)
	var unitRect: Rect2 = Rect2(unit.global_position - half, half * 2.0)

	return unitRect.has_point(worldPosition)


func _UnitInsideSelectionRect(unit: Unit, selectionRect: Rect2) -> bool:
	var halfSize: int = unit.GetHalfSize()
	var half: Vector2 = Vector2(halfSize, halfSize)
	var unitRect: Rect2 = Rect2(unit.global_position - half, half * 2.0)

	return selectionRect.intersects(unitRect)


func _GetUnits() -> Array[Unit]:
	var result: Array[Unit] = []
	var nodes: Array[Node] = get_tree().get_nodes_in_group("unit")

	for node: Node in nodes:
		if node is Unit:
			result.append(node as Unit)

	return result


func _InitializeUnits() -> void:
	for unit: Unit in _GetUnits():
		_InitializeUnit(unit)


func _InitializeUnit(unit: Unit) -> void:
	if unit == null:
		return

	var selectNode: Sprite2D = unit.get_node_or_null("select") as Sprite2D

	if selectNode == null:
		return

	if unit.playerControllable:
		selectNode.self_modulate = friendlySelectColor
	else:
		selectNode.self_modulate = enemySelectColor

	selectNode.visible = _selectedUnits.has(unit)


func _SetSelectionVisual(unit: Unit, selected: bool) -> void:
	var selectNode: Sprite2D = unit.get_node_or_null("select") as Sprite2D

	if selectNode == null:
		return

	selectNode.visible = selected


func _OnNodeAdded(node: Node) -> void:
	if not node is Unit:
		return

	call_deferred("_InitializeUnit", node as Unit)


func _ScreenToWorld(screenPosition: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screenPosition


func _MakeRect(a: Vector2, b: Vector2) -> Rect2:
	var left: float = minf(a.x, b.x)
	var top: float = minf(a.y, b.y)
	var right: float = maxf(a.x, b.x)
	var bottom: float = maxf(a.y, b.y)

	return Rect2(Vector2(left, top), Vector2(right - left, bottom - top))


func _draw() -> void:
	if not _leftPressed:
		return

	if not _dragActive:
		return

	var startLocal: Vector2 = to_local(_dragStartWorld)
	var currentLocal: Vector2 = to_local(_dragCurrentWorld)
	var rect: Rect2 = _MakeRect(startLocal, currentLocal)

	draw_rect(rect, selectionFillColor, true)
	draw_rect(rect, selectionBorderColor, false, selectionBorderWidth)
