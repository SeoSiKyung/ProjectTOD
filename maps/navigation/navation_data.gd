class_name NavigationData
extends Resource


@export var cell_size: int = 8
@export var grid_size: Vector2i = Vector2i.ZERO
@export var world_origin: Vector2 = Vector2.ZERO

# 0 = 이동 가능
# 1 = 고정 장애물
@export var blocked: PackedByteArray = PackedByteArray()

# (grid_width + 1) * (grid_height + 1)
@export var prefix_sum: PackedInt32Array = PackedInt32Array()


func get_world_size() -> Vector2:
	return Vector2(
		grid_size.x * cell_size,
		grid_size.y * cell_size
	)


func get_world_rect() -> Rect2:
	return Rect2(
		world_origin,
		get_world_size()
	)
