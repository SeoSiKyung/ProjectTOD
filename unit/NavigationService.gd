class_name NavigationService
extends Node

const EPSILON: float = 0.00001
const CONTACT_EPSILON: float = 0.001
const BIG_NUMBER: float = 1.0e30
const SQRT_2: float = 1.41421356237

@export var navigationData: NavigationData
@export_range(0.0, 2.0, 0.05) var staticContactSlop: float = 1.0

var _navigationReady: bool = false
var _navCellSize: float = 8.0
var _gridWidth: int = 0
var _gridHeight: int = 0
var _worldRect: Rect2 = Rect2()
var _blocked: PackedByteArray = PackedByteArray()
var _prefixSum: PackedInt32Array = PackedInt32Array()

var _pathState: PathSearchState = PathSearchState.new()
var _footprintMaps: Dictionary[int, FootprintNavigationMap] = { }


class PathSearchState:
	var f: PackedFloat64Array = PackedFloat64Array()
	var g: PackedFloat64Array = PackedFloat64Array()
	var h: PackedFloat64Array = PackedFloat64Array()
	var turnCost: PackedFloat64Array = PackedFloat64Array()

	var parent: PackedInt32Array = PackedInt32Array()
	var incomingDirection: PackedInt32Array = PackedInt32Array()
	var closed: PackedByteArray = PackedByteArray()
	var heapPosition: PackedInt32Array = PackedInt32Array()


	func Resize(size: int) -> void:
		f.resize(size)
		g.resize(size)
		h.resize(size)
		turnCost.resize(size)

		parent.resize(size)
		incomingDirection.resize(size)
		closed.resize(size)
		heapPosition.resize(size)


	func Reset() -> void:
		f.fill(BIG_NUMBER)
		g.fill(BIG_NUMBER)
		h.fill(BIG_NUMBER)
		turnCost.fill(BIG_NUMBER)

		parent.fill(-1)
		incomingDirection.fill(-1)
		closed.fill(0)
		heapPosition.fill(-1)


class FootprintNavigationMap:
	var placeableMap: PackedByteArray = PackedByteArray()
	var componentMap: PackedInt32Array = PackedInt32Array()


const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(1, 1),
	Vector2i(0, 1),
	Vector2i(-1, 1),
	Vector2i(-1, 0),
	Vector2i(-1, -1),
	Vector2i(0, -1),
	Vector2i(1, -1),
]


func _ready() -> void:
	_LoadNavigationData()


func IsReady() -> bool:
	return _navigationReady


func Reload() -> void:
	_LoadNavigationData()


func _LoadNavigationData() -> void:
	_navigationReady = false

	if navigationData == null:
		push_error("NavigationData가 지정되지 않았습니다.")
		return

	_navCellSize = float(navigationData.cellSize)
	_gridWidth = navigationData.gridSize.x
	_gridHeight = navigationData.gridSize.y
	_worldRect = navigationData.GetWorldRect()
	_blocked = navigationData.blocked
	_prefixSum = navigationData.prefixSum

	if _navCellSize <= 0.0:
		push_error("NavigationData의 cell_size가 잘못되었습니다.")
		return

	var expectedBlocked: int = _gridWidth * _gridHeight
	var expectedPrefix: int = (_gridWidth + 1) * (_gridHeight + 1)

	if _blocked.size() != expectedBlocked:
		push_error("NavigationData의 blocked 크기가 잘못되었습니다.")
		return

	if _prefixSum.size() != expectedPrefix:
		push_error("NavigationData의 prefix_sum 크기가 잘못되었습니다.")
		return

	_EnsurePathBuffers()
	_footprintMaps.clear()

	_navigationReady = true


func _EnsurePathBuffers() -> void:
	var total: int = _gridWidth * _gridHeight
	if _pathState.g.size() == total:
		return

	_pathState.Resize(total)


func _ResetPathBuffers() -> void:
	_pathState.Reset()


func _GetFootprintMap(halfSize: int) -> FootprintNavigationMap:
	if _footprintMaps.has(halfSize):
		return _footprintMaps[halfSize]

	var navigationMap: FootprintNavigationMap = _MakeFootprintMap(halfSize)
	_footprintMaps[halfSize] = navigationMap

	return navigationMap


