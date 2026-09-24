class_name NavigationRegionQuery
extends RefCounted

var _navCellSize: float
var _gridWidth: int
var _gridHeight: int
var _worldRect: Rect2

var _portalMap: PackedByteArray
var _regionMap: PackedInt32Array

var _portalFoundRegions: Dictionary[int, bool] = { }
var _portalVisited: Dictionary[int, bool] = { }
var _portalQueue: Array[Vector2i] = []


func _init(navigationData: NavigationData) -> void:
	_navCellSize = float(navigationData.cellSize)
	_gridWidth = navigationData.gridSize.x
	_gridHeight = navigationData.gridSize.y
	_worldRect = navigationData.GetWorldRect()

	_portalMap = navigationData.portalMap
	_regionMap = navigationData.regionMap


func FillRegionIds(result: Array[int], position: Vector2) -> void:
	result.clear()

	var cell: Vector2i = _WorldToCellFloor(position)
	if not Grid.IsCellInGrid(cell, _gridWidth, _gridHeight):
		return

	var index: int = Grid.CellToIndex(cell, _gridWidth)
	var regionId: int = _regionMap[index]

	if regionId >= 0:
		result.append(regionId)
		return

	if _portalMap[index] == 0:
		return

	_FillPortalRegionIds(result, cell)


func IsSegmentInsideRegion(start: Vector2, end: Vector2, regionId: int) -> bool:
	var distance: float = start.distance_to(end)
	if distance <= Math.EPSILON:
		return true

	var stepLength: float = _navCellSize * 0.5
	var stepCount: int = maxi(1, ceili(distance / stepLength))

	for step: int in range(stepCount + 1):
		var ratio: float = float(step) / float(stepCount)
		var point: Vector2 = start.lerp(end, ratio)
		var cell: Vector2i = _WorldToCellFloor(point)
		if not Grid.IsCellInGrid(cell, _gridWidth, _gridHeight):
			return false

		var index: int = Grid.CellToIndex(cell, _gridWidth)
		if _regionMap[index] == regionId:
			continue

		# Portal 셀은 해당 Region의 경계 공간으로 취급한다.
		if _portalMap[index] != 0:
			continue

		return false

	return true


func _FillPortalRegionIds(result: Array[int], startCell: Vector2i) -> void:
	_portalFoundRegions.clear()
	_portalVisited.clear()
	_portalQueue.clear()

	var startIndex: int = Grid.CellToIndex(startCell, _gridWidth)

	_portalQueue.append(startCell)
	_portalVisited[startIndex] = true

	var head: int = 0
	while head < _portalQueue.size():
		var currentCell: Vector2i = _portalQueue[head]
		head += 1

		for direction: Vector2i in Math.DIRECTIONS_8:
			var nextCell: Vector2i = currentCell + direction
			if not Grid.IsCellInGrid(nextCell, _gridWidth, _gridHeight):
				continue

			var nextIndex: int = Grid.CellToIndex(nextCell, _gridWidth)
			var regionId: int = _regionMap[nextIndex]
			if regionId >= 0:
				if not _portalFoundRegions.has(regionId):
					_portalFoundRegions[regionId] = true
					result.append(regionId)

				continue

			if _portalMap[nextIndex] == 0 or _portalVisited.has(nextIndex):
				continue

			_portalVisited[nextIndex] = true
			_portalQueue.append(nextCell)


func _WorldToCellFloor(position: Vector2) -> Vector2i:
	var local: Vector2 = position - _worldRect.position
	return Vector2i(floori(local.x / _navCellSize), floori(local.y / _navCellSize))
