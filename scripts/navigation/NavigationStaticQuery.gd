class_name NavigationStaticQuery
extends RefCounted

const CONTACT_EPSILON: float = 0.001

var _navigationData: NavigationData

var _navCellSize: float
var _gridWidth: int
var _gridHeight: int
var _worldRect: Rect2

var _prefixSum: PackedInt32Array
var _blockedXsByRow: Array[PackedInt32Array] = []


func _init(navigationData: NavigationData) -> void:
	_navigationData = navigationData

	_navCellSize = float(navigationData.cellSize)
	_gridWidth = navigationData.gridSize.x
	_gridHeight = navigationData.gridSize.y
	_worldRect = navigationData.GetWorldRect()

	_prefixSum = navigationData.prefixSum

	_BuildBlockedRowIndex(navigationData.blocked)


func CanPlace(center: Vector2, halfSize: int) -> bool:
	return _CanPlaceStaticWithHalf(center, _StaticHalfSize(halfSize))


func SegmentClear(
	start: Vector2,
	end: Vector2,
	halfSize: int,
	metrics: NavigationProfileMetrics = null,
) -> bool:
	if metrics != null:
		metrics.staticSegmentChecks += 1

	var details: NavigationProfileMetrics = (
		metrics if metrics != null and metrics.captureStaticQueryDetails else null
	)
	var queryStart: int = Time.get_ticks_usec() if details != null else 0
	var staticHalf: float = _StaticHalfSize(halfSize)
	var startValid: bool = _CanPlaceStaticWithHalf(start, staticHalf)
	var endValid: bool = _CanPlaceStaticWithHalf(end, staticHalf)
	if details == null:
		if not endValid:
			return false
		if not startValid:
			return _IsRecoveringSegmentClear(start, end, staticHalf)
		return _IsStaticSegmentClearFromValidStart(start, end, staticHalf)

	var endpointEnd: int = Time.get_ticks_usec()
	var cellsBefore: int = details.staticDetailBroadCells
	var blockedBefore: int = details.staticDetailBroadBlocked
	var checksBefore: int = details.staticDetailIntersectionChecks
	var sweepStart: int = Time.get_ticks_usec()
	var result: bool = false
	if not endValid:
		details.staticDetailInvalidEndCalls += 1
	elif not startValid:
		details.staticDetailRecoveryCalls += 1
		result = _IsRecoveringSegmentClear(start, end, staticHalf, details)
	else:
		result = _IsStaticSegmentClearFromValidStart(start, end, staticHalf, details)
	var queryEnd: int = Time.get_ticks_usec()
	var endpointUsec: int = endpointEnd - queryStart
	var sweepUsec: int = queryEnd - sweepStart
	details.staticDetailCalls += 1
	if result:
		details.staticDetailClearCalls += 1
	details.staticDetailEndpointUsec += endpointUsec
	details.staticDetailSweepUsec += sweepUsec
	if queryEnd - queryStart > details.staticDetailWorstUsec:
		details.staticDetailWorstUsec = queryEnd - queryStart
		details.staticDetailWorstEndpointUsec = endpointUsec
		details.staticDetailWorstSweepUsec = sweepUsec
		details.staticDetailWorstStart = start
		details.staticDetailWorstEnd = end
		details.staticDetailWorstHalfSize = halfSize
		details.staticDetailWorstClear = result
		details.staticDetailWorstTick = details.staticQueryTick
		details.staticDetailWorstBroadCells = details.staticDetailBroadCells - cellsBefore
		details.staticDetailWorstBroadBlocked = details.staticDetailBroadBlocked - blockedBefore
		details.staticDetailWorstIntersectionChecks = (
			details.staticDetailIntersectionChecks - checksBefore
		)

	return result


func FurthestClearPoint(
	start: Vector2,
	target: Vector2,
	halfSize: int,
	metrics: NavigationProfileMetrics = null,
) -> Vector2:
	if Math.IsSamePoint(start, target):
		return start

	if SegmentClear(start, target, halfSize, metrics):
		return target

	var low: float = 0.0
	var high: float = 1.0
	for i: int in range(24):
		var mid: float = (low + high) * 0.5
		var point: Vector2 = start.lerp(target, mid)
		if SegmentClear(start, point, halfSize, metrics):
			low = mid
		else:
			high = mid

	return start.lerp(target, low)