func _MakeFootprintMap(halfSize: int) -> FootprintNavigationMap:
	var navigationMap: FootprintNavigationMap = FootprintNavigationMap.new()
	var pathOffset: Vector2 = _PathLatticeOffset(halfSize)
	var total: int = _gridWidth * _gridHeight

	navigationMap.placeableMap.resize(total)
	navigationMap.placeableMap.fill(0)
	for index: int in range(total):
		var cell: Vector2i = _IndexToCell(index)
		var center: Vector2 = _PathCellToWorld(cell, pathOffset)

		if CanPlaceStatic(center, halfSize):
			navigationMap.placeableMap[index] = 1

	navigationMap.componentMap.resize(total)
	navigationMap.componentMap.fill(-1)

	var componentId: int = 0
	var queue: Array[int] = []
	for startIndex: int in range(total):
		if (
			navigationMap.placeableMap[startIndex] == 0
			or navigationMap.componentMap[startIndex] >= 0
		):
			continue

		queue.clear()
		queue.append(startIndex)
		navigationMap.componentMap[startIndex] = componentId

		var head: int = 0
		while head < queue.size():
			var currentIndex: int = queue[head]
			head += 1

			var currentCell: Vector2i = _IndexToCell(currentIndex)
			for direction: Vector2i in DIRECTIONS:
				var nextCell: Vector2i = currentCell + direction
				if not _IsValidCell(nextCell):
					continue

				var nextIndex: int = _CellToIndex(nextCell)
				if (
					navigationMap.placeableMap[nextIndex] == 0
					or navigationMap.componentMap[nextIndex] >= 0
				):
					continue

				if direction.x != 0 and direction.y != 0:
					var horizontal: Vector2i = Vector2i(currentCell.x + direction.x, currentCell.y)
					var vertical: Vector2i = Vector2i(currentCell.x, currentCell.y + direction.y)

					if (
						navigationMap.placeableMap[_CellToIndex(horizontal)] == 0
						or navigationMap.placeableMap[_CellToIndex(vertical)] == 0
					):
						continue

				navigationMap.componentMap[nextIndex] = componentId
				queue.append(nextIndex)

		componentId += 1

	return navigationMap


func _GetNearestCellInComponent(
	position: Vector2,
	pathOffset: Vector2,
	componentId: int,
	navigationMap: FootprintNavigationMap,
) -> Vector2i:
	var centerCell: Vector2i = _WorldToNearestPathCell(position, pathOffset)
	centerCell.x = clampi(centerCell.x, 0, _gridWidth - 1)
	centerCell.y = clampi(centerCell.y, 0, _gridHeight - 1)

	var best: Vector2i = Vector2i(-1, -1)
	var bestDistance: float = BIG_NUMBER

	var maxRadius: int = maxi(_gridWidth, _gridHeight)
	for radius: int in range(maxRadius + 1):
		for y: int in range(centerCell.y - radius, centerCell.y + radius + 1):
			for x: int in range(centerCell.x - radius, centerCell.x + radius + 1):
				if maxi(absi(x - centerCell.x), absi(y - centerCell.y)) != radius:
					continue

				var cell: Vector2i = Vector2i(x, y)
				if not _IsValidCell(cell):
					continue

				var index: int = _CellToIndex(cell)
				if navigationMap.componentMap[index] != componentId:
					continue

				var point: Vector2 = _PathCellToWorld(cell, pathOffset)
				var distance: float = point.distance_squared_to(position)
				if distance < bestDistance - EPSILON:
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


func _CollisionHalf(aHalf: Vector2, bHalf: Vector2) -> Vector2:
	return Vector2(
		maxf(EPSILON, aHalf.x + bHalf.x - CONTACT_EPSILON),
		maxf(EPSILON, aHalf.y + bHalf.y - CONTACT_EPSILON),
	)


func _SegmentAabbEntryFraction(start: Vector2, delta: Vector2, half: Vector2) -> float:
	var tMin: float = 0.0
	var tMax: float = 1.0

	if absf(delta.x) <= EPSILON:
		if start.x < -half.x or start.x > half.x:
			return -1.0
	else:
		var tx1: float = (-half.x - start.x) / delta.x
		var tx2: float = (half.x - start.x) / delta.x

		if tx1 > tx2:
			var tempX: float = tx1
			tx1 = tx2
			tx2 = tempX

		tMin = maxf(tMin, tx1)
		tMax = minf(tMax, tx2)

		if tMin > tMax:
			return -1.0

	if absf(delta.y) <= EPSILON:
		if start.y < -half.y or start.y > half.y:
			return -1.0
	else:
		var ty1: float = (-half.y - start.y) / delta.y
		var ty2: float = (half.y - start.y) / delta.y

		if ty1 > ty2:
			var tempY: float = ty1
			ty1 = ty2
			ty2 = tempY

		tMin = maxf(tMin, ty1)
		tMax = minf(tMax, ty2)

		if tMin > tMax:
			return -1.0

	if tMax < 0.0:
		return -1.0

	if tMin > 1.0:
		return -1.0

	return clampf(tMin, 0.0, 1.0)


