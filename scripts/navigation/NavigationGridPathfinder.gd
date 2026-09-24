class_name NavigationGridPathfinder
extends RefCounted

const PATH_REGION_PORTAL: int = -2
const HEURISTIC_WEIGHT: float = 1.5
const TARGET_STAMP_MAX_GENERATION: int = 2_147_483_647

var _gridWidth: int
var _gridHeight: int
var _navCellSize: float
var _worldRect: Rect2

var lastExpandedCount: int = 0
var lastRelaxedCount: int = 0
var lastSearchArea: int = 0

var _state: NavigationPathSearchState = NavigationPathSearchState.new()

var _targetStamp: PackedInt32Array = PackedInt32Array()
var _targetGeneration: int = 0

var _heap: NavigationPathHeap


func _init(gridWidth: int, gridHeight: int, navCellSize: float, worldRect: Rect2) -> void:
	_gridWidth = gridWidth
	_gridHeight = gridHeight
	_navCellSize = navCellSize
	_worldRect = worldRect

	var totalCellCount: int = _gridWidth * _gridHeight
	_state.Resize(totalCellCount)

	_targetStamp.resize(totalCellCount)

	_heap = NavigationPathHeap.new(_state)


func FindPath(
	startCell: Vector2i,
	targetCell: Vector2i,
	target: Vector2,
	pathOffset: Vector2,
	navigationMap: NavigationFootprintMapData,
	regionId: int,
	searchMarginCells: int,
	metrics: NavigationProfileMetrics = null,
) -> PackedVector2Array:
	var startIndex: int = Grid.CellToIndex(startCell, _gridWidth)
	var targetIndex: int = Grid.CellToIndex(targetCell, _gridWidth)

	var startComponent: int = navigationMap.componentMap[startIndex]
	var targetComponent: int = navigationMap.componentMap[targetIndex]
	if startComponent < 0 or targetComponent < 0:
		return PackedVector2Array()

	if targetComponent != startComponent:
		return PackedVector2Array()

	var useSearchBounds: bool = searchMarginCells >= 0

	var searchMinX: int = 0
	var searchMinY: int = 0
	var searchMaxX: int = _gridWidth - 1
	var searchMaxY: int = _gridHeight - 1
	if useSearchBounds:
		searchMinX = maxi(0, mini(startCell.x, targetCell.x) - searchMarginCells)
		searchMinY = maxi(0, mini(startCell.y, targetCell.y) - searchMarginCells)
		searchMaxX = mini(_gridWidth - 1, maxi(startCell.x, targetCell.x) + searchMarginCells)
		searchMaxY = mini(_gridHeight - 1, maxi(startCell.y, targetCell.y) + searchMarginCells)

	var startH: float = Math.OctileDistance(startCell, targetCell)
	_BeginPathSearch(startIndex, startH, HEURISTIC_WEIGHT)

	var bestIndex: int = startIndex
	var bestTargetDistance: float = _PathCellToWorld(startCell, pathOffset).distance_squared_to(
		target
	)

	while not _heap.IsEmpty():
		var currentIndex: int = int(_heap.Pop())
		if _state.IsClosed(currentIndex):
			continue

		_state.MarkClosed(currentIndex)
		if metrics != null:
			metrics.gridExpanded += 1

		var curCell: Vector2i = Grid.IndexToCell(currentIndex, _gridWidth)
		var curWorld: Vector2 = _PathCellToWorld(curCell, pathOffset)

		var targetDistance: float = curWorld.distance_squared_to(target)
		if targetDistance < bestTargetDistance - Math.EPSILON:
			bestTargetDistance = targetDistance
			bestIndex = currentIndex
		elif absf(targetDistance - bestTargetDistance) <= Math.EPSILON and currentIndex < bestIndex:
			bestIndex = currentIndex

		if currentIndex == targetIndex:
			bestIndex = currentIndex
			break

		# 8방향에 대해 A* 알고리즘을 수행
		var previousDirection: int = _state.incomingDirection[currentIndex]

		var staticWalkMask: int = navigationMap.walkMask[currentIndex]
		var currentPathRegionId: int = navigationMap.pathRegionMap[currentIndex]

		# 일반 Region 셀에서는 미리 계산된 Region 전용 mask를 사용할 수 있다.
		# Portal 셀에서는 진입한 Region에 따라 허용 방향이 달라지므로 일반 walkMask를 사용한 뒤 Runtime에서 Region을 검사한다.
		var useRegionWalkMask: bool = regionId >= 0 and currentPathRegionId == regionId

		var walkMask: int = staticWalkMask
		if useRegionWalkMask:
			walkMask = navigationMap.regionWalkMask[currentIndex]

		for dirIndex: int in range(Math.DIRECTIONS_8.size()):
			var directionBit: int = 1 << dirIndex
			var direction: Vector2i = Math.DIRECTIONS_8[dirIndex]
			var nextCell: Vector2i = curCell + direction

			# Local Path에서는 target cell 자체를 예외적으로 허용하고 있기 때문에 Region mask가 막더라도 static 이동이 가능하고 target이면 Runtime 판정으로 넘긴다.
			var targetException: bool = regionId >= 0 and nextCell == targetCell

			if walkMask & directionBit == 0:
				if (
					not useRegionWalkMask or not targetException
					or (staticWalkMask & directionBit) == 0
				):
					continue

			if (
				useSearchBounds
				and (
					not (searchMinX <= nextCell.x and nextCell.x <= searchMaxX)
					or not (searchMinY <= nextCell.y and nextCell.y <= searchMaxY)
				)
			):
				continue

			var nextIndex: int = Grid.CellToIndex(nextCell, _gridWidth)
			if _state.IsClosed(nextIndex):
				continue

			# Region mask를 사용할 수 없는 Portal 셀 또는 target cell 예외인 경우에만 Runtime Region 판정.
			if regionId >= 0 and (not useRegionWalkMask or targetException):
				if not _IsLocalPathCellAllowed(nextCell, regionId, targetCell, navigationMap):
					continue

				# 정적 Corner Cutting 여부는 walkMask에 이미 포함되어 있다.
				# 여기서는 Local Region 경계를 대각선으로 가로지르는지만 추가 검사.
				if direction.x != 0 and direction.y != 0:
					var horizontal: Vector2i = Vector2i(curCell.x + direction.x, curCell.y)
					var vertical: Vector2i = Vector2i(curCell.x, curCell.y + direction.y)
					if not _IsLocalPathCellAllowed(horizontal, regionId, targetCell, navigationMap):
						continue
					if not _IsLocalPathCellAllowed(vertical, regionId, targetCell, navigationMap):
						continue

			_state.Touch(nextIndex)

			# 이동 비용 계산
			var stepCost: float = 1.0
			if direction.x != 0 and direction.y != 0:
				stepCost = Math.SQRT_2

			var directionChange: float = 0.0
			if previousDirection >= 0:
				var difference: int = absi(dirIndex - previousDirection)
				difference = mini(difference, 8 - difference)
				directionChange = float(difference)

			var tentativeG: float = _state.g[currentIndex] + stepCost
			var tentativeTurn: float = _state.turnCost[currentIndex] + directionChange

			var better: bool = false
			if tentativeG < _state.g[nextIndex] - Math.EPSILON:
				better = true
			elif (
				absf(tentativeG - _state.g[nextIndex]) <= Math.EPSILON
				and tentativeTurn < _state.turnCost[nextIndex] - Math.EPSILON
			):
				better = true

			if not better:
				continue

			if metrics != null:
				metrics.gridRelaxed += 1

			_state.g[nextIndex] = tentativeG
			_state.turnCost[nextIndex] = tentativeTurn
			_state.parent[nextIndex] = currentIndex
			_state.incomingDirection[nextIndex] = dirIndex

			# 목적지까지의 남은 예상 거리 계산
			var h: float = Math.OctileDistance(nextCell, targetCell)
			_state.h[nextIndex] = h
			_state.f[nextIndex] = tentativeG + h * HEURISTIC_WEIGHT

			_heap.PushOrUpdate(nextIndex)

	return _ReconstructPath(_state.parent, startIndex, bestIndex, pathOffset)


