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

var _pathG: PackedFloat64Array = PackedFloat64Array()
var _pathTurnCost: PackedFloat64Array = PackedFloat64Array()
var _pathParent: PackedInt32Array = PackedInt32Array()
var _pathIncomingDirection: PackedInt32Array = PackedInt32Array()
var _pathClosed: PackedByteArray = PackedByteArray()


class HeapEntry:
	var index: int = 0
	var f: float = 0.0
	var h: float = 0.0
	var turn: float = 0.0
	var g: float = 0.0


	func _init(pIndex: int, pF: float, pH: float, pTurn: float, pG: float) -> void:
		index = pIndex
		f = pF
		h = pH
		turn = pTurn
		g = pG


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
	_navigationReady = true


func _EnsurePathBuffers() -> void:
	var total: int = _gridWidth * _gridHeight

	if _pathG.size() == total:
		return

	_pathG.resize(total)
	_pathTurnCost.resize(total)
	_pathParent.resize(total)
	_pathIncomingDirection.resize(total)
	_pathClosed.resize(total)


func _ResetPathBuffers() -> void:
	_pathG.fill(BIG_NUMBER)
	_pathTurnCost.fill(BIG_NUMBER)
	_pathParent.fill(-1)
	_pathIncomingDirection.fill(-1)
	_pathClosed.fill(0)


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


func SegmentClear(start: Vector2, end: Vector2, halfSize: Vector2) -> bool:
	return _SegmentStaticClear(start, end, halfSize)


func _PrefixRectCount(x0: int, y0: int, x1: int, y1: int) -> int:
	var width: int = (_gridWidth + 1)

	return (
		_prefixSum[y1 * width + x1] - _prefixSum[y0 * width + x1] - _prefixSum[y1 * width + x0]
		+ _prefixSum[y0 * width + x0]
	)


func CanPlaceStatic(center: Vector2, halfSize: Vector2) -> bool:
	return _CanPlaceStaticWithHalf(center, _StaticHalfSize(halfSize))


func _StaticHalfSize(halfSize: Vector2) -> Vector2:
	var slop: float = maxf(staticContactSlop, 0.0)

	return Vector2(maxf(0.0, halfSize.x - slop), maxf(0.0, halfSize.y - slop))


func _CanPlaceStaticWithHalf(center: Vector2, halfSize: Vector2) -> bool:
	var worldEnd: Vector2 = _worldRect.position + _worldRect.size
	var rectMin: Vector2 = center - halfSize
	var rectMax: Vector2 = center + halfSize

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


func NearestPlaceablePoint(
	worldPosition: Vector2,
	halfSize: Vector2,
	referencePosition: Vector2,
) -> Vector2:
	if CanPlaceStatic(worldPosition, halfSize):
		return worldPosition

	var pathOffset: Vector2 = _PathLatticeOffset(halfSize)
	var centerCell: Vector2i = _WorldToNearestPathCell(worldPosition, pathOffset)
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

				if not _ValidCell(cell):
					continue

				var point: Vector2 = _PathPoint(cell, pathOffset)

				if not CanPlaceStatic(point, halfSize):
					continue

				var targetDistance: float = point.distance_squared_to(worldPosition)
				var referenceDistance: float = point.distance_squared_to(referencePosition)
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
			return _PathPoint(best, pathOffset)

	return worldPosition


