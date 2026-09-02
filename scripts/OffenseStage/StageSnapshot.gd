class_name StageSnapshot
extends RefCounted

const SPATIAL_CELL_SIZE: float = 64.0

var _positionsByUnitId: Dictionary[int, Vector2] = {}
var _halfSizesByUnitId: Dictionary[int, int] = {}
var _minCellsByUnitId: Dictionary[int, Vector2i] = {}
var _maxCellsByUnitId: Dictionary[int, Vector2i] = {}
var _unitIdsByCell: Dictionary[Vector2i, Array] = {}
var _unitIds: Array[int] = []


func GetUnitCount() -> int:
	return _unitIds.size()


func HasUnit(unitId: int) -> bool:
	return _positionsByUnitId.has(unitId)


func GetPosition(unitId: int) -> Vector2:
	if not _positionsByUnitId.has(unitId):
		push_error("StageSnapshot에 unitId %d가 없습니다." % unitId)
		return Vector2.ZERO

	return _positionsByUnitId[unitId]


func GetHalfSize(unitId: int) -> int:
	if not _halfSizesByUnitId.has(unitId):
		push_error("StageSnapshot에 unitId %d가 없습니다." % unitId)
		return 0

	return _halfSizesByUnitId[unitId]


func GetUnitIds() -> Array[int]:
	return _unitIds.duplicate()


func RegisterUnit(unitId: int, position: Vector2, halfSize: int) -> void:
	if _positionsByUnitId.has(unitId):
		push_error("StageSnapshot에 unitId %d가 이미 등록되어 있습니다." % unitId)
		return

	if halfSize < 0:
		push_error("halfSize는 0 이상이어야 합니다.")
		return

	var extent: Vector2 = Vector2(float(halfSize), float(halfSize))
	var minCell: Vector2i = _getCell(position - extent)
	var maxCell: Vector2i = _getCell(position + extent)

	_positionsByUnitId[unitId] = position
	_halfSizesByUnitId[unitId] = halfSize
	_minCellsByUnitId[unitId] = minCell
	_maxCellsByUnitId[unitId] = maxCell
	_unitIds.append(unitId)
	_addUnitToCells(unitId, minCell, maxCell)


func UnregisterUnit(unitId: int) -> void:
	if not _positionsByUnitId.has(unitId):
		return

	_removeUnitFromCells(
		unitId,
		_minCellsByUnitId[unitId],
		_maxCellsByUnitId[unitId],
	)

	_positionsByUnitId.erase(unitId)
	_halfSizesByUnitId.erase(unitId)
	_minCellsByUnitId.erase(unitId)
	_maxCellsByUnitId.erase(unitId)
	_unitIds.erase(unitId)


func UpdateUnit(unitId: int, position: Vector2, halfSize: int) -> void:
	if not _positionsByUnitId.has(unitId):
		push_error("StageSnapshot에 unitId %d가 없습니다." % unitId)
		return

	if halfSize < 0:
		push_error("halfSize는 0 이상이어야 합니다.")
		return

	var oldMinCell: Vector2i = _minCellsByUnitId[unitId]
	var oldMaxCell: Vector2i = _maxCellsByUnitId[unitId]
	var extent: Vector2 = Vector2(float(halfSize), float(halfSize))
	var newMinCell: Vector2i = _getCell(position - extent)
	var newMaxCell: Vector2i = _getCell(position + extent)

	_positionsByUnitId[unitId] = position
	_halfSizesByUnitId[unitId] = halfSize

	if oldMinCell == newMinCell and oldMaxCell == newMaxCell:
		return

	_removeUnitFromCells(unitId, oldMinCell, oldMaxCell)
	_addUnitToCells(unitId, newMinCell, newMaxCell)
	_minCellsByUnitId[unitId] = newMinCell
	_maxCellsByUnitId[unitId] = newMaxCell


func UpdatePosition(unitId: int, position: Vector2) -> void:
	if not _halfSizesByUnitId.has(unitId):
		push_error("StageSnapshot에 unitId %d가 없습니다." % unitId)
		return

	UpdateUnit(unitId, position, _halfSizesByUnitId[unitId])


func UpdateHalfSize(unitId: int, halfSize: int) -> void:
	if not _positionsByUnitId.has(unitId):
		push_error("StageSnapshot에 unitId %d가 없습니다." % unitId)
		return

	UpdateUnit(unitId, _positionsByUnitId[unitId], halfSize)


func Clear() -> void:
	_positionsByUnitId.clear()
	_halfSizesByUnitId.clear()
	_minCellsByUnitId.clear()
	_maxCellsByUnitId.clear()
	_unitIdsByCell.clear()
	_unitIds.clear()