func _SegmentIntersectsCenteredAabb(start: Vector2, end: Vector2, half: Vector2) -> bool:
	return _SegmentAabbEntryFraction(start, end - start, half) >= 0.0


func SegmentClear(start: Vector2, end: Vector2, halfSize: int) -> bool:
	return _IsStaticSegmentClear(start, end, halfSize)


func _PrefixRectCount(x0: int, y0: int, x1: int, y1: int) -> int:
	var width: int = (_gridWidth + 1)
	return (
		_prefixSum[y1 * width + x1] - _prefixSum[y0 * width + x1] - _prefixSum[y1 * width + x0]
		+ _prefixSum[y0 * width + x0]
	)


func CanPlaceStatic(center: Vector2, halfSize: int) -> bool:
	return _CanPlaceStaticWithHalf(center, _StaticHalfSize(halfSize))


func _StaticHalfSize(halfSize: int) -> float:
	return maxf(0.0, float(halfSize) - maxf(staticContactSlop, 0.0))


func _CanPlaceStaticWithHalf(center: Vector2, halfSize: float) -> bool:
	var worldEnd: Vector2 = _worldRect.position + _worldRect.size

	var half: Vector2 = Vector2(halfSize, halfSize)
	var rectMin: Vector2 = center - half
	var rectMax: Vector2 = center + half

	if rectMin.x < _worldRect.position.x - EPSILON:
		return false

	if rectMin.y < _worldRect.position.y - EPSILON:
		return false

	if rectMax.x > worldEnd.x + EPSILON:
		return false

	if rectMax.y > worldEnd.y + EPSILON:
		return false

	var localMin: Vector2 = rectMin - _worldRect.position
	var localMax: Vector2 = rectMax - _worldRect.position
	var minX: int = floori((localMin.x + EPSILON) / _navCellSize)
	var minY: int = floori((localMin.y + EPSILON) / _navCellSize)
	var maxX: int = floori((localMax.x - EPSILON) / _navCellSize)
	var maxY: int = floori((localMax.y - EPSILON) / _navCellSize)

	minX = clampi(minX, 0, _gridWidth - 1)
	minY = clampi(minY, 0, _gridHeight - 1)
	maxX = clampi(maxX, 0, _gridWidth - 1)
	maxY = clampi(maxY, 0, _gridHeight - 1)

	return _PrefixRectCount(minX, minY, maxX + 1, maxY + 1) == 0


func GetNearestPlaceablePoint(
	position: Vector2,
	halfSize: int,
	referencePosition: Vector2,
) -> Vector2:
	if CanPlaceStatic(position, halfSize):
		return position

	var pathOffset: Vector2 = _PathLatticeOffset(halfSize)
	var centerCell: Vector2i = _WorldToNearestPathCell(position, pathOffset)
	centerCell.x = clampi(centerCell.x, 0, _gridWidth - 1)
	centerCell.y = clampi(centerCell.y, 0, _gridHeight - 1)
	var maxRadius: int = maxi(_gridWidth, _gridHeight)

	for radius: int in range(maxRadius + 1):
		var best: Vector2i = Vector2i(-1, -1)
		var bestTargetDistance: float = BIG_NUMBER
		var bestReferenceDistance: float = BIG_NUMBER

		for y: int in range(centerCell.y - radius, centerCell.y + radius + 1):
			for x: int in range(centerCell.x - radius, centerCell.x + radius + 1):
				var ringDistance: int = maxi(absi(x - centerCell.x), absi(y - centerCell.y))

				if ringDistance != radius:
					continue

				var cell: Vector2i = Vector2i(x, y)

				if not _IsValidCell(cell):
					continue

				var center: Vector2 = _PathCellToWorld(cell, pathOffset)
				if not CanPlaceStatic(center, halfSize):
					continue

				var targetDistance: float = center.distance_squared_to(position)
				var referenceDistance: float = center.distance_squared_to(referencePosition)
				var better: bool = false

				if targetDistance < bestTargetDistance - EPSILON:
					better = true
				elif absf(targetDistance - bestTargetDistance) <= EPSILON:
					if referenceDistance < bestReferenceDistance - EPSILON:
						better = true
					elif absf(referenceDistance - bestReferenceDistance) <= EPSILON:
						if best.x < 0 or y < best.y or (y == best.y and x < best.x):
							better = true

				if not better:
					continue

				best = cell
				bestTargetDistance = targetDistance
				bestReferenceDistance = referenceDistance

		if best.x >= 0:
			return _PathCellToWorld(best, pathOffset)

	return position