func _BuildBlockedRowIndex(blocked: PackedByteArray) -> void:
	_blockedXsByRow.clear()
	_blockedXsByRow.resize(_gridHeight)

	for y: int in range(_gridHeight):
		var blockedXs: PackedInt32Array = PackedInt32Array()
		var rowStart: int = y * _gridWidth
		for x: int in range(_gridWidth):
			if blocked[rowStart + x] == 0:
				continue

			blockedXs.append(x)

		_blockedXsByRow[y] = blockedXs


func _StaticHalfSize(halfSize: int) -> float:
	return maxf(0.0, float(halfSize) - maxf(_navigationData.staticContactSlop, 0.0))


func _CanPlaceStaticWithHalf(center: Vector2, halfSize: float) -> bool:
	var worldEnd: Vector2 = _worldRect.position + _worldRect.size

	var half: Vector2 = Vector2(halfSize, halfSize)
	var rectMin: Vector2 = center - half
	var rectMax: Vector2 = center + half

	if Math.IsLess(rectMin.x, _worldRect.position.x):
		return false

	if Math.IsLess(rectMin.y, _worldRect.position.y):
		return false

	if Math.IsGreater(rectMax.x, worldEnd.x):
		return false

	if Math.IsGreater(rectMax.y, worldEnd.y):
		return false

	var localMin: Vector2 = rectMin - _worldRect.position
	var localMax: Vector2 = rectMax - _worldRect.position
	var minX: int = floori((localMin.x + Math.EPSILON) / _navCellSize)
	var minY: int = floori((localMin.y + Math.EPSILON) / _navCellSize)
	var maxX: int = floori((localMax.x - Math.EPSILON) / _navCellSize)
	var maxY: int = floori((localMax.y - Math.EPSILON) / _navCellSize)

	minX = clampi(minX, 0, _gridWidth - 1)
	minY = clampi(minY, 0, _gridHeight - 1)
	maxX = clampi(maxX, 0, _gridWidth - 1)
	maxY = clampi(maxY, 0, _gridHeight - 1)

	return _PrefixRectCount(minX, minY, maxX + 1, maxY + 1) == 0


func _IsRecoveringSegmentClear(
	start: Vector2,
	end: Vector2,
	halfSize: float,
	details: NavigationProfileMetrics = null,
) -> bool:
	var delta: Vector2 = end - start
	if delta.length_squared() <= Math.EPSILON:
		return false

	var recoveryLimit: float = maxf(
		_navCellSize * 0.5,
		maxf(_navigationData.staticContactSlop, 0.0) * 4.0,
	)
	if Math.IsGreater(delta.length(), recoveryLimit):
		return false

	var firstValid: Vector2 = end
	var foundValid: bool = false

	for step: int in range(1, 8 + 1):
		var ratio: float = float(step) / float(8)
		var point: Vector2 = start.lerp(end, ratio)

		if not _CanPlaceStaticWithHalf(point, halfSize):
			continue

		firstValid = point
		foundValid = true
		break

	if not foundValid:
		return false

	return _IsStaticSegmentClearFromValidStart(firstValid, end, halfSize, details)