func FindUnitIdsInCircle(center: Vector2, radius: float) -> Array[int]:
	var result: Array[int] = []

	if radius < 0.0:
		push_error("검색 반경은 0 이상이어야 합니다.")
		return result

	var radiusVector: Vector2 = Vector2(radius, radius)
	var minCell: Vector2i = _getCell(center - radiusVector)
	var maxCell: Vector2i = _getCell(center + radiusVector)
	var radiusSquared: float = radius * radius
	var candidateUnitIds: Array[int] = _collectCandidateUnitIds(minCell, maxCell)

	for unitId: int in candidateUnitIds:
		if _intersectsCircle(unitId, center, radiusSquared):
			result.append(unitId)

	return result


func FindUnitIdsInRect(center: Vector2, halfExtent: Vector2) -> Array[int]:
	var result: Array[int] = []
	var extent: Vector2 = Vector2(absf(halfExtent.x), absf(halfExtent.y))
	var minCell: Vector2i = _getCell(center - extent)
	var maxCell: Vector2i = _getCell(center + extent)
	var candidateUnitIds: Array[int] = _collectCandidateUnitIds(minCell, maxCell)

	for unitId: int in candidateUnitIds:
		if _intersectsRect(unitId, center, extent):
			result.append(unitId)

	return result


func FindUnitIdsInRadius(center: Vector2, radius: float) -> Array[int]:
	return FindUnitIdsInCircle(center, radius)


func FindUnitIdsInBounds(center: Vector2, halfExtent: Vector2) -> Array[int]:
	return FindUnitIdsInRect(center, halfExtent)


func _intersectsCircle(
	unitId: int,
	center: Vector2,
	radiusSquared: float
) -> bool:
	var unitPosition: Vector2 = _positionsByUnitId[unitId]
	var halfSize: float = float(_halfSizesByUnitId[unitId])
	var minPosition: Vector2 = unitPosition - Vector2(halfSize, halfSize)
	var maxPosition: Vector2 = unitPosition + Vector2(halfSize, halfSize)
	var closestPoint: Vector2 = Vector2(
		clampf(center.x, minPosition.x, maxPosition.x),
		clampf(center.y, minPosition.y, maxPosition.y),
	)

	return center.distance_squared_to(closestPoint) <= radiusSquared


func _intersectsRect(
	unitId: int,
	center: Vector2,
	halfExtent: Vector2
) -> bool:
	var unitPosition: Vector2 = _positionsByUnitId[unitId]
	var halfSize: float = float(_halfSizesByUnitId[unitId])

	return (
		absf(unitPosition.x - center.x) <= halfExtent.x + halfSize
		and absf(unitPosition.y - center.y) <= halfExtent.y + halfSize
	)


func _collectCandidateUnitIds(
	minCell: Vector2i,
	maxCell: Vector2i
) -> Array[int]:
	var result: Array[int] = []
	var collectedUnitIds: Dictionary[int, bool] = {}

	for cellX: int in range(minCell.x, maxCell.x + 1):
		for cellY: int in range(minCell.y, maxCell.y + 1):
			var cell: Vector2i = Vector2i(cellX, cellY)

			if not _unitIdsByCell.has(cell):
				continue

			var cellUnitIds: Array = _unitIdsByCell[cell]

			for unitId: int in cellUnitIds:
				if collectedUnitIds.has(unitId):
					continue

				collectedUnitIds[unitId] = true
				result.append(unitId)

	return result


func _addUnitToCells(
	unitId: int,
	minCell: Vector2i,
	maxCell: Vector2i
) -> void:
	for cellX: int in range(minCell.x, maxCell.x + 1):
		for cellY: int in range(minCell.y, maxCell.y + 1):
			var cell: Vector2i = Vector2i(cellX, cellY)

			if not _unitIdsByCell.has(cell):
				var newCellUnitIds: Array[int] = []
				_unitIdsByCell[cell] = newCellUnitIds

			var cellUnitIds: Array = _unitIdsByCell[cell]
			cellUnitIds.append(unitId)


func _removeUnitFromCells(
	unitId: int,
	minCell: Vector2i,
	maxCell: Vector2i
) -> void:
	for cellX: int in range(minCell.x, maxCell.x + 1):
		for cellY: int in range(minCell.y, maxCell.y + 1):
			var cell: Vector2i = Vector2i(cellX, cellY)

			if not _unitIdsByCell.has(cell):
				continue

			var cellUnitIds: Array = _unitIdsByCell[cell]
			cellUnitIds.erase(unitId)

			if cellUnitIds.is_empty():
				_unitIdsByCell.erase(cell)


func _getCell(position: Vector2) -> Vector2i:
	return Vector2i(
		floori(position.x / SPATIAL_CELL_SIZE),
		floori(position.y / SPATIAL_CELL_SIZE),
	)z
