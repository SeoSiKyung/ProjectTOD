class_name DefenseDeploymentGridView
extends Node2D

const GRID_COLOR: Color = Color(0.58, 0.34, 0.12, 0.28)
const PLACEABLE_FILL_COLOR: Color = Color(0.72, 0.58, 0.22, 0.10)
const PLACEABLE_BORDER_COLOR: Color = Color(0.84, 0.68, 0.30, 0.66)
const HOVER_FILL_COLOR: Color = Color(0.94, 0.72, 0.22, 0.18)
const HOVER_BORDER_COLOR: Color = Color(0.98, 0.78, 0.30, 0.96)
const FOCUS_FILL_COLOR: Color = Color(0.55, 0.28, 0.08, 0.16)
const FOCUS_BORDER_COLOR: Color = Color(1.0, 0.72, 0.15, 1.0)
const PREVIEW_ALPHA: float = 0.58
const PREVIEW_MARGIN: float = 18.0

signal CellClicked(cell: Vector2i)
signal CellRightClicked(cell: Vector2i)

var _grid: DefenseDeploymentGrid
var _canInteractCell: Callable
var _canPlaceCell: Callable

var _hoverCell: Vector2i = Vector2i.ZERO
var _hasHoverCell: bool = false

var _focusedCell: Vector2i = Vector2i.ZERO
var _hasFocusedCell: bool = false

var _mouseCell: Vector2i = Vector2i.ZERO
var _hasMouseCell: bool = false

var _isHoverLocked: bool = false
var _placementPreviewTexture: Texture2D


func _process(_delta: float) -> void:
	if _grid == null:
		return

	if _isHoverLocked:
		return

	var mousePosition: Vector2 = get_global_mouse_position()
	var cell: Vector2i = _grid.WorldToCell(mousePosition)

	if _hasMouseCell and cell == _mouseCell:
		return

	_hasMouseCell = true
	_mouseCell = cell

	if not _CanHoverCell(cell):
		if not _hasHoverCell:
			return

		_hasHoverCell = false
		queue_redraw()
		return

	if _hasHoverCell and cell == _hoverCell:
		return

	_hasHoverCell = true
	_hoverCell = cell

	queue_redraw()


func _draw() -> void:
	if _grid == null:
		return

	_DrawGrid()

	if _hasHoverCell:
		_DrawHoverCell()

	if _hasFocusedCell:
		_DrawFocusedCell()


func _unhandled_input(event: InputEvent) -> void:
	if _grid == null:
		return

	if _isHoverLocked:
		return

	if event is not InputEventMouseButton:
		return

	var mouseEvent: InputEventMouseButton = event
	if not mouseEvent.pressed:
		return

	var cell: Vector2i = _grid.WorldToCell(get_global_mouse_position())

	match mouseEvent.button_index:
		MOUSE_BUTTON_LEFT:
			if _placementPreviewTexture != null and not _CanPlaceCell(cell):
				return
			if not _CanInteractCell(cell):
				return

			CellClicked.emit(cell)

		MOUSE_BUTTON_RIGHT:
			if not _CanInteractCell(cell):
				return

			CellRightClicked.emit(cell)


func Initialize(
	grid: DefenseDeploymentGrid,
	canInteractCell: Callable,
	canPlaceCell: Callable,
) -> void:
	_grid = grid
	_canInteractCell = canInteractCell
	_canPlaceCell = canPlaceCell

	_hasHoverCell = false
	_hasFocusedCell = false
	_hasMouseCell = false
	_isHoverLocked = false
	_placementPreviewTexture = null

	queue_redraw()


func SetPlacementPreview(texture: Texture2D) -> void:
	_placementPreviewTexture = texture
	queue_redraw()


func LockHoverCell(cell: Vector2i) -> void:
	if not _CanInteractCell(cell):
		return

	_isHoverLocked = true
	_hasHoverCell = true
	_hoverCell = cell

	queue_redraw()


func UnlockHoverCell() -> void:
	_isHoverLocked = false
	_hasMouseCell = false
	queue_redraw()


func SetFocusedCell(cell: Vector2i) -> void:
	if _grid == null or not _grid.IsValidCell(cell):
		ClearFocusedCell()
		return

	_focusedCell = cell
	_hasFocusedCell = true

	queue_redraw()


func ClearFocusedCell() -> void:
	if not _hasFocusedCell:
		return

	_hasFocusedCell = false
	queue_redraw()


func _DrawGrid() -> void:
	for y: int in range(_grid.gridSize.y):
		for x: int in range(_grid.gridSize.x):
			var cell: Vector2i = Vector2i(x, y)

			if _placementPreviewTexture != null:
				if not _CanPlaceCell(cell):
					continue

				var placeableRect: Rect2 = _GetCellRect(cell)
				draw_rect(placeableRect, PLACEABLE_FILL_COLOR, true)
				draw_rect(placeableRect, PLACEABLE_BORDER_COLOR, false, 2.0)
				continue

			if not _CanInteractCell(cell):
				continue

			var rect: Rect2 = _GetCellRect(cell)
			draw_rect(rect, GRID_COLOR, false, 2.0)


func _DrawHoverCell() -> void:
	var rect: Rect2 = _GetCellRect(_hoverCell)

	draw_rect(rect, HOVER_FILL_COLOR, true)
	draw_rect(rect, HOVER_BORDER_COLOR, false, 3.0)

	if _placementPreviewTexture == null:
		return

	var previewRect: Rect2 = rect.grow(-PREVIEW_MARGIN)
	draw_texture_rect(
		_placementPreviewTexture,
		previewRect,
		false,
		Color(1.0, 1.0, 1.0, PREVIEW_ALPHA),
	)


func _DrawFocusedCell() -> void:
	var rect: Rect2 = _GetCellRect(_focusedCell)

	draw_rect(rect, FOCUS_FILL_COLOR, true)
	draw_rect(rect, FOCUS_BORDER_COLOR, false, 4.0)


func _GetCellRect(cell: Vector2i) -> Rect2:
	var worldPosition: Vector2 = (_grid.worldOrigin + Vector2(cell) * _grid.cellSize)
	var localPosition: Vector2 = to_local(worldPosition)

	return Rect2(localPosition, Vector2.ONE * _grid.cellSize)


func _CanHoverCell(cell: Vector2i) -> bool:
	if _placementPreviewTexture != null:
		return _CanPlaceCell(cell)

	return _CanInteractCell(cell)


func _CanPlaceCell(cell: Vector2i) -> bool:
	if not _grid.IsValidCell(cell):
		return false

	if not _canPlaceCell.is_valid():
		return _CanInteractCell(cell)

	return _canPlaceCell.call(cell)


func _CanInteractCell(cell: Vector2i) -> bool:
	if not _grid.IsValidCell(cell):
		return false

	if not _canInteractCell.is_valid():
		return true

	return _canInteractCell.call(cell)
