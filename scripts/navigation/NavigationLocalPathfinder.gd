class_name NavigationLocalPathfinder
extends RefCounted

var _gridPathfinder: NavigationGridPathfinder
var _staticQuery: NavigationStaticQuery
var _regionQuery: NavigationRegionQuery

var _navCellSize: float
var _gridWidth: int
var _gridHeight: int
var _worldRect: Rect2

var _footprintDataByHalfSize: Dictionary[int, NavigationFootprintData] = { }


func _init(
	navigationData: NavigationData,
	gridPathfinder: NavigationGridPathfinder,
	staticQuery: NavigationStaticQuery,
	regionQuery: NavigationRegionQuery,
) -> void:
	_gridPathfinder = gridPathfinder
	_staticQuery = staticQuery
	_regionQuery = regionQuery

	_navCellSize = float(navigationData.cellSize)
	_gridWidth = navigationData.gridSize.x
	_gridHeight = navigationData.gridSize.y
	_worldRect = navigationData.GetWorldRect()

	for footprint: NavigationFootprintData in navigationData.footprints:
		if footprint == null or footprint.halfSize <= 0:
			continue

		_footprintDataByHalfSize[footprint.halfSize] = footprint


func SegmentClear(
	start: Vector2,
	end: Vector2,
	halfSize: int,
	metrics: NavigationProfileMetrics = null,
) -> bool:
	if metrics != null:
		metrics.segmentClearQueryCalls += 1

		var startTime: int = Time.get_ticks_usec()
		var result: bool = _staticQuery.SegmentClear(start, end, halfSize, metrics)

		metrics.segmentClearQueryUsec += Time.get_ticks_usec() - startTime
		return result

	return _staticQuery.SegmentClear(start, end, halfSize)


func IsSegmentClearInsideRegion(
	start: Vector2,
	end: Vector2,
	halfSize: int,
	regionId: int,
	metrics: NavigationProfileMetrics = null,
) -> bool:
	return (
		SegmentClear(start, end, halfSize, metrics)
		and _regionQuery.IsSegmentInsideRegion(start, end, regionId)
	)


func GetNearestPlaceablePoint(
	position: Vector2,
	halfSize: int,
	referencePosition: Vector2,
) -> Vector2:
	if _staticQuery.CanPlace(position, halfSize):
		return position

	var navigationMap: NavigationFootprintMapData = GetFootprintMap(halfSize)

	var pathOffset: Vector2 = GetPathLatticeOffset(halfSize)
	var centerCell: Vector2i = _WorldToNearestPathCell(position, pathOffset)
	centerCell.x = clampi(centerCell.x, 0, _gridWidth - 1)
	centerCell.y = clampi(centerCell.y, 0, _gridHeight - 1)

	var maxRadius: int = maxi(_gridWidth, _gridHeight)
	for radius: int in range(maxRadius + 1):
		var best: Vector2i = Vector2i(-1, -1)
		var bestTargetDistance: float = Math.BIG_NUMBER
		var bestReferenceDistance: float = Math.BIG_NUMBER

		var perimeterCount: int = _GetPerimeterCellCount(radius)
		for perimeterIndex: int in range(perimeterCount):
			var cell: Vector2i = _GetPerimeterCell(centerCell, radius, perimeterIndex)
			if not Grid.IsCellInGrid(cell, _gridWidth, _gridHeight):
				continue

			var index: int = Grid.CellToIndex(cell, _gridWidth)
			if navigationMap.placeableMap[index] == 0:
				continue

			var center: Vector2 = _PathCellToWorld(cell, pathOffset)
			var targetDistance: float = center.distance_squared_to(position)
			var referenceDistance: float = center.distance_squared_to(referencePosition)

			var better: bool = false
			if Math.IsLess(targetDistance, bestTargetDistance):
				better = true
			elif Math.IsNearlyEqual(targetDistance, bestTargetDistance):
				if Math.IsLess(referenceDistance, bestReferenceDistance):
					better = true
				elif Math.IsNearlyEqual(referenceDistance, bestReferenceDistance):
					if best.x < 0 or cell.y < best.y or (cell.y == best.y and cell.x < best.x):
						better = true

			if not better:
				continue

			best = cell
			bestTargetDistance = targetDistance
			bestReferenceDistance = referenceDistance

		if best.x >= 0:
			return _PathCellToWorld(best, pathOffset)

	return position