func GetNearestReachablePoint(
	position: Vector2,
	halfSize: int,
	referencePosition: Vector2,
) -> Vector2:
	var pathOffset: Vector2 = _PathLatticeOffset(halfSize)
	var navigationMap: FootprintNavigationMap = _GetFootprintMap(halfSize)

	var referenceCell: Vector2i = _GetNearestPathCell(referencePosition, halfSize, pathOffset, true)
	if referenceCell.x < 0:
		return referencePosition

	var referenceIndex: int = _CellToIndex(referenceCell)
	var componentId: int = navigationMap.componentMap[referenceIndex]
	if componentId < 0:
		return referencePosition

	var cell: Vector2i = _GetNearestCellInComponent(
		position,
		pathOffset,
		componentId,
		navigationMap,
	)
	if cell.x < 0:
		return referencePosition

	return _PathCellToWorld(cell, pathOffset)


func FindPath(start: Vector2, target: Vector2, halfSize: int) -> PackedVector2Array:
	var empty: PackedVector2Array = PackedVector2Array()
	if not _navigationReady:
		return empty

	var pathOffset: Vector2 = _PathLatticeOffset(halfSize)
	var navigationMap: FootprintNavigationMap = _GetFootprintMap(halfSize)

	var startCell: Vector2i = _GetNearestPathCell(start, halfSize, pathOffset, true)
	var targetCell: Vector2i = _GetNearestPathCell(target, halfSize, pathOffset, false)
	if startCell.x < 0 or targetCell.x < 0:
		return empty

	var startIndex: int = _CellToIndex(startCell)
	var targetIndex: int = _CellToIndex(targetCell)

	var startComponent: int = navigationMap.componentMap[startIndex]
	var targetComponent: int = navigationMap.componentMap[targetIndex]
	if startComponent < 0:
		return empty

	if targetComponent != startComponent:
		targetCell = _GetNearestCellInComponent(target, pathOffset, startComponent, navigationMap)
		if targetCell.x < 0:
			return empty

		targetIndex = _CellToIndex(targetCell)

	_EnsurePathBuffers()
	_ResetPathBuffers()
	_pathState.g[startIndex] = 0.0
	_pathState.turnCost[startIndex] = 0.0

	var heap: Array[int] = []
	var startH: float = _OctileHeuristic(startCell, targetCell)
	_pathState.h[startIndex] = startH
	_pathState.f[startIndex] = startH * 1.5

	_HeapInsertOrDecrease(heap, startIndex)

	var bestIndex: int = startIndex
	var bestTargetDistance: float = (
		_PathCellToWorld(startCell, pathOffset).distance_squared_to(target)
	)

	var foundGoal: bool = false
	while not heap.is_empty():
		var currentIndex: int = _HeapPop(heap)
		if _pathState.closed[currentIndex] != 0:
			continue

		_pathState.closed[currentIndex] = 1

		var curCell: Vector2i = _IndexToCell(currentIndex)
		var curWorld: Vector2 = _PathCellToWorld(curCell, pathOffset)

		var targetDistance: float = curWorld.distance_squared_to(target)
		if targetDistance < bestTargetDistance - EPSILON:
			bestTargetDistance = targetDistance
			bestIndex = currentIndex
		elif (absf(targetDistance - bestTargetDistance) <= EPSILON and currentIndex < bestIndex):
			bestIndex = currentIndex
		if currentIndex == targetIndex:
			foundGoal = true
			bestIndex = currentIndex
			break

		# 8방향에 대해 A* 알고리즘을 수행
		var previousDirection: int = _pathState.incomingDirection[currentIndex]
		for dirIndex: int in range(DIRECTIONS.size()):
			var direction: Vector2i = DIRECTIONS[dirIndex]
			var nextCell: Vector2i = curCell + direction
			if not _IsValidCell(nextCell):
				continue

			var nextIndex: int = _CellToIndex(nextCell)
			if _pathState.closed[nextIndex] != 0 or navigationMap.placeableMap[nextIndex] == 0:
				continue

			# 대각선 검사
			if direction.x != 0 and direction.y != 0:
				var horizontal: Vector2i = Vector2i(curCell.x + direction.x, curCell.y)
				var vertical: Vector2i = Vector2i(curCell.x, curCell.y + direction.y)
				if not _IsValidCell(horizontal) or not _IsValidCell(vertical):
					continue

				if (
					navigationMap.placeableMap[_CellToIndex(horizontal)] == 0
					or navigationMap.placeableMap[_CellToIndex(vertical)] == 0
				):
					continue

			# 이동 비용 계산
			var stepCost: float = 1.0
			if direction.x != 0 and direction.y != 0:
				stepCost = SQRT_2

			var directionChange: float = 0.0
			if previousDirection >= 0:
				var difference: int = absi(dirIndex - previousDirection)
				difference = mini(difference, 8 - difference)
				directionChange = float(difference)

			var tentativeG: float = _pathState.g[currentIndex] + stepCost
			var tentativeTurn: float = _pathState.turnCost[currentIndex] + directionChange

			var better: bool = false
			if tentativeG < _pathState.g[nextIndex] - EPSILON:
				better = true
			elif (
				absf(tentativeG - _pathState.g[nextIndex]) <= EPSILON
				and tentativeTurn < _pathState.turnCost[nextIndex] - EPSILON
			):
				better = true

			if not better:
				continue

			_pathState.g[nextIndex] = tentativeG
			_pathState.turnCost[nextIndex] = tentativeTurn
			_pathState.parent[nextIndex] = currentIndex
			_pathState.incomingDirection[nextIndex] = dirIndex

			# 목적지까지의 남은 예상 거리 계산
			var h: float = _OctileHeuristic(nextCell, targetCell)
			_pathState.h[nextIndex] = h
			_pathState.f[nextIndex] = tentativeG + h * 1.5
			_HeapInsertOrDecrease(heap, nextIndex)

	var destinationIndex: int = bestIndex
	if foundGoal:
		destinationIndex = targetIndex

	var path: Array[Vector2] = _ReconstructPath(
		_pathState.parent,
		startIndex,
		destinationIndex,
		pathOffset,
	)
	var pathSize: int = path.size()
	if pathSize == 0:
		return empty

	var last: Vector2 = path[pathSize - 1]
	var finalPoint: Vector2 = _FurthestStaticClearPoint(last, target, halfSize)
	if last.distance_squared_to(finalPoint) > EPSILON:
		path.append(finalPoint)

	var compressedPath: Array[Vector2] = _CompressPath(path)
	return _ShortcutPath(start, compressedPath, halfSize)