func FillPathsToTargets(
	result: Dictionary[int, PackedVector2Array],
	startCell: Vector2i,
	targetCells: Array[Vector2i],
	pathOffset: Vector2,
	navigationMap: NavigationFootprintMapData,
	regionId: int,
	searchMarginCells: int,
) -> void:
	result.clear()

	lastExpandedCount = 0
	lastRelaxedCount = 0
	lastSearchArea = 0

	if targetCells.is_empty():
		return

	var startIndex: int = Grid.CellToIndex(startCell, _gridWidth)

	var singleTargetMode: bool = targetCells.size() == 1
	var heuristicWeight: float = 1.0
	var singleTargetCell: Vector2i = Vector2i(-1, -1)

	# Target이 하나뿐이면 기존 Local A*와 동일한 Weighted A* 사용.
	if singleTargetMode:
		heuristicWeight = HEURISTIC_WEIGHT
		singleTargetCell = targetCells[0]

	# Portal 하나의 Anchor들은 서로 가까우므로 Start ↔ Target 주변으로만 먼저 탐색한다.
	var searchMinX: int = startCell.x
	var searchMinY: int = startCell.y
	var searchMaxX: int = startCell.x
	var searchMaxY: int = startCell.y

	for targetCell: Vector2i in targetCells:
		searchMinX = mini(searchMinX, targetCell.x)
		searchMinY = mini(searchMinY, targetCell.y)
		searchMaxX = maxi(searchMaxX, targetCell.x)
		searchMaxY = maxi(searchMaxY, targetCell.y)

	searchMinX = maxi(0, searchMinX - searchMarginCells)
	searchMinY = maxi(0, searchMinY - searchMarginCells)
	searchMaxX = mini(_gridWidth - 1, searchMaxX + searchMarginCells)
	searchMaxY = mini(_gridHeight - 1, searchMaxY + searchMarginCells)

	lastSearchArea = ((searchMaxX - searchMinX + 1) * (searchMaxY - searchMinY + 1))

	var startH: float
	if singleTargetMode:
		startH = Math.OctileDistance(startCell, singleTargetCell)
	else:
		startH = _GetNearestTargetHeuristic(startCell, targetCells)

	_BeginPathSearch(startIndex, startH, heuristicWeight)

	_BeginTargetGeneration()

	var remainingTargetCount: int = 0
	for targetCell: Vector2i in targetCells:
		var targetIndex: int = Grid.CellToIndex(targetCell, _gridWidth)
		if _targetStamp[targetIndex] == _targetGeneration:
			continue

		_targetStamp[targetIndex] = _targetGeneration
		remainingTargetCount += 1

	while not _heap.IsEmpty():
		if remainingTargetCount <= 0:
			break

		var currentIndex: int = int(_heap.Pop())
		if _state.IsClosed(currentIndex):
			continue

		_state.MarkClosed(currentIndex)
		lastExpandedCount += 1

		if _targetStamp[currentIndex] == _targetGeneration:
			var path: PackedVector2Array = _ReconstructPath(
				_state.parent,
				startIndex,
				currentIndex,
				pathOffset,
			)
			if not path.is_empty():
				result[currentIndex] = path

			_targetStamp[currentIndex] = 0
			remainingTargetCount -= 1
			if remainingTargetCount <= 0:
				break

		var currentCell: Vector2i = Grid.IndexToCell(currentIndex, _gridWidth)

		var previousDirection: int = _state.incomingDirection[currentIndex]

		var currentPathRegionId: int = navigationMap.pathRegionMap[currentIndex]

		var useRegionWalkMask: bool = currentPathRegionId == regionId

		var walkMask: int
		if useRegionWalkMask:
			walkMask = navigationMap.regionWalkMask[currentIndex]
		else:
			walkMask = navigationMap.walkMask[currentIndex]

		for dirIndex: int in range(Math.DIRECTIONS_8.size()):
			if walkMask & (1 << dirIndex) == 0:
				continue

			var direction: Vector2i = Math.DIRECTIONS_8[dirIndex]
			var nextCell: Vector2i = currentCell + direction
			if (
				not (searchMinX <= nextCell.x and nextCell.x <= searchMaxX)
				or not (searchMinY <= nextCell.y and nextCell.y <= searchMaxY)
			):
				continue

			var nextIndex: int = Grid.CellToIndex(nextCell, _gridWidth)
			if _state.IsClosed(nextIndex):
				continue

			if not useRegionWalkMask:
				var pathRegionId: int = navigationMap.pathRegionMap[nextIndex]
				if pathRegionId != regionId and pathRegionId != PATH_REGION_PORTAL:
					continue

				# Portal 셀에서 대각선으로 빠져나갈 때만 side cell Region을 Runtime 검사.
				if direction.x != 0 and direction.y != 0:
					var horizontalIndex: int = currentIndex + direction.x
					var horizontalRegionId: int = navigationMap.pathRegionMap[horizontalIndex]
					if horizontalRegionId != regionId and horizontalRegionId != PATH_REGION_PORTAL:
						continue

					var verticalIndex: int = currentIndex + direction.y * _gridWidth
					var verticalRegionId: int = navigationMap.pathRegionMap[verticalIndex]
					if verticalRegionId != regionId and verticalRegionId != PATH_REGION_PORTAL:
						continue

			_state.Touch(nextIndex)

			var stepCost: float = 1.0
			if direction.x != 0 and direction.y != 0:
				stepCost = Math.SQRT_2

			var directionChange: float = 0.0
			if previousDirection >= 0:
				var difference: int = absi(dirIndex - previousDirection)
				difference = mini(difference, 8 - difference)
				directionChange = float(difference)

			var tentativeG: float = _state.g[currentIndex] + stepCost
			var tentativeTurn: float = _state.turnCost[currentIndex] + directionChange
			var better: bool = false
			if tentativeG < _state.g[nextIndex] - Math.EPSILON:
				better = true
			elif (
				absf(tentativeG - _state.g[nextIndex]) <= Math.EPSILON
				and tentativeTurn < _state.turnCost[nextIndex] - Math.EPSILON
			):
				better = true

			if not better:
				continue

			lastRelaxedCount += 1

			_state.g[nextIndex] = tentativeG
			_state.turnCost[nextIndex] = tentativeTurn
			_state.parent[nextIndex] = currentIndex
			_state.incomingDirection[nextIndex] = dirIndex

			var h: float
			if singleTargetMode:
				h = Math.OctileDistance(nextCell, singleTargetCell)
			else:
				h = _GetNearestTargetHeuristic(nextCell, targetCells)

			_state.h[nextIndex] = h
			_state.f[nextIndex] = tentativeG + h * heuristicWeight

			_heap.PushOrUpdate(nextIndex)