func _IsStaticSegmentClearFromValidStart(
	start: Vector2,
	end: Vector2,
	halfSize: float,
	details: NavigationProfileMetrics = null,
) -> bool:
	var half: Vector2 = Vector2(halfSize, halfSize)

	var broadMin: Vector2 = Vector2(minf(start.x, end.x), minf(start.y, end.y)) - half
	var broadMax: Vector2 = Vector2(maxf(start.x, end.x), maxf(start.y, end.y)) + half

	var minCell: Vector2i = _WorldToCellFloor(broadMin)
	minCell.x = clampi(minCell.x, 0, _gridWidth - 1)
	minCell.y = clampi(minCell.y, 0, _gridHeight - 1)
	var maxCell: Vector2i = _WorldToCellFloor(broadMax)
	maxCell.x = clampi(maxCell.x, 0, _gridWidth - 1)
	maxCell.y = clampi(maxCell.y, 0, _gridHeight - 1)

	# Bounding rect 안에 장애물 자체가 하나도 없으면 즉시 성공.
	var blockedCount: int = _PrefixRectCount(minCell.x, minCell.y, maxCell.x + 1, maxCell.y + 1)
	if details != null:
		details.staticDetailBroadCalls += 1
		details.staticDetailBroadCells += (maxCell.x - minCell.x + 1) * (maxCell.y - minCell.y + 1)
		details.staticDetailBroadBlocked += blockedCount
	if blockedCount == 0:
		if details != null:
			details.staticDetailPrefixEmptyCalls += 1
		return true

	var cellHalf: Vector2 = Vector2(_navCellSize * 0.5, _navCellSize * 0.5)
	var expandedHalf: Vector2 = _CollisionHalf(half, cellHalf)
	var deltaX: float = float(end.x) - float(start.x)
	var deltaY: float = float(end.y) - float(start.y)
	var pruneRows: bool = not Math.IsNearlyZero(deltaY)

	# 모든 grid cell이 아니라 실제 blocked cell만 검사.
	for y: int in range(minCell.y, maxCell.y + 1):
		if details != null:
			details.staticDetailRowsVisited += 1
		var blockedXs: PackedInt32Array = _blockedXsByRow[y]
		if blockedXs.is_empty():
			continue

		var rowMinX: int = minCell.x
		var rowMaxX: int = maxCell.x
		if pruneRows:
			# 이 행의 확장 장애물과 겹칠 수 있는 선분 구간만 후보로 남긴다. 한 셀 여유를 두고, 최종 접촉 판정은 기존 정밀 함수에 맡긴다.
			var rowCenterY: float = _worldRect.position.y + (float(y) + 0.5) * _navCellSize
			var rowHalf: float = expandedHalf.y + _navCellSize
			var t1: float = (rowCenterY - rowHalf - start.y) / deltaY
			var t2: float = (rowCenterY + rowHalf - start.y) / deltaY
			var enter: float = maxf(0.0, minf(t1, t2))
			var leave: float = minf(1.0, maxf(t1, t2))
			if enter > leave:
				continue
			var x1: float = start.x + deltaX * enter
			var x2: float = start.x + deltaX * leave
			rowMinX = maxi(
				minCell.x,
				floori((minf(x1, x2) - expandedHalf.x - _worldRect.position.x) / _navCellSize) - 1,
			)
			rowMaxX = mini(
				maxCell.x,
				floori((maxf(x1, x2) + expandedHalf.x - _worldRect.position.x) / _navCellSize) + 1,
			)
			if rowMinX > rowMaxX:
				continue

		# 정렬된 기존 행 인덱스에서 좁힌 범위만 조회한다.
		var blockedIndex: int = blockedXs.bsearch(rowMinX)
		var firstBlockedIndex: int = blockedIndex
		while blockedIndex < blockedXs.size():
			var x: int = blockedXs[blockedIndex]
			if x > rowMaxX:
				break

			var center: Vector2 = (
				_worldRect.position
				+ Vector2((float(x) + 0.5) * _navCellSize, (float(y) + 0.5) * _navCellSize)
			)
			if Math.SegmentIntersectsCenteredAabb(start - center, end - center, expandedHalf):
				if details != null:
					details.staticDetailIntersectionChecks += blockedIndex - firstBlockedIndex + 1
				return false

			blockedIndex += 1
		if details != null:
			details.staticDetailIntersectionChecks += blockedIndex - firstBlockedIndex

	return true


func _CollisionHalf(aHalf: Vector2, bHalf: Vector2) -> Vector2:
	return Vector2(
		maxf(Math.EPSILON, aHalf.x + bHalf.x - CONTACT_EPSILON),
		maxf(Math.EPSILON, aHalf.y + bHalf.y - CONTACT_EPSILON),
	)


func _WorldToCellFloor(position: Vector2) -> Vector2i:
	var local: Vector2 = position - _worldRect.position
	return Vector2i(floori(local.x / _navCellSize), floori(local.y / _navCellSize))


func _PrefixRectCount(x0: int, y0: int, x1: int, y1: int) -> int:
	var width: int = _gridWidth + 1
	return (
		_prefixSum[y1 * width + x1] - _prefixSum[y0 * width + x1] - _prefixSum[y1 * width + x0]
		+ _prefixSum[y0 * width + x0]
	)
