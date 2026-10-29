class_name MinimapView
extends Control

enum DockSide {
	LEFT,
	RIGHT,
}

signal DockSideChanged(side: DockSide)
signal MoveCommandRequested(worldPosition: Vector2)

@onready var _mapCanvas: Control = $ParchmentPanel/MapCanvas

@export var dockSide: DockSide = DockSide.RIGHT
@export var minimapSize: Vector2 = Vector2(220.0, 220.0)
@export var screenMargin: float = 16.0

@export var backgroundColor: Color = Color(0.08, 0.08, 0.08, 1.0)
@export var borderColor: Color = Color(0.65, 0.55, 0.35, 1.0)
@export var cameraFillColor: Color = Color(1.0, 1.0, 1.0, 0.08)
@export var cameraBorderColor: Color = Color.WHITE

@export var interactionEnabled: bool = true

var worldCamera: WorldCamera2D
var mapTexture: Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false
	custom_minimum_size = minimapSize

	SetDockSide(dockSide)

	_mapCanvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mapCanvas.clip_contents = true
	_mapCanvas.draw.connect(_DrawMap)

	mouse_force_pass_scroll_events = false


func Initialize(camera: WorldCamera2D, texture: Texture2D) -> void:
	worldCamera = camera
	mapTexture = texture


func _process(_delta: float) -> void:
	_mapCanvas.queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is not InputEventMouseButton:
		return

	var mouseEvent: InputEventMouseButton = event
	if not mouseEvent.pressed:
		return

	if (
		mouseEvent.button_index != MOUSE_BUTTON_LEFT
		and mouseEvent.button_index != MOUSE_BUTTON_RIGHT
	):
		return

	accept_event()

	if not interactionEnabled:
		return

	if not is_instance_valid(worldCamera):
		return

	if not worldCamera.worldRect.has_area():
		return

	if _mapCanvas.size.x <= 0.0 or _mapCanvas.size.y <= 0.0:
		return

	var canvasPosition: Vector2 = (
		_mapCanvas.get_global_transform().affine_inverse()
		* (get_global_transform() * mouseEvent.position)
	)

	var mapRect: Rect2 = _GetMapRect()
	if not mapRect.has_point(canvasPosition):
		return

	var worldPosition: Vector2 = _MinimapToWorld(canvasPosition)
	match mouseEvent.button_index:
		MOUSE_BUTTON_LEFT:
			if worldCamera.cameraInputEnabled:
				worldCamera.MoveToWorldPosition(worldPosition)
		MOUSE_BUTTON_RIGHT:
			MoveCommandRequested.emit(worldPosition)


func SetDockSide(side: DockSide) -> void:
	dockSide = side

	var anchorX: float = 0.0
	if side == DockSide.RIGHT:
		anchorX = 1.0

	anchor_left = anchorX
	anchor_right = anchorX
	anchor_top = 1.0
	anchor_bottom = 1.0

	offset_top = -screenMargin - minimapSize.y
	offset_bottom = -screenMargin

	if side == DockSide.LEFT:
		offset_left = screenMargin
		offset_right = screenMargin + minimapSize.x
	else:
		offset_left = -screenMargin - minimapSize.x
		offset_right = -screenMargin

	queue_redraw()
	DockSideChanged.emit(side)


func _DrawMap() -> void:
	var canvasSize: Vector2 = _mapCanvas.size
	if canvasSize.x <= 0.0 or canvasSize.y <= 0.0:
		return

	_mapCanvas.draw_rect(Rect2(Vector2.ZERO, canvasSize), backgroundColor)

	if not is_instance_valid(worldCamera):
		return

	var worldRect: Rect2 = worldCamera.worldRect
	if not worldRect.has_area():
		return

	var mapRect: Rect2 = _GetMapRect()
	if mapTexture != null:
		_mapCanvas.draw_texture_rect(mapTexture, mapRect, false)

	var visibleWorldRect: Rect2 = (worldCamera.GetVisibleWorldRect().intersection(worldRect))
	if visibleWorldRect.has_area():
		var cameraRect: Rect2 = Rect2(
			_WorldToMinimap(visibleWorldRect.position),
			visibleWorldRect.size / worldRect.size * mapRect.size,
		)

		_mapCanvas.draw_rect(cameraRect, cameraFillColor)
		_mapCanvas.draw_rect(cameraRect, cameraBorderColor, false, 2.0)

	_mapCanvas.draw_rect(mapRect.grow(-0.5), borderColor, false, 1.0)


func _MinimapToWorld(minimapPosition: Vector2) -> Vector2:
	var mapRect: Rect2 = _GetMapRect()
	var normalizedPosition: Vector2 = (minimapPosition - mapRect.position) / mapRect.size

	var worldRect: Rect2 = worldCamera.worldRect

	return worldRect.position + normalizedPosition * worldRect.size


func _GetMapRect() -> Rect2:
	var availableSize: Vector2 = _mapCanvas.size
	var worldSize: Vector2 = worldCamera.worldRect.size

	var mapScale: float = minf(availableSize.x / worldSize.x, availableSize.y / worldSize.y)

	var mapSize: Vector2 = worldSize * mapScale

	return Rect2((availableSize - mapSize) * 0.5, mapSize)


func _WorldToMinimap(worldPosition: Vector2) -> Vector2:
	var worldRect: Rect2 = worldCamera.worldRect
	var mapRect: Rect2 = _GetMapRect()
	var normalizedPosition: Vector2 = (worldPosition - worldRect.position) / worldRect.size

	return mapRect.position + normalizedPosition * mapRect.size
