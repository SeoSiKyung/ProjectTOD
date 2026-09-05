class_name NavigationData
extends Resource

@export var cellSize: int = 8
@export var gridSize: Vector2i = Vector2i.ZERO
@export var worldOrigin: Vector2 = Vector2.ZERO

# 0 = 이동 가능
# 1 = 고정 장애물
@export var blocked: PackedByteArray = PackedByteArray()

# (grid_width + 1) * (grid_height + 1)
@export var prefixSum: PackedInt32Array = PackedInt32Array()


func GetWorldSize() -> Vector2:
	return Vector2(gridSize.x * cellSize, gridSize.y * cellSize)


func GetWorldRect() -> Rect2:
	return Rect2(worldOrigin, GetWorldSize())