func BuildUnitPath(unit: Unit, slot: Vector2, anchorPath: PackedVector2Array) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	if anchorPath.is_empty():
		return result

	var anchorPathSize: int = anchorPath.size()
	var unitPosition: Vector2 = unit.position
	var halfSize: int = unit.GetHalfSize()

	# 1. 가능한 한 목적지 쪽 Anchor 선분에 직선으로 합류
	for segmentIndex: int in range(anchorPathSize - 2, -1, -1):
		var segmentStart: Vector2 = anchorPath[segmentIndex]
		var segmentEnd: Vector2 = anchorPath[segmentIndex + 1]
		var joinPoint: Vector2 = Geometry2D.get_closest_point_to_segment(
			unitPosition,
			segmentStart,
			segmentEnd,
		)

		if not SegmentClear(unitPosition, joinPoint, halfSize):
			continue

		if unitPosition.distance_squared_to(joinPoint) > EPSILON:
			result.append(joinPoint)

		for index: int in range(segmentIndex + 1, anchorPathSize):
			result.append(anchorPath[index])

		if (result.is_empty() or result[result.size() - 1].distance_squared_to(slot) > EPSILON):
			result.append(slot)

		return result

	# 2. Anchor waypoint 자체로 직선 합류 가능한지 검사
	for index: int in range(anchorPathSize - 1, -1, -1):
		if not SegmentClear(unitPosition, anchorPath[index], halfSize):
			continue

		for pathIndex: int in range(index, anchorPathSize):
			result.append(anchorPath[pathIndex])

		if (result.is_empty() or result[result.size() - 1].distance_squared_to(slot) > EPSILON):
			result.append(slot)

		return result

	# 3. 직선 합류가 불가능하면 가장 가까운 Anchor 지점까지 짧은 A*
	var joinData: Vector3 = _ClosestAnchorJoin(unitPosition, anchorPath)
	var joinNextIndex: int = int(joinData.z)
	if joinNextIndex < 0:
		return result

	var joinPoint: Vector2 = Vector2(joinData.x, joinData.y)
	var localPath: PackedVector2Array = FindPath(unitPosition, joinPoint, halfSize)
	if localPath.is_empty():
		return result

	# FindPath가 partial path를 반환한 경우 Anchor에 실제로 합류한 게 아니므로 실패 처리
	var localGoal: Vector2 = localPath[localPath.size() - 1]
	if localGoal.distance_to(joinPoint) > _navCellSize * 2.0:
		return result

	for point: Vector2 in localPath:
		result.append(point)

	# 합류한 선분 다음 waypoint부터 Anchor 경로를 이어 붙인다.
	for index: int in range(joinNextIndex, anchorPathSize):
		var point: Vector2 = anchorPath[index]

		if (result.is_empty() or result[result.size() - 1].distance_squared_to(point) > EPSILON):
			result.append(point)

	# 마지막으로 각 유닛의 formation slot
	if (result.is_empty() or result[result.size() - 1].distance_squared_to(slot) > EPSILON):
		result.append(slot)

	return result


