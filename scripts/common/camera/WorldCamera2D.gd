class_name WorldCamera2D
extends Camera2D

# 화면 가장자리에서 이동을 시작하는 폭과 스크롤 속도
@export var edgeMargin: float = 24.0
@export var scrollSpeed: float = 900.0

@export var cameraInputEnabled: bool = true
@export var minZoom: float = 0.5
@export var maxZoom: float = 2.0
@export var zoomStep: float = 1.1

var worldRect: Rect2

var _isMouseOutsideWindow: bool = false


func _ready() -> void:
	anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	offset = Vector2.ZERO

	position_smoothing_enabled = false
	drag_horizontal_enabled = false
	drag_vertical_enabled = false

	var window: Window = get_window()
	window.mouse_entered.connect(_OnMouseEntered)
	window.mouse_exited.connect(_OnMouseExited)

	if worldRect.has_area():
		MoveToWorldPosition(global_position)


func _process(delta: float) -> void:
	if not worldRect.has_area():
		return

	var direction: Vector2 = Vector2.ZERO
	if _CanUseCameraInput():
		direction = _GetEdgeDirection()

	var movement: Vector2 = direction.normalized() * scrollSpeed * delta / zoom

	MoveToWorldPosition(global_position + movement)


func _unhandled_input(event: InputEvent) -> void:
	if event is not InputEventMouseButton:
		return

	var mouseEvent: InputEventMouseButton = event
	if not mouseEvent.pressed:
		return

	if not _CanUseCameraInput():
		return

	var zoomMultiplier: float
	match mouseEvent.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			zoomMultiplier = zoomStep
		MOUSE_BUTTON_WHEEL_DOWN:
			zoomMultiplier = 1.0 / zoomStep
		_:
			return

	_ZoomAtScreenPosition(mouseEvent.position, zoomMultiplier)
	get_viewport().set_input_as_handled()


func SetWorldRect(rect: Rect2) -> void:
	worldRect = rect
	if worldRect.has_area():
		MoveToWorldPosition(global_position)


func MoveToWorldPosition(worldPosition: Vector2) -> void:
	global_position = worldPosition
	_ClampToWorldRect()
	force_update_scroll()


func GetVisibleWorldRect() -> Rect2:
	var visibleSize: Vector2 = get_viewport_rect().size / zoom
	return Rect2(global_position - visibleSize * 0.5, visibleSize)


func _CanUseCameraInput() -> bool:
	if not worldRect.has_area():
		return false

	if not cameraInputEnabled:
		return false

	if not get_window().has_focus():
		return false

	if _isMouseOutsideWindow:
		return false

	var viewport: Viewport = get_viewport()
	var mousePosition: Vector2 = viewport.get_mouse_position()
	if not get_viewport_rect().has_point(mousePosition):
		return false

	if viewport.gui_get_hovered_control() != null:
		return false

	return true


func _GetEdgeDirection() -> Vector2:
	var rect: Rect2 = get_viewport_rect()
	var mousePosition: Vector2 = get_viewport().get_mouse_position()
	var direction: Vector2 = Vector2.ZERO

	if mousePosition.x < rect.position.x + edgeMargin:
		direction.x = -1.0
	elif mousePosition.x > rect.end.x - edgeMargin:
		direction.x = 1.0

	if mousePosition.y < rect.position.y + edgeMargin:
		direction.y = -1.0
	elif mousePosition.y > rect.end.y - edgeMargin:
		direction.y = 1.0

	return direction


func _ClampToWorldRect() -> void:
	var halfViewSize: Vector2 = get_viewport_rect().size / zoom * 0.5
	var minCenter: Vector2 = worldRect.position + halfViewSize
	var maxCenter: Vector2 = worldRect.end - halfViewSize
	var worldCenter: Vector2 = worldRect.get_center()
	var cameraPosition: Vector2 = global_position

	if minCenter.x > maxCenter.x:
		cameraPosition.x = worldCenter.x
	else:
		cameraPosition.x = clampf(cameraPosition.x, minCenter.x, maxCenter.x)

	if minCenter.y > maxCenter.y:
		cameraPosition.y = worldCenter.y
	else:
		cameraPosition.y = clampf(cameraPosition.y, minCenter.y, maxCenter.y)

	global_position = cameraPosition


func _OnMouseEntered() -> void:
	_isMouseOutsideWindow = false


func _OnMouseExited() -> void:
	_isMouseOutsideWindow = true


func _ZoomAtScreenPosition(screenPosition: Vector2, zoomMultiplier: float) -> void:
	var newZoom: float = clampf(zoom.x * zoomMultiplier, minZoom, maxZoom)
	if is_equal_approx(newZoom, zoom.x):
		return

	var worldBefore: Vector2 = _ScreenToWorld(screenPosition)

	zoom = Vector2.ONE * newZoom
	force_update_scroll()

	var worldAfter: Vector2 = _ScreenToWorld(screenPosition)
	MoveToWorldPosition(global_position + worldBefore - worldAfter)


func _ScreenToWorld(screenPosition: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screenPosition