func _BeginPathSearch(startIndex: int, startH: float, heuristicWeight: float) -> void:
	_heap.Clear()

	_state.BeginSearch()
	_state.Touch(startIndex)

	_state.f[startIndex] = startH * heuristicWeight
	_state.g[startIndex] = 0.0
	_state.h[startIndex] = startH
	_state.turnCost[startIndex] = 0.0

	_heap.PushOrUpdate(startIndex)


func _ReconstructPath(
	parent: PackedInt32Array,
	startIndex: int,
	destinationIndex: int,
	pathOffset: Vector2,
) -> PackedVector2Array:
	var count: int = 0
	var current: int = destinationIndex
	while current >= 0:
		count += 1

		if current == startIndex:
			break

		current = parent[current]

	if current != startIndex:
		return PackedVector2Array()

	var result: PackedVector2Array = PackedVector2Array()
	result.resize(count)

	current = destinationIndex
	for index: int in range(count - 1, -1, -1):
		result[index] = _PathCellToWorld(Grid.IndexToCell(current, _gridWidth), pathOffset)

		if current == startIndex:
			break

		current = parent[current]

	return result


func _IsLocalPathCellAllowed(
	pathCell: Vector2i,
	regionId: int,
	targetPathCell: Vector2i,
	navigationMap: NavigationFootprintMapData,
) -> bool:
	if not Grid.IsCellInGrid(pathCell, _gridWidth, _gridHeight):
		return false

	if pathCell == targetPathCell:
		return true

	var pathRegionId: int = navigationMap.pathRegionMap[Grid.CellToIndex(pathCell, _gridWidth)]
	return pathRegionId == regionId or pathRegionId == PATH_REGION_PORTAL


func _PathCellToWorld(cell: Vector2i, pathOffset: Vector2) -> Vector2:
	return (
		_worldRect.position
		+ Vector2(
			float(cell.x) * _navCellSize + pathOffset.x,
			float(cell.y) * _navCellSize + pathOffset.y,
		)
	)


func _GetNearestTargetHeuristic(cell: Vector2i, targetCells: Array[Vector2i]) -> float:
	var best: float = Math.BIG_NUMBER
	for targetCell: Vector2i in targetCells:
		best = minf(best, Math.OctileDistance(cell, targetCell))

	return best


func _BeginTargetGeneration() -> void:
	if _targetGeneration >= TARGET_STAMP_MAX_GENERATION:
		_targetStamp.fill(0)
		_targetGeneration = 1
		return

	_targetGeneration += 1