func _ClosestAnchorJoin(unitPosition: Vector2, anchorPath: PackedVector2Array) -> Vector3:
	if anchorPath.is_empty():
		return Vector3(0.0, 0.0, -1.0)

	var anchorPathSize: int = anchorPath.size()
	# Anchor path가 점 하나뿐인 경우
	if anchorPathSize == 1:
		var point: Vector2 = anchorPath[0]
		return Vector3(point.x, point.y, 0.0)

	var bestPoint: Vector2 = Vector2.ZERO
	var bestDistance: float = BIG_NUMBER
	var bestNextIndex: int = -1

	for segmentIndex: int in range(anchorPathSize - 1):
		var segmentStart: Vector2 = anchorPath[segmentIndex]
		var segmentEnd: Vector2 = anchorPath[segmentIndex + 1]
		var point: Vector2 = Geometry2D.get_closest_point_to_segment(
			unitPosition,
			segmentStart,
			segmentEnd,
		)

		var distance: float = unitPosition.distance_squared_to(point)
		if distance >= bestDistance:
			continue

		bestDistance = distance
		bestPoint = point
		bestNextIndex = segmentIndex + 1

	return Vector3(bestPoint.x, bestPoint.y, float(bestNextIndex))


func _FurthestStaticClearPoint(start: Vector2, target: Vector2, halfSize: int) -> Vector2:
	if start.distance_squared_to(target) <= EPSILON:
		return start

	if _IsStaticSegmentClear(start, target, halfSize):
		return target

	var low: float = 0.0
	var high: float = 1.0

	for iteration: int in range(24):
		var mid: float = (low + high) * 0.5

		var point: Vector2 = start.lerp(target, mid)

		if _IsStaticSegmentClear(start, point, halfSize):
			low = mid
		else:
			high = mid

	return start.lerp(target, low)


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

	return outerMinDistance * outerMinDistance > bestDistance + EPSILON


func _GetNearestPathCell(
	position: Vector2,
	halfSize: int,
	pathOffset: Vector2,
	requireReachable: bool,
) -> Vector2i:
	var centerCell: Vector2i = _WorldToNearestPathCell(position, pathOffset)
	centerCell.x = clampi(centerCell.x, 0, _gridWidth - 1)
	centerCell.y = clampi(centerCell.y, 0, _gridHeight - 1)

	var best: Vector2i = Vector2i(-1, -1)
	var bestDistance: float = BIG_NUMBER

	var maxRadius: int = maxi(_gridWidth, _gridHeight)
	for radius: int in range(maxRadius + 1):
		for y: int in range(centerCell.y - radius, centerCell.y + radius + 1):
			for x: int in range(centerCell.x - radius, centerCell.x + radius + 1):
				var ringDistance: int = maxi(absi(x - centerCell.x), absi(y - centerCell.y))
				if ringDistance != radius:
					continue

				var cell: Vector2i = Vector2i(x, y)
				if not _IsValidCell(cell):
					continue

				var center: Vector2 = _PathCellToWorld(cell, pathOffset)
				if not CanPlaceStatic(center, halfSize):
					continue
				if requireReachable and not _IsStaticSegmentClear(position, center, halfSize):
					continue

				var distance: float = center.distance_squared_to(position)
				if distance < bestDistance - EPSILON:
					bestDistance = distance
					best = cell
				elif absf(distance - bestDistance) <= EPSILON:
					if best.x < 0 or y < best.y or (y == best.y and x < best.x):
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


