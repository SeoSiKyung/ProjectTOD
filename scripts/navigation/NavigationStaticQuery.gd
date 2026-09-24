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

	var staticHalf: float = _StaticHalfSize(halfSize)
	var startValid: bool = _CanPlaceStaticWithHalf(start, staticHalf)
	var endValid: bool = _CanPlaceStaticWithHalf(end, staticHalf)
	if not endValid:
		return false

	if not startValid:
		return _IsRecoveringSegmentClear(start, end, staticHalf)

	return _IsStaticSegmentClearFromValidStart(start, end, staticHalf)


func FurthestClearPoint(
	start: Vector2,
	target: Vector2,
	halfSize: int,
	metrics: NavigationProfileMetrics = null,
) -> Vector2:
	if start.distance_squared_to(target) <= Math.EPSILON:
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

	if rectMin.x < _worldRect.position.x - Math.EPSILON:
		return false

	if rectMin.y < _worldRect.position.y - Math.EPSILON:
		return false

	if rectMax.x > worldEnd.x + Math.EPSILON:
		return false

	if rectMax.y > worldEnd.y + Math.EPSILON:
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


func _IsRecoveringSegmentClear(start: Vector2, end: Vector2, halfSize: float) -> bool:
	var delta: Vector2 = end - start
	if delta.length_squared() <= Math.EPSILON:
		return false

	var recoveryLimit: float = maxf(
		_navCellSize * 0.5,
		maxf(_navigationData.staticContactSlop, 0.0) * 4.0,
	)
	if delta.length() > recoveryLimit + Math.EPSILON:
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

	return _IsStaticSegmentClearFromValidStart(firstValid, end, halfSize)


func _IsStaticSegmentClearFromValidStart(start: Vector2, end: Vector2, halfSize: float) -> bool:
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
	if _PrefixRectCount(minCell.x, minCell.y, maxCell.x + 1, maxCell.y + 1) == 0:
		return true

	var cellHalf: Vector2 = Vector2(_navCellSize * 0.5, _navCellSize * 0.5)
	var expandedHalf: Vector2 = _CollisionHalf(half, cellHalf)

	# 모든 grid cell이 아니라 실제 blocked cell만 검사.
	for y: int in range(minCell.y, maxCell.y + 1):
		var blockedXs: PackedInt32Array = _blockedXsByRow[y]
		if blockedXs.is_empty():
			continue

		# 정렬되어 있으므로 minCell.x 이전은 바로 건너뛴다.
		var blockedIndex: int = blockedXs.bsearch(minCell.x)
		while blockedIndex < blockedXs.size():
			var x: int = blockedXs[blockedIndex]
			if x > maxCell.x:
				break

			var center: Vector2 = (
				_worldRect.position
				+ Vector2((float(x) + 0.5) * _navCellSize, (float(y) + 0.5) * _navCellSize)
			)
			if Math.SegmentIntersectsCenteredAabb(start - center, end - center, expandedHalf):
				return false

			blockedIndex += 1

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