func GetComponentId(
	position: Vector2,
	halfSize: int,
	metrics: NavigationProfileMetrics = null,
) -> int:
	if not _staticQuery.CanPlace(position, halfSize):
		return -1

	var navigationMap: NavigationFootprintMapData = GetFootprintMap(halfSize)

	var pathOffset: Vector2 = GetPathLatticeOffset(halfSize)
	var pathCell: Vector2i = GetNearestPathCell(position, halfSize, pathOffset, metrics)
	if pathCell.x < 0:
		return -1

	var index: int = Grid.CellToIndex(pathCell, _gridWidth)
	return navigationMap.componentMap[index]


func GetNearestReachablePoint(
	position: Vector2,
	halfSize: int,
	referencePosition: Vector2,
	metrics: NavigationProfileMetrics = null,
) -> Vector2:
	var componentId: int = GetComponentId(referencePosition, halfSize, metrics)
	if componentId < 0:
		return referencePosition

	if GetComponentId(position, halfSize, metrics) == componentId:
		return position

	var navigationMap: NavigationFootprintMapData = GetFootprintMap(halfSize)
	var pathOffset: Vector2 = GetPathLatticeOffset(halfSize)

	var reachableCell: Vector2i = _GetNearestCellInComponent(
		position,
		pathOffset,
		componentId,
		navigationMap,
	)
	if reachableCell.x < 0:
		return referencePosition

	return _PathCellToWorld(reachableCell, pathOffset)


#region Pathfinding

func FindCompleteGridPath(
	start: Vector2,
	target: Vector2,
	halfSize: int,
	metrics: NavigationProfileMetrics = null,
) -> PackedVector2Array:
	var path: PackedVector2Array = _FindGridPath(start, target, halfSize, metrics)

	if not _PathEndsAtPoint(path, target):
		return PackedVector2Array()

	return path


func FindPathInsideRegion(
	start: Vector2,
	target: Vector2,
	halfSize: int,
	regionId: int,
	searchMarginCells: int,
	metrics: NavigationProfileMetrics = null,
) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()

	if IsSegmentClearInsideRegion(start, target, halfSize, regionId, metrics):
		result.append(target)
		return result

	result = FindLocalPath(start, target, halfSize, regionId, searchMarginCells, metrics)

	if not _PathEndsAtPoint(result, target):
		return PackedVector2Array()

	return result


func FindLocalPath(
	start: Vector2,
	target: Vector2,
	halfSize: int,
	regionId: int,
	searchMarginCells: int,
	metrics: NavigationProfileMetrics = null,
) -> PackedVector2Array:
	# 먼저 Start-Target 주변으로 제한된 A*를 시도한다.
	var quickPath: PackedVector2Array = _FindGridPathInternal(
		start,
		target,
		halfSize,
		regionId,
		searchMarginCells,
		metrics,
	)

	var completedQuickPath: PackedVector2Array = _CompleteLocalPathIfPossible(
		target,
		quickPath,
		halfSize,
		regionId,
		metrics,
	)
	if not completedQuickPath.is_empty():
		return completedQuickPath

	# 제한 범위 안에서 못 찾았으면 기존 전체 Region 탐색.
	return _FindGridPathInternal(start, target, halfSize, regionId, -1, metrics)


func _FindGridPath(
	start: Vector2,
	target: Vector2,
	halfSize: int,
	metrics: NavigationProfileMetrics = null,
) -> PackedVector2Array:
	return _FindGridPathInternal(start, target, halfSize, -1, -1, metrics)