func _OctileHeuristic(a: Vector2i, b: Vector2i) -> float:
	var dx: int = absi(a.x - b.x)
	var dy: int = absi(a.y - b.y)

	var diagonal: int = mini(dx, dy)
	var straight: int = maxi(dx, dy) - diagonal

	return float(diagonal) * SQRT_2 + float(straight)


func _ReconstructPath(
	parent: PackedInt32Array,
	startIndex: int,
	destinationIndex: int,
	pathOffset: Vector2,
) -> Array[Vector2]:
	var reversed: Array[Vector2] = []

	var current: int = destinationIndex

	while current >= 0:
		reversed.append(_PathCellToWorld(_IndexToCell(current), pathOffset))

		if current == startIndex:
			break

		current = parent[current]

	if reversed.is_empty() or current != startIndex:
		return []

	reversed.reverse()

	return reversed


# 경로 압축 : 같은 방향으로 연속된 경로점들을 제거해 방향 전환점만 남김
func _CompressPath(path: Array[Vector2]) -> Array[Vector2]:
	if path.size() <= 2:
		return path

	var result: Array[Vector2] = []
	result.append(path[0])

	var previousDirection: Vector2 = (path[1] - path[0]).normalized()
	for index: int in range(1, path.size() - 1):
		var nextDirection: Vector2 = (path[index + 1] - path[index]).normalized()
		if not previousDirection.is_equal_approx(nextDirection):
			result.append(path[index])

		previousDirection = nextDirection

	result.append(path[path.size() - 1])

	return result


# 경로 단순화 : 장애물과 충돌하지 않는 범위에서 중간 경로점을 건너뛰어 waypoint 수를 줄임
func _ShortcutPath(start: Vector2, path: Array[Vector2], halfSize: int) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	var pathSize: int = path.size()
	if pathSize == 0:
		return result

	var current: Vector2 = start
	var index: int = 0
	while index < pathSize:
		var farthest: int = index
		# 가까운 지점부터 앞으로 검사
		for candidateIndex: int in range(index, pathSize):
			if not _IsStaticSegmentClear(current, path[candidateIndex], halfSize):
				break
			farthest = candidateIndex

		var point: Vector2 = path[farthest]
		if current.distance_squared_to(point) > EPSILON:
			result.append(point)

		current = point
		index = farthest + 1

	return result


func _IsStaticSegmentClear(start: Vector2, end: Vector2, halfSize: int) -> bool:
	var staticHalf: float = _StaticHalfSize(halfSize)
	var startValid: bool = _CanPlaceStaticWithHalf(start, staticHalf)
	var endValid: bool = _CanPlaceStaticWithHalf(end, staticHalf)

	if not endValid:
		return false

	if not startValid:
		return _IsRecoveringSegmentClear(start, end, staticHalf)

	return _IsStaticSegmentClearFromValidStart(start, end, staticHalf)


func _IsRecoveringSegmentClear(start: Vector2, end: Vector2, halfSize: float) -> bool:
	var delta: Vector2 = end - start

	if delta.length_squared() <= EPSILON:
		return false

	var recoveryLimit: float = maxf(_navCellSize * 0.5, maxf(staticContactSlop, 0.0) * 4.0)

	if delta.length() > recoveryLimit + EPSILON:
		return false

	var firstValid: Vector2 = end
	var foundValid: bool = false

	for step: int in range(1, 9):
		var t: float = float(step) / 8.0
		var point: Vector2 = start.lerp(end, t)

		if _CanPlaceStaticWithHalf(point, halfSize):
			firstValid = point
			foundValid = true
			break

	if not foundValid:
		return false

	return _IsStaticSegmentClearFromValidStart(firstValid, end, halfSize)


func _IsStaticSegmentClearFromValidStart(start: Vector2, end: Vector2, halfSize: float) -> bool:
	var half: Vector2 = Vector2(halfSize, halfSize)
	var broadMin: Vector2 = Vector2(minf(start.x, end.x), minf(start.y, end.y)) - half
	var broadMax: Vector2 = Vector2(maxf(start.x, end.x), maxf(start.y, end.y)) + half

	var minCell: Vector2i = _WorldToCellFloor(broadMin)
	var maxCell: Vector2i = _WorldToCellFloor(broadMax)

	minCell.x = clampi(minCell.x, 0, _gridWidth - 1)
	minCell.y = clampi(minCell.y, 0, _gridHeight - 1)
	maxCell.x = clampi(maxCell.x, 0, _gridWidth - 1)
	maxCell.y = clampi(maxCell.y, 0, _gridHeight - 1)

	for y: int in range(minCell.y, maxCell.y + 1):
		for x: int in range(minCell.x, maxCell.x + 1):
			if not _IsBlockedCell(x, y):
				continue

			var rect: Rect2 = _CellRect(Vector2i(x, y))
			var center: Vector2 = rect.position + rect.size * 0.5
			var expandedHalf: Vector2 = _CollisionHalf(half, rect.size * 0.5)

			if _SegmentIntersectsCenteredAabb(start - center, end - center, expandedHalf):
				return false

	return true


