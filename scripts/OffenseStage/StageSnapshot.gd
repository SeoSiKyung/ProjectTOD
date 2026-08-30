class_name StageSnapshot
extends RefCounted

const MIN_SPATIAL_CELL_SIZE: float = 0.001

var _spatialCellSize: float = 64.0
var _positionsByUnitId: Dictionary[int, Vector2] = {}
var _unitIds: Array[int] = []
var _spatialIndex: Dictionary[Vector2i, Array] = {}


func Ready(tick: int, positionsByUnitId: Dictionary[int, Vector2], spatialCellSize: float = 64.0) -> void:
	_spatialCellSize = maxf(spatialCellSize, MIN_SPATIAL_CELL_SIZE)

	for unitId: int in positionsByUnitId:
		_positionsByUnitId[unitId] = positionsByUnitId[unitId]
		_unitIds.append(unitId)

	_unitIds.sort()
	_buildSpatialIndex()

func GetSpatialCellSize() -> float:
	return _spatialCellSize

func GetUnitCount() -> int:
	return _unitIds.size()

func HasUnit(unitId: int) -> bool:
	return _positionsByUnitId.has(unitId)

func GetPosition(unitId: int) -> Vector2:
	if not _positionsByUnitId.has(unitId):
		push_error("StageSnapshot에 unitId %d가 없습니다." % unitId)
		return Vector2.ZERO

	return _positionsByUnitId[unitId]

func GetUnitIds() -> Array[int]:
	return _unitIds.duplicate()

func FindUnitIdsInRadius(center: Vector2, radius: float) -> Array[int]:
	var result: Array[int] = []

	if radius < 0.0:
		push_error("검색 반경은 0 이상이어야 합니다.")
		return result

	var radiusVector: Vector2 = Vector2(radius, radius)
	var minCell: Vector2i = _getCell(center - radiusVector)
	var maxCell: Vector2i = _getCell(center + radiusVector)
	var radiusSquared: float = radius * radius

	for cellX: int in range(minCell.x, maxCell.x + 1):
		for cellY: int in range(minCell.y, maxCell.y + 1):
			var cell: Vector2i = Vector2i(cellX, cellY)

			if not _spatialIndex.has(cell):
				continue

			var cellUnitIds: Array = _spatialIndex[cell]

			for unitId: int in cellUnitIds:
				var unitPosition: Vector2 = _positionsByUnitId[unitId]

				if center.distance_squared_to(unitPosition) <= radiusSquared:
					result.append(unitId)

	result.sort()
	return result

func FindUnitIdsInBounds(center: Vector2, halfExtent: Vector2) -> Array[int]:
	var result: Array[int] = []
	var extent: Vector2 = Vector2(absf(halfExtent.x), absf(halfExtent.y))
	var minPosition: Vector2 = center - extent
	var maxPosition: Vector2 = center + extent
	var minCell: Vector2i = _getCell(minPosition)
	var maxCell: Vector2i = _getCell(maxPosition)

	for cellX: int in range(minCell.x, maxCell.x + 1):
		for cellY: int in range(minCell.y, maxCell.y + 1):
			var cell: Vector2i = Vector2i(cellX, cellY)

			if not _spatialIndex.has(cell):
				continue

			var cellUnitIds: Array = _spatialIndex[cell]

			for unitId: int in cellUnitIds:
				var unitPosition: Vector2 = _positionsByUnitId[unitId]

				if unitPosition.x < minPosition.x or unitPosition.x > maxPosition.x:
					continue

				if unitPosition.y < minPosition.y or unitPosition.y > maxPosition.y:
					continue

				result.append(unitId)

	result.sort()
	return result

func _buildSpatialIndex() -> void:
	for unitId: int in _unitIds:
		var cell: Vector2i = _getCell(_positionsByUnitId[unitId])

		if not _spatialIndex.has(cell):
			var newCellUnitIds: Array[int] = []
			_spatialIndex[cell] = newCellUnitIds

		var cellUnitIds: Array = _spatialIndex[cell]
		cellUnitIds.append(unitId)

func _getCell(position: Vector2) -> Vector2i:
	return Vector2i(
		floori(position.x / _spatialCellSize),
		floori(position.y / _spatialCellSize),
	)