func FindPath(startWorld: Vector2, targetWorld: Vector2, halfSize: Vector2) -> PackedVector2Array:
	var empty: PackedVector2Array = PackedVector2Array()

	if not _navigationReady:
		return empty

	var pathOffset: Vector2 = _PathLatticeOffset(halfSize)

	var startCell: Vector2i = _NearestValidPathCell(startWorld, halfSize, pathOffset)

	if startCell.x < 0:
		return empty

	var goalCell: Vector2i = _NearestValidPathCell(targetWorld, halfSize, pathOffset)

	if goalCell.x < 0:
		return empty

	_EnsurePathBuffers()
	_ResetPathBuffers()

	var startIndex: int = _CellIndex(startCell)
	var goalIndex: int = _CellIndex(goalCell)

	_pathG[startIndex] = 0.0
	_pathTurnCost[startIndex] = 0.0

	var heap: Array[HeapEntry] = []

	var startH: float = _OctileHeuristic(startCell, goalCell)

	_HeapPush(heap, HeapEntry.new(startIndex, startH, startH, 0.0, 0.0))

	var bestIndex: int = startIndex

	var bestTargetDistance: float = (
		_PathPoint(startCell, pathOffset).distance_squared_to(targetWorld)
	)

	var foundGoal: bool = false

	while not heap.is_empty():
		var entry: HeapEntry = _HeapPop(heap)

		var currentIndex: int = entry.index

		if _pathClosed[currentIndex] != 0:
			continue

		if absf(entry.g - _pathG[currentIndex]) > EPSILON:
			continue

		_pathClosed[currentIndex] = 1

		var currentCell: Vector2i = _IndexCell(currentIndex)

		var currentWorld: Vector2 = _PathPoint(currentCell, pathOffset)

		var targetDistance: float = currentWorld.distance_squared_to(targetWorld)

		if targetDistance < bestTargetDistance - EPSILON:
			bestTargetDistance = targetDistance

			bestIndex = currentIndex

		elif (absf(targetDistance - bestTargetDistance) <= EPSILON and currentIndex < bestIndex):
			bestIndex = currentIndex

		if currentIndex == goalIndex:
			foundGoal = true
			bestIndex = currentIndex
			break

		var previousDirection: int = _pathIncomingDirection[currentIndex]

		for dirIndex: int in range(DIRECTIONS.size()):
			var direction: Vector2i = DIRECTIONS[dirIndex]

			var nextCell: Vector2i = currentCell + direction

			if not _ValidCell(nextCell):
				continue

			var nextIndex: int = _CellIndex(nextCell)

			if _pathClosed[nextIndex] != 0:
				continue

			var nextWorld: Vector2 = _PathPoint(nextCell, pathOffset)

			if not CanPlaceStatic(nextWorld, halfSize):
				continue

			if direction.x != 0 and direction.y != 0:
				var horizontal: Vector2i = Vector2i(currentCell.x + direction.x, currentCell.y)

				var vertical: Vector2i = Vector2i(currentCell.x, currentCell.y + direction.y)

				if not _ValidCell(horizontal) or not _ValidCell(vertical):
					continue

				if not CanPlaceStatic(_PathPoint(horizontal, pathOffset), halfSize):
					continue

				if not CanPlaceStatic(_PathPoint(vertical, pathOffset), halfSize):
					continue

			var stepCost: float = 1.0

			if direction.x != 0 and direction.y != 0:
				stepCost = SQRT_2

			var tentativeG: float = _pathG[currentIndex] + stepCost

			var directionChange: float = 0.0

			if previousDirection >= 0:
				var difference: int = absi(dirIndex - previousDirection)

				difference = mini(difference, 8 - difference)

				directionChange = float(difference)

			var tentativeTurn: float = _pathTurnCost[currentIndex] + directionChange

			var better: bool = false

			if tentativeG < _pathG[nextIndex] - EPSILON:
				better = true

			elif (
				absf(tentativeG - _pathG[nextIndex]) <= EPSILON
				and tentativeTurn < _pathTurnCost[nextIndex] - EPSILON
			):
				better = true

			if not better:
				continue

			_pathG[nextIndex] = tentativeG

			_pathTurnCost[nextIndex] = tentativeTurn

			_pathParent[nextIndex] = currentIndex

			_pathIncomingDirection[nextIndex] = dirIndex

			var h: float = _OctileHeuristic(nextCell, goalCell)

			_HeapPush(heap, HeapEntry.new(nextIndex, tentativeG + h, h, tentativeTurn, tentativeG))

	var destinationIndex: int = bestIndex

	if foundGoal:
		destinationIndex = goalIndex

	var rawPath: Array[Vector2] = _ReconstructPath(
		_pathParent,
		startIndex,
		destinationIndex,
		pathOffset,
	)

	if rawPath.is_empty():
		return empty

	var last: Vector2 = rawPath[rawPath.size() - 1]

	var finalPoint: Vector2 = _FurthestStaticClearPoint(last, targetWorld, halfSize)

	if last.distance_squared_to(finalPoint) > EPSILON:
		rawPath.append(finalPoint)

	return _SimplifyPath(startWorld, rawPath, halfSize)


func _FurthestStaticClearPoint(start: Vector2, target: Vector2, halfSize: Vector2) -> Vector2:
	if start.distance_squared_to(target) <= EPSILON:
		return start

	if _SegmentStaticClear(start, target, halfSize):
		return target

	var low: float = 0.0
	var high: float = 1.0

	for iteration: int in range(24):
		var mid: float = (low + high) * 0.5

		var point: Vector2 = start.lerp(target, mid)

		if _SegmentStaticClear(start, point, halfSize):
			low = mid
		else:
			high = mid

	return start.lerp(target, low)


func _NearestValidPathCell(
	worldPosition: Vector2,
	halfSize: Vector2,
	pathOffset: Vector2,
) -> Vector2i:
	var centerCell: Vector2i = _WorldToNearestPathCell(worldPosition, pathOffset)

	centerCell.x = clampi(centerCell.x, 0, _gridWidth - 1)
	centerCell.y = clampi(centerCell.y, 0, _gridHeight - 1)
	var maxRadius: int = maxi(_gridWidth, _gridHeight)

	for radius: int in range(maxRadius + 1):
		var best: Vector2i = Vector2i(-1, -1)
		var bestDistance: float = BIG_NUMBER

		for y: int in range(centerCell.y - radius, centerCell.y + radius + 1):
			for x: int in range(centerCell.x - radius, centerCell.x + radius + 1):
				var ringDistance: int = maxi(absi(x - centerCell.x), absi(y - centerCell.y))

				if ringDistance != radius:
					continue

				var cell: Vector2i = Vector2i(x, y)

				if not _ValidCell(cell):
					continue

				var point: Vector2 = _PathPoint(cell, pathOffset)

				if not CanPlaceStatic(point, halfSize):
					continue

				var distance: float = point.distance_squared_to(worldPosition)

				if distance < bestDistance - EPSILON:
					bestDistance = distance
					best = cell
				elif absf(distance - bestDistance) <= EPSILON:
					if best.x < 0 or y < best.y or (y == best.y and x < best.x):
						best = cell

		if best.x >= 0:
			return best

	return Vector2i(-1, -1)


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
		reversed.append(_PathPoint(_IndexCell(current), pathOffset))

		if current == startIndex:
			break

		current = parent[current]

	if reversed.is_empty() or current != startIndex:
		return []

	reversed.reverse()

	return reversed


