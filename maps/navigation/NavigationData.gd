class_name NavigationData
extends Resource

@export var cellSize: int = 8
@export var gridSize: Vector2i = Vector2i.ZERO
@export var worldOrigin: Vector2 = Vector2.ZERO

# 0 = 이동 가능, 1 = 고정 장애물
@export var blocked: PackedByteArray = PackedByteArray()

# (gridWidth + 1) * (gridHeight + 1)
@export var prefixSum: PackedInt32Array = PackedInt32Array()

# 0 = Portal 아님, 1 = Portal cell
@export var portalMap: PackedByteArray = PackedByteArray()

# 각 cell이 속한 Region ID
# -1 = 장애물 또는 Portal
@export var regionMap: PackedInt32Array = PackedInt32Array()

@export var regions: Array[NavigationRegionData] = []
@export var portals: Array[NavigationPortalData] = []

# 유닛 halfSize별로 Bake된 Portal 이동 데이터
@export var footprints: Array[NavigationFootprintData] = []


func GetWorldSize() -> Vector2:
	return Vector2(gridSize.x * cellSize, gridSize.y * cellSize)


func GetWorldRect() -> Rect2:
	return Rect2(worldOrigin, GetWorldSize())