func _FindGridPathInternal(
	start: Vector2,
	target: Vector2,
	halfSize: int,
	regionId: int,
	searchMarginCells: int = -1,
	metrics: NavigationProfileMetrics = null,
) -> PackedVector2Array:
	if metrics != null:
		metrics.gridSearchCalls += 1

	var navigationMap: NavigationFootprintMapData = GetFootprintMap(halfSize)
	var pathOffset: Vector2 = GetPathLatticeOffset(halfSize)

	var startCell: Vector2i = GetNearestPathCell(start, halfSize, pathOffset, metrics)
	var targetCell: Vector2i = GetNearestPathCell(target, halfSize, pathOffset, metrics)

	if startCell.x < 0 or targetCell.x < 0:
		return PackedVector2Array()

	var path: PackedVector2Array = _gridPathfinder.FindPath(
		startCell,
		targetCell,
		target,
		pathOffset,
		navigationMap,
		regionId,
		searchMarginCells,
		metrics,
	)
	if path.is_empty():
		return path

	var last: Vector2 = path[path.size() - 1]
	var finalPoint: Vector2 = _staticQuery.FurthestClearPoint(last, target, halfSize, metrics)
	if not Math.IsSamePoint(last, finalPoint):
		path.append(finalPoint)

	return path


func _CompleteLocalPathIfPossible(
	target: Vector2,
	path: PackedVector2Array,
	halfSize: int,
	regionId: int,
	metrics: NavigationProfileMetrics = null,
) -> PackedVector2Array:
	if path.is_empty():
		return PackedVector2Array()

	var result: PackedVector2Array = path

	var last: Vector2 = result[result.size() - 1]
	if Math.IsSamePoint(last, target):
		return result

	if not IsSegmentClearInsideRegion(last, target, halfSize, regionId, metrics):
		return PackedVector2Array()

	result.append(target)
	return result

#endregion


#region Nearest Cell Search

func GetNearestPathCell(
	position: Vector2,
	halfSize: int,
	pathOffset: Vector2,
	metrics: NavigationProfileMetrics = null,
) -> Vector2i:
	var navigationMap: NavigationFootprintMapData = GetFootprintMap(halfSize)

	var centerCell: Vector2i = _WorldToNearestPathCell(position, pathOffset)
	centerCell.x = clampi(centerCell.x, 0, _gridWidth - 1)
	centerCell.y = clampi(centerCell.y, 0, _gridHeight - 1)

	var best: Vector2i = Vector2i(-1, -1)
	var bestDistance: float = Math.BIG_NUMBER
	var maxRadius: int = maxi(_gridWidth, _gridHeight)
	for radius: int in range(maxRadius + 1):
		var perimeterCount: int = _GetPerimeterCellCount(radius)
		for perimeterIndex: int in range(perimeterCount):
			var cell: Vector2i = _GetPerimeterCell(centerCell, radius, perimeterIndex)
			if not Grid.IsCellInGrid(cell, _gridWidth, _gridHeight):
				continue

			var index: int = Grid.CellToIndex(cell, _gridWidth)
			if navigationMap.placeableMap[index] == 0:
				continue

			var center: Vector2 = _PathCellToWorld(cell, pathOffset)
			if not _staticQuery.SegmentClear(position, center, halfSize, metrics):
				continue

			var distance: float = center.distance_squared_to(position)
			if Math.IsLess(distance, bestDistance):
				bestDistance = distance
				best = cell
			elif Math.IsNearlyEqual(distance, bestDistance):
				if best.x < 0 or cell.y < best.y or (cell.y == best.y and cell.x < best.x):
					best = cell

		if (
			best.x >= 0
			and _IsNearestCellSearchComplete(
				position,
				centerCell,
				pathOffset,
				radius + 1,
				bestDistance,
			)
		):
			break

	return best


func _GetNearestCellInComponent(
	position: Vector2,
	pathOffset: Vector2,
	componentId: int,
	navigationMap: NavigationFootprintMapData,
) -> Vector2i:
	var centerCell: Vector2i = _WorldToNearestPathCell(position, pathOffset)
	centerCell.x = clampi(centerCell.x, 0, _gridWidth - 1)
	centerCell.y = clampi(centerCell.y, 0, _gridHeight - 1)

	var best: Vector2i = Vector2i(-1, -1)
	var bestDistance: float = Math.BIG_NUMBER
	var maxRadius: int = maxi(_gridWidth, _gridHeight)
	for radius: int in range(maxRadius + 1):
		var perimeterCount: int = _GetPerimeterCellCount(radius)
		for perimeterIndex: int in range(perimeterCount):
			var cell: Vector2i = _GetPerimeterCell(centerCell, radius, perimeterIndex)
			if not Grid.IsCellInGrid(cell, _gridWidth, _gridHeight):
				continue

			var index: int = Grid.CellToIndex(cell, _gridWidth)
			if navigationMap.componentMap[index] != componentId:
				continue

			var point: Vector2 = _PathCellToWorld(cell, pathOffset)
			var distance: float = point.distance_squared_to(position)
			if Math.IsLess(distance, bestDistance):
				bestDistance = distance
				best = cell

		if (
			best.x >= 0
			and _IsNearestCellSearchComplete(
				position,
				centerCell,
				pathOffset,
				radius + 1,
				bestDistance,
			)
		):
			break

	return best