func _SimplifyPath(
	actualStart: Vector2,
	rawPath: Array[Vector2],
	halfSize: Vector2,
) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()

	if rawPath.is_empty():
		return result

	var anchor: Vector2 = actualStart
	var index: int = 0

	while index < rawPath.size():
		var farthest: int = index

		for candidateIndex: int in range(rawPath.size() - 1, index - 1, -1):
			if _SegmentStaticClear(anchor, rawPath[candidateIndex], halfSize):
				farthest = candidateIndex
				break

		var point: Vector2 = rawPath[farthest]

		if anchor.distance_squared_to(point) > EPSILON:
			result.append(point)

		anchor = point
		index = farthest + 1

	return result


func _SegmentStaticClear(start: Vector2, end: Vector2, halfSize: Vector2) -> bool:
	var staticHalf: Vector2 = _StaticHalfSize(halfSize)
	var startValid: bool = _CanPlaceStaticWithHalf(start, staticHalf)
	var endValid: bool = _CanPlaceStaticWithHalf(end, staticHalf)

	if not endValid:
		return false

	if not startValid:
		return _SegmentStaticClearRecovering(start, end, staticHalf)

	return _SegmentStaticClearValidStart(start, end, staticHalf)


func _SegmentStaticClearRecovering(start: Vector2, end: Vector2, halfSize: Vector2) -> bool:
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

	return _SegmentStaticClearValidStart(firstValid, end, halfSize)


func _SegmentStaticClearValidStart(start: Vector2, end: Vector2, halfSize: Vector2) -> bool:
	var broadMin: Vector2 = (Vector2(minf(start.x, end.x), minf(start.y, end.y)) - halfSize)

	var broadMax: Vector2 = (Vector2(maxf(start.x, end.x), maxf(start.y, end.y)) + halfSize)

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
			var expandedHalf: Vector2 = _CollisionHalf(halfSize, rect.size * 0.5)

			if _SegmentIntersectsCenteredAabb(start - center, end - center, expandedHalf):
				return false

	return true


func _HeapLess(a: HeapEntry, b: HeapEntry) -> bool:
	if absf(a.f - b.f) > EPSILON:
		return a.f < b.f

	if absf(a.turn - b.turn) > EPSILON:
		return a.turn < b.turn

	if absf(a.h - b.h) > EPSILON:
		return a.h < b.h

	return a.index < b.index


func _HeapPush(heap: Array[HeapEntry], entry: HeapEntry) -> void:
	heap.append(entry)

	var index: int = heap.size() - 1

	while index > 0:
		var parentIndex: int = int((index - 1) / 2)

		if not _HeapLess(heap[index], heap[parentIndex]):
			break

		var temp: HeapEntry = heap[index]

		heap[index] = heap[parentIndex]

		heap[parentIndex] = temp

		index = parentIndex


func _HeapPop(heap: Array[HeapEntry]) -> HeapEntry:
	var root: HeapEntry = heap[0]

	var lastIndex: int = heap.size() - 1

	var last: HeapEntry = heap[lastIndex]

	heap.remove_at(lastIndex)

	if heap.is_empty():
		return root

	heap[0] = last

	var index: int = 0

	while true:
		var left: int = index * 2 + 1

		var right: int = left + 1

		var smallest: int = index

		if left < heap.size() and _HeapLess(heap[left], heap[smallest]):
			smallest = left

		if right < heap.size() and _HeapLess(heap[right], heap[smallest]):
			smallest = right

		if smallest == index:
			break

		var temp: HeapEntry = heap[index]

		heap[index] = heap[smallest]

		heap[smallest] = temp

		index = smallest

	return root


func _ValidCell(cell: Vector2i) -> bool:
	return (cell.x >= 0 and cell.y >= 0 and cell.x < _gridWidth and cell.y < _gridHeight)


func _CellIndex(cell: Vector2i) -> int:
	return cell.y * _gridWidth + cell.x


func _IndexCell(index: int) -> Vector2i:
	return Vector2i(index % _gridWidth, int(index / _gridWidth))


func _PathLatticeOffset(halfSize: Vector2) -> Vector2:
	return Vector2(_LatticeAxisOffset(halfSize.x), _LatticeAxisOffset(halfSize.y))


func _LatticeAxisOffset(halfExtent: float) -> float:
	var offset: float = fposmod(maxf(halfExtent, 0.0), _navCellSize)

	if offset <= EPSILON or _navCellSize - offset <= EPSILON:
		return 0.0

	return offset


func _PathPoint(cell: Vector2i, pathOffset: Vector2) -> Vector2:
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
