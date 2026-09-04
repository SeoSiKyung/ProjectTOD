class_name DefenseDeploymentGridView
extends Node2D

const GRID_COLOR: Color = Color(1.0, 0.0, 0.0, 0.4)

const DEPLOYMENT_FILL_COLOR: Color = Color(0.0, 1.0, 0.0, 0.35)
const DEPLOYMENT_BORDER_COLOR: Color = Color(0.0, 1.0, 0.0, 0.9)

const HOVER_FILL_COLOR: Color = Color(0.0, 1.0, 0.0, 0.2)
const HOVER_BORDER_COLOR: Color = Color(0.0, 1.0, 0.0, 0.9)

signal CellClicked(cell: Vector2i)
signal CellRightClicked(cell: Vector2i)

var _grid: DefenseDeploymentGrid

var _deploymentCells: Dictionary = { }

var _hoverCell: Vector2i = Vector2i.ZERO
var _hasHoverCell: bool = false


func Initialize(grid: DefenseDeploymentGrid) -> void:
	_grid = grid

	queue_redraw()


func _process(_delta: float) -> void:
	if _grid == null:
		return

	var mousePosition: Vector2 = get_global_mouse_position()
	var cell: Vector2i = _grid.WorldToCell(mousePosition)

	if not _grid.IsValidCell(cell):
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
	_DrawDeployments()

	if _hasHoverCell:
		_DrawHoverCell()


func _unhandled_input(event: InputEvent) -> void:
	if _grid == null:
		return

	if event is not InputEventMouseButton:
		return

	var mouseEvent: InputEventMouseButton = event
	if not mouseEvent.pressed:
		return

	var cell: Vector2i = _grid.WorldToCell(get_global_mouse_position())
	if not _grid.IsValidCell(cell):
		return

	match mouseEvent.button_index:
		MOUSE_BUTTON_LEFT:
			CellClicked.emit(cell)

		MOUSE_BUTTON_RIGHT:
			CellRightClicked.emit(cell)


func SetDeployment(cell: Vector2i) -> void:
	_deploymentCells[cell] = true

	queue_redraw()


func RemoveDeployment(cell: Vector2i) -> void:
	_deploymentCells.erase(cell)

	queue_redraw()


func _DrawGrid() -> void:
	var origin: Vector2 = to_local(_grid.worldOrigin)

	var width: float = _grid.gridSize.x * _grid.cellSize
	var height: float = _grid.gridSize.y * _grid.cellSize

	for x: int in range(_grid.gridSize.x + 1):
		var xPosition: float = origin.x + x * _grid.cellSize
		draw_line(
			Vector2(xPosition, origin.y),
			Vector2(xPosition, origin.y + height),
			GRID_COLOR,
			2.0,
		)

	for y: int in range(_grid.gridSize.y + 1):
		var yPosition: float = origin.y + y * _grid.cellSize
		draw_line(
			Vector2(origin.x, yPosition),
			Vector2(origin.x + width, yPosition),
			GRID_COLOR,
			2.0,
		)


func _DrawDeployments() -> void:
	for cell: Vector2i in _deploymentCells:
		var rect: Rect2 = _GetCellRect(cell)

		draw_rect(rect, DEPLOYMENT_FILL_COLOR, true)
		draw_rect(rect, DEPLOYMENT_BORDER_COLOR, false, 4.0)


func _DrawHoverCell() -> void:
	var rect: Rect2 = _GetCellRect(_hoverCell)

	draw_rect(rect, HOVER_FILL_COLOR, true)
	draw_rect(rect, HOVER_BORDER_COLOR, false, 3.0)


func _GetCellRect(cell: Vector2i) -> Rect2:
	var worldPosition: Vector2 = (_grid.worldOrigin + Vector2(cell) * _grid.cellSize)
	var localPosition: Vector2 = to_local(worldPosition)

	return Rect2(localPosition, Vector2.ONE * _grid.cellSize)