func _HeapLess(aIndex: int, bIndex: int) -> bool:
	if absf(_pathState.f[aIndex] - _pathState.f[bIndex]) > EPSILON:
		return _pathState.f[aIndex] < _pathState.f[bIndex]

	if absf(_pathState.turnCost[aIndex] - _pathState.turnCost[bIndex]) > EPSILON:
		return _pathState.turnCost[aIndex] < _pathState.turnCost[bIndex]

	if absf(_pathState.h[aIndex] - _pathState.h[bIndex]) > EPSILON:
		return _pathState.h[aIndex] < _pathState.h[bIndex]

	return aIndex < bIndex


func _HeapSwap(heap: Array[int], a: int, b: int) -> void:
	var temp: int = heap[a]
	heap[a] = heap[b]
	heap[b] = temp

	_pathState.heapPosition[heap[a]] = a
	_pathState.heapPosition[heap[b]] = b


func _HeapSiftUp(heap: Array[int], position: int) -> void:
	var index: int = position
	while index > 0:
		var parentIndex: int = int((index - 1) / 2)
		if not _HeapLess(heap[index], heap[parentIndex]):
			break

		_HeapSwap(heap, index, parentIndex)
		index = parentIndex


func _HeapInsertOrDecrease(heap: Array[int], cellIndex: int) -> bool:
	var position: int = _pathState.heapPosition[cellIndex]
	if position < 0:
		heap.append(cellIndex)
		position = heap.size() - 1
		_pathState.heapPosition[cellIndex] = position

		_HeapSiftUp(heap, position)
		return true

	_HeapSiftUp(heap, position)
	return false


func _HeapPop(heap: Array[int]) -> int:
	var rootIndex: int = heap[0]
	var lastIndex: int = heap.pop_back()

	_pathState.heapPosition[rootIndex] = -1

	if heap.is_empty():
		return rootIndex

	heap[0] = lastIndex
	_pathState.heapPosition[lastIndex] = 0

	var index: int = 0
	var heapSize: int = heap.size()
	while true:
		var left: int = index * 2 + 1
		var right: int = left + 1
		var smallest: int = index

		if left < heapSize and _HeapLess(heap[left], heap[smallest]):
			smallest = left

		if right < heapSize and _HeapLess(heap[right], heap[smallest]):
			smallest = right

		if smallest == index:
			break

		_HeapSwap(heap, index, smallest)
		index = smallest

	return rootIndex


func _IsValidCell(cell: Vector2i) -> bool:
	return (0 <= cell.x and cell.x < _gridWidth) and (0 <= cell.y and cell.y < _gridHeight)


func _CellToIndex(cell: Vector2i) -> int:
	return cell.y * _gridWidth + cell.x


func _IndexToCell(index: int) -> Vector2i:
	return Vector2i(index % _gridWidth, int(index / _gridWidth))


func _PathLatticeOffset(halfSize: int) -> Vector2:
	var offset: float = _LatticeAxisOffset(float(halfSize))
	return Vector2(offset, offset)


func _LatticeAxisOffset(halfExtent: float) -> float:
	var offset: float = fposmod(maxf(halfExtent, 0.0), _navCellSize)

	if offset <= EPSILON or _navCellSize - offset <= EPSILON:
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


func _CellRect(cell: Vector2i) -> Rect2:
	return Rect2(
		_worldRect.position + Vector2(float(cell.x) * _navCellSize, float(cell.y) * _navCellSize),
		Vector2(_navCellSize, _navCellSize),
	)


func _WorldToCellFloor(position: Vector2) -> Vector2i:
	var local: Vector2 = position - _worldRect.position

	return Vector2i(floori(local.x / _navCellSize), floori(local.y / _navCellSize))


func _IsBlockedCell(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= _gridWidth or y >= _gridHeight:
		return true

	return _blocked[y * _gridWidth + x] != 0
