class_name NavigationPortalData
extends Resource

@export var id: int = -1

# PNG에 그려진 Portal 선분
@export var startCell: Vector2i = Vector2i(-1, -1)
@export var endCell: Vector2i = Vector2i(-1, -1)

# Portal 양쪽의 Region
@export var regionA: int = -1
@export var regionB: int = -1

# 인접한 Portal ID 배열
@export var neighborPortalIds: PackedInt32Array = PackedInt32Array()