func _GetPerimeterCellCount(radius: int) -> int:
	if radius == 0:
		return 1

	return radius * 8


func _GetPerimeterCell(centerCell: Vector2i, radius: int, perimeterIndex: int) -> Vector2i:
	if radius == 0:
		return centerCell

	var minX: int = centerCell.x - radius
	var maxX: int = centerCell.x + radius
	var minY: int = centerCell.y - radius
	var maxY: int = centerCell.y + radius

	var diameter: int = radius * 2
	var horizontalCount: int = diameter + 1

	# 위쪽 변: 왼쪽 → 오른쪽
	if perimeterIndex < horizontalCount:
		return Vector2i(minX + perimeterIndex, minY)
	perimeterIndex -= horizontalCount

	# 좌 / 우 변: 위 → 아래
	var sideCount: int = (diameter - 1) * 2
	if perimeterIndex < sideCount:
		var rowOffset: int = (perimeterIndex >> 1) + 1
		var x: int = minX
		if (perimeterIndex & 1) != 0:
			x = maxX

		return Vector2i(x, minY + rowOffset)

	perimeterIndex -= sideCount
	# 아래쪽 변: 왼쪽 → 오른쪽
	return Vector2i(minX + perimeterIndex, maxY)


func _IsNearestCellSearchComplete(
	position: Vector2,
	centerCell: Vector2i,
	pathOffset: Vector2,
	nextRadius: int,
	bestDistance: float,
) -> bool:
	var center: Vector2 = _PathCellToWorld(centerCell, pathOffset)
	var offset: Vector2 = position - center
	var radiusDistance: float = float(nextRadius) * _navCellSize

	var minXDistance: float = maxf(radiusDistance - absf(offset.x), 0.0)
	var minYDistance: float = maxf(radiusDistance - absf(offset.y), 0.0)
	var outerMinDistance: float = minf(minXDistance, minYDistance)

	return Math.IsGreater(outerMinDistance * outerMinDistance, bestDistance)

#endregion


#region Footprint Data

func GetFootprintMap(halfSize: int) -> NavigationFootprintMapData:
	var footprintData: NavigationFootprintData = _GetFootprintData(halfSize)
	if footprintData == null:
		return null

	return footprintData.navigationMap


func _GetFootprintData(halfSize: int) -> NavigationFootprintData:
	if not _footprintDataByHalfSize.has(halfSize):
		return null

	return _footprintDataByHalfSize[halfSize]

#endregion


#region Coordinates

func GetPathLatticeOffset(halfSize: int) -> Vector2:
	var offset: float = _LatticeAxisOffset(float(halfSize))
	return Vector2(offset, offset)


func _LatticeAxisOffset(halfExtent: float) -> float:
	var offset: float = fposmod(maxf(halfExtent, 0.0), _navCellSize)
	if Math.IsNearlyZero(offset) or Math.IsNearlyZero(_navCellSize - offset):
		return 0.0

	return offset


func _PathCellToWorld(cell: Vector2i, pathOffset: Vector2) -> Vector2:
	return (
		_worldRect.position
		+ Vector2(
			float(cell.x) * _navCellSize + pathOffset.x,
			float(cell.y) * _navCellSize + pathOffset.y,
		)
	)


func _WorldToNearestPathCell(position: Vector2, pathOffset: Vector2) -> Vector2i:
	var local: Vector2 = position - _worldRect.position - pathOffset
	return Vector2i(roundi(local.x / _navCellSize), roundi(local.y / _navCellSize))

#endregion


func _PathEndsAtPoint(path: PackedVector2Array, point: Vector2) -> bool:
	if path.is_empty():
		return false

	return Math.IsSamePoint(path[path.size() - 1], point)
