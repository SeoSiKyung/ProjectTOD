class_name DefenseDeploymentGrid
extends RefCounted

var cellSize: int
var worldOrigin: Vector2
var gridSize: Vector2i


func _init(pCellSize: int, pWorldOrigin: Vector2, pGridSize: Vector2i) -> void:
	cellSize = pCellSize
	worldOrigin = pWorldOrigin
	gridSize = pGridSize


func WorldToCell(worldPosition: Vector2) -> Vector2i:
	var localPosition: Vector2 = worldPosition - worldOrigin
	return Vector2i(floori(localPosition.x / cellSize), floori(localPosition.y / cellSize))


func CellToWorld(cell: Vector2i) -> Vector2:
	return (
		worldOrigin + Vector2((float(cell.x) + 0.5) * cellSize, (float(cell.y) + 0.5) * cellSize)
	)


func IsValidCell(cell: Vector2i) -> bool:
	return (cell.x >= 0 and cell.y >= 0 and cell.x < gridSize.x and cell.y < gridSize.y)
