class_name NavigationService
extends Node

const EPSILON: float = 0.00001
const CONTACT_EPSILON: float = 0.001
const BIG_NUMBER: float = 1.0e30
const SQRT_2: float = 1.41421356237
const SQRT_2_MINUS_1: float = SQRT_2 - 1.0

const PATH_REGION_INVALID: int = -1
const PATH_REGION_PORTAL: int = -2

@export var navigationData: NavigationData
@export_range(0.0, 2.0, 0.05) var staticContactSlop: float = 1.0
@export_range(8, 256, 8) var localSearchMarginCells: int = 64
@export_range(8, 256, 8) var anchorConnectionCacheCapacity: int = 64
@export var navigationProfileEnabled: bool = true

var _navigationReady: bool = false
var _navCellSize: float = 8.0
var _gridWidth: int = 0
var _gridHeight: int = 0
var _worldRect: Rect2 = Rect2()
var _blocked: PackedByteArray = PackedByteArray()
var _prefixSum: PackedInt32Array = PackedInt32Array()

var _portalMap: PackedByteArray = PackedByteArray()
var _regionMap: PackedInt32Array = PackedInt32Array()

var _regions: Array[NavigationRegionData] = []
var _portals: Array[NavigationPortalData] = []

var _pathState: PathSearchState = PathSearchState.new()
var _footprintMaps: Dictionary[int, FootprintNavigationMap] = { }

var _footprintDataByHalfSize: Dictionary[int, NavigationFootprintData] = { }

var _anchorGraphByHalfSize: Dictionary[int, AnchorGraphData] = { }

var _anchorConnectionCache: Dictionary[Vector4, AnchorConnectionCacheEntry] = { }
var _anchorConnectionCacheOrder: Array[Vector4] = []

var _regionAnchorTopologyCache: Dictionary[Vector2i, RegionAnchorTopology] = { }

# jhw
var _anchorCacheHits: int = 0
var _anchorCacheMisses: int = 0
# jhw/
var _blockedXsByRow: Array[PackedInt32Array] = []


class PathSearchState:
	var f: PackedFloat64Array = PackedFloat64Array()
	var g: PackedFloat64Array = PackedFloat64Array()
	var h: PackedFloat64Array = PackedFloat64Array()
	var turnCost: PackedFloat64Array = PackedFloat64Array()

	var parent: PackedInt32Array = PackedInt32Array()
	var incomingDirection: PackedInt32Array = PackedInt32Array()
	var closed: PackedByteArray = PackedByteArray()
	var heapPosition: PackedInt32Array = PackedInt32Array()
	var touchedMap: PackedByteArray = PackedByteArray()
	var touched: Array[int] = []


	func Resize(size: int) -> void:
		f.resize(size)
		g.resize(size)
		h.resize(size)
		turnCost.resize(size)

		parent.resize(size)
		incomingDirection.resize(size)
		closed.resize(size)
		heapPosition.resize(size)
		touchedMap.resize(size)

		f.fill(BIG_NUMBER)
		g.fill(BIG_NUMBER)
		h.fill(BIG_NUMBER)
		turnCost.fill(BIG_NUMBER)

		parent.fill(-1)
		incomingDirection.fill(-1)
		closed.fill(0)
		heapPosition.fill(-1)
		touchedMap.fill(0)

		touched.clear()


	func Reset() -> void:
		for index: int in touched:
			f[index] = BIG_NUMBER
			g[index] = BIG_NUMBER
			h[index] = BIG_NUMBER
			turnCost[index] = BIG_NUMBER

			parent[index] = -1
			incomingDirection[index] = -1
			closed[index] = 0
			heapPosition[index] = -1
			touchedMap[index] = 0

		touched.clear()


	func Touch(index: int) -> void:
		if touchedMap[index] != 0:
			return

		touchedMap[index] = 1
		touched.append(index)


class FootprintNavigationMap:
	var placeableMap: PackedByteArray = PackedByteArray()
	var componentMap: PackedInt32Array = PackedInt32Array()
	var pathRegionMap: PackedInt32Array = PackedInt32Array()

	var walkMask: PackedByteArray = PackedByteArray()
	var regionWalkMask: PackedByteArray = PackedByteArray()


class AnchorGraphEdge:
	var toPortalId: int = -1
	var toAnchorIndex: int = -1

	var route: NavigationPortalRouteData = null
	var reversed: bool = false


class AnchorGraphData:
	var edgesByNode: Dictionary = { }


class AnchorConnection:
	var nodeKey: Vector2i = Vector2i(-1, -1)
	var path: PackedVector2Array = PackedVector2Array()
	var cost: float = BIG_NUMBER


class AnchorConnectionCacheEntry:
	var connections: Array[AnchorConnection] = []


class AnchorGraphPath:
	var startConnection: AnchorConnection = null
	var targetConnection: AnchorConnection = null
	var edges: Array[AnchorGraphEdge] = []
	var cost: float = BIG_NUMBER


class RegionAnchorTopology:
	var nodes: Array[Vector2i] = []
	var componentByNode: Dictionary = { }


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

	_portalMap = navigationData.portalMap
	_regionMap = navigationData.regionMap

	_regions = navigationData.regions
	_portals = navigationData.portals

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

	if _portalMap.size() != expectedBlocked:
		push_error("NavigationData의 portalMap 크기가 잘못되었습니다.")
		return

	if _regionMap.size() != expectedBlocked:
		push_error("NavigationData의 regionMap 크기가 잘못되었습니다.")
		return

	_BuildBlockedRowIndex()

	_EnsurePathBuffers()

	_footprintMaps.clear()
	_footprintDataByHalfSize.clear()

	for footprint: NavigationFootprintData in navigationData.footprints:
		if footprint == null or footprint.halfSize <= 0:
			continue

		if _footprintDataByHalfSize.has(footprint.halfSize):
			push_warning("중복된 NavigationFootprintData halfSize: %d" % footprint.halfSize)

		_footprintDataByHalfSize[footprint.halfSize] = footprint

	_anchorGraphByHalfSize.clear()
	for footprint: NavigationFootprintData in navigationData.footprints:
		if footprint == null or footprint.halfSize <= 0:
			continue

		_footprintDataByHalfSize[footprint.halfSize] = footprint

		var graph: AnchorGraphData = _MakeAnchorGraph(footprint)
		_anchorGraphByHalfSize[footprint.halfSize] = graph

	_anchorConnectionCache.clear()
	_anchorConnectionCacheOrder.clear()

	_regionAnchorTopologyCache.clear()

	_navigationReady = true


func _BuildBlockedRowIndex() -> void:
	_blockedXsByRow.clear()
	_blockedXsByRow.resize(_gridHeight)

	for y: int in range(_gridHeight):
		var blockedXs: PackedInt32Array = PackedInt32Array()
		var rowStart: int = y * _gridWidth

		for x: int in range(_gridWidth):
			if _blocked[rowStart + x] == 0:
				continue

			blockedXs.append(x)

		_blockedXsByRow[y] = blockedXs


func _EnsurePathBuffers() -> void:
	var total: int = _gridWidth * _gridHeight
	if _pathState.g.size() == total:
		return

	_pathState.Resize(total)


func _ResetPathBuffers() -> void:
	_pathState.Reset()


func _MakeAnchorGraph(footprint: NavigationFootprintData) -> AnchorGraphData:
	var result: AnchorGraphData = AnchorGraphData.new()

	for route: NavigationPortalRouteData in footprint.portalRoutes:
		if route == null:
			continue

		if (
			not _IsValidPortalAnchor(footprint, route.fromPortalId, route.fromAnchorIndex)
			or not _IsValidPortalAnchor(footprint, route.toPortalId, route.toAnchorIndex)
		):
			continue

		var fromKey: Vector2i = Vector2i(route.fromPortalId, route.fromAnchorIndex)
		var toKey: Vector2i = Vector2i(route.toPortalId, route.toAnchorIndex)

		var forwardEdge: AnchorGraphEdge = AnchorGraphEdge.new()
		forwardEdge.toPortalId = route.toPortalId
		forwardEdge.toAnchorIndex = route.toAnchorIndex
		forwardEdge.route = route
		forwardEdge.reversed = false

		_AppendAnchorEdge(result, fromKey, forwardEdge)

		var reverseEdge: AnchorGraphEdge = AnchorGraphEdge.new()
		reverseEdge.toPortalId = route.fromPortalId
		reverseEdge.toAnchorIndex = route.fromAnchorIndex
		reverseEdge.route = route
		reverseEdge.reversed = true

		_AppendAnchorEdge(result, toKey, reverseEdge)

	return result


func _IsValidPortalAnchor(
	footprint: NavigationFootprintData,
	portalId: int,
	anchorIndex: int,
) -> bool:
	if portalId < 0 or portalId >= footprint.portals.size():
		return false

	var portalData: NavigationFootprintPortalData = footprint.portals[portalId]
	if portalData == null:
		return false

	return (0 <= anchorIndex and anchorIndex < portalData.anchors.size())


func _AppendAnchorEdge(graph: AnchorGraphData, nodeKey: Vector2i, edge: AnchorGraphEdge) -> void:
	if not graph.edgesByNode.has(nodeKey):
		graph.edgesByNode[nodeKey] = []

	var edges: Array = graph.edgesByNode[nodeKey]
	edges.append(edge)


func _GetAnchorGraph(halfSize: int) -> AnchorGraphData:
	if not _anchorGraphByHalfSize.has(halfSize):
		return null

	return _anchorGraphByHalfSize[halfSize]


func _GetFootprintMap(halfSize: int) -> FootprintNavigationMap:
	if _footprintMaps.has(halfSize):
		return _footprintMaps[halfSize]

	var navigationMap: FootprintNavigationMap = _MakeFootprintMap(halfSize)
	_footprintMaps[halfSize] = navigationMap

	return navigationMap


func _GetFootprintData(halfSize: int) -> NavigationFootprintData:
	if not _footprintDataByHalfSize.has(halfSize):
		return null

	return _footprintDataByHalfSize[halfSize]


func _MakeFootprintMap(halfSize: int) -> FootprintNavigationMap:
	var navigationMap: FootprintNavigationMap = FootprintNavigationMap.new()
	var pathOffset: Vector2 = _PathLatticeOffset(halfSize)
	var total: int = _gridWidth * _gridHeight

	navigationMap.placeableMap.resize(total)
	navigationMap.placeableMap.fill(0)

	navigationMap.pathRegionMap.resize(total)
	navigationMap.pathRegionMap.fill(PATH_REGION_INVALID)

	navigationMap.componentMap.resize(total)
	navigationMap.componentMap.fill(-1)

	navigationMap.walkMask.resize(total)
	navigationMap.walkMask.fill(0)

	navigationMap.regionWalkMask.resize(total)
	navigationMap.regionWalkMask.fill(0)

	for index: int in range(total):
		var cell: Vector2i = _IndexToCell(index)
		var center: Vector2 = _PathCellToWorld(cell, pathOffset)
		if not CanPlaceStatic(center, halfSize):
			continue

		navigationMap.placeableMap[index] = 1

		var regionCell: Vector2i = _WorldToCellFloor(center)
		if not _IsValidCell(regionCell):
			continue

		var regionIndex: int = _CellToIndex(regionCell)
		var regionId: int = _regionMap[regionIndex]
		if regionId >= 0:
			navigationMap.pathRegionMap[index] = regionId
		elif _portalMap[regionIndex] != 0:
			navigationMap.pathRegionMap[index] = PATH_REGION_PORTAL

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
			var currentWalkMask: int = 0
			var currentRegionWalkMask: int = 0

			var currentRegionId: int = (navigationMap.pathRegionMap[currentIndex])

			for dirIndex: int in range(DIRECTIONS.size()):
				var direction: Vector2i = DIRECTIONS[dirIndex]
				var nextCell: Vector2i = currentCell + direction
				if not _IsValidCell(nextCell):
					continue

				var nextIndex: int = _CellToIndex(nextCell)
				if navigationMap.placeableMap[nextIndex] == 0:
					continue

				if direction.x != 0 and direction.y != 0:
					var horizontal: Vector2i = Vector2i(currentCell.x + direction.x, currentCell.y)
					var vertical: Vector2i = Vector2i(currentCell.x, currentCell.y + direction.y)
					if (
						navigationMap.placeableMap[_CellToIndex(horizontal)] == 0
						or navigationMap.placeableMap[_CellToIndex(vertical)] == 0
					):
						continue

				# 여기까지 왔으면 이 방향은 정적으로 이동 가능.
				var directionBit: int = 1 << dirIndex
				currentWalkMask |= directionBit

				# 일반 Region 셀은 같은 Region + Portal만 이동 가능하도록
				# Region 전용 mask도 미리 만든다.
				if currentRegionId >= 0:
					var nextRegionId: int = (navigationMap.pathRegionMap[nextIndex])

					var regionAllowed: bool = (
						nextRegionId == currentRegionId or nextRegionId == PATH_REGION_PORTAL
					)

					if (regionAllowed and direction.x != 0 and direction.y != 0):
						var horizontalIndex: int = (currentIndex + direction.x)
						var verticalIndex: int = (currentIndex + direction.y * _gridWidth)

						var horizontalRegionId: int = (navigationMap.pathRegionMap[horizontalIndex])
						var verticalRegionId: int = (navigationMap.pathRegionMap[verticalIndex])
						if (
							horizontalRegionId != currentRegionId
							and horizontalRegionId != PATH_REGION_PORTAL
						):
							regionAllowed = false

						if (
							verticalRegionId != currentRegionId
							and verticalRegionId != PATH_REGION_PORTAL
						):
							regionAllowed = false

					if regionAllowed:
						currentRegionWalkMask |= directionBit

				if navigationMap.componentMap[nextIndex] >= 0:
					continue

				navigationMap.componentMap[nextIndex] = componentId
				queue.append(nextIndex)

			navigationMap.walkMask[currentIndex] = currentWalkMask
			navigationMap.regionWalkMask[currentIndex] = currentRegionWalkMask

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

	var referenceCell: Vector2i = _GetNearestPathCell(referencePosition, halfSize, pathOffset)
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


func _ProfileMilliseconds(startUs: int) -> float:
	return float(Time.get_ticks_usec() - startUs) / 1000.0


func FindPath(start: Vector2, target: Vector2, halfSize: int) -> PackedVector2Array:
	# jhw
	var totalStartUs: int = 0
	var phaseStartUs: int = 0
	var resolveMs: float = 0.0
	var fallbackStartUs: int = 0
	var regionMs: float = 0.0
	var localMs: float = 0.0
	var startConnectionsMs: float = 0.0
	var targetConnectionsMs: float = 0.0
	var graphMs: float = 0.0
	var buildMs: float = 0.0
	# jhw/
	totalStartUs = Time.get_ticks_usec()
	if not _navigationReady:
		return PackedVector2Array()

	phaseStartUs = Time.get_ticks_usec()
	var resolvedTarget: Vector2 = _ResolveReachableTarget(start, target, halfSize)
	resolveMs = _ProfileMilliseconds(phaseStartUs)
	if start.distance_squared_to(resolvedTarget) <= EPSILON:
		return PackedVector2Array()

	var footprintData: NavigationFootprintData = _GetFootprintData(halfSize)
	if footprintData == null:
		fallbackStartUs = Time.get_ticks_usec()
		var fallbackPath: PackedVector2Array = _FindCompleteGridPath(
			start,
			resolvedTarget,
			halfSize,
		)

		if navigationProfileEnabled:
			print(
				"[Nav] fallback | resolve=%.2f | grid=%.2f | total=%.2f"
				% [
					resolveMs,
					_ProfileMilliseconds(fallbackStartUs),
					_ProfileMilliseconds(totalStartUs),
				]
			)

		return fallbackPath

	phaseStartUs = Time.get_ticks_usec()
	var startRegionIds: Array[int] = _GetRegionIds(start)
	var targetRegionIds: Array[int] = _GetRegionIds(resolvedTarget)
	regionMs = _ProfileMilliseconds(phaseStartUs)
	if startRegionIds.is_empty() or targetRegionIds.is_empty():
		return _FindCompleteGridPath(start, resolvedTarget, halfSize)
	localMs = 0.0

	if (
		startRegionIds.size() == 1 and targetRegionIds.size() == 1
		and startRegionIds[0] == targetRegionIds[0]
	):
		phaseStartUs = Time.get_ticks_usec()
		var localPath: PackedVector2Array = _FindPathInsideRegion(
			start,
			resolvedTarget,
			halfSize,
			startRegionIds[0],
		)
		localMs += _ProfileMilliseconds(phaseStartUs)
		if not localPath.is_empty():
			if navigationProfileEnabled:
				print(
					(
						"[Nav] LOCAL" + " | resolve=%.2f" + " | region=%.2f"
						+ " | local=%.2f" + " | total=%.2f"
					)
					% [resolveMs, regionMs, localMs, _ProfileMilliseconds(totalStartUs)]
				)
			return localPath

	var bestPath: PackedVector2Array = PackedVector2Array()
	var bestCost: float = BIG_NUMBER
	phaseStartUs = Time.get_ticks_usec()

	# Portal 위의 시작/목표 때문에 양쪽이 같은 Region으로 연결 가능한 경우도 후보에 포함한다.
	for startRegionId: int in startRegionIds:
		if not targetRegionIds.has(startRegionId):
			continue

		var localPath: PackedVector2Array = _FindPathInsideRegion(
			start,
			resolvedTarget,
			halfSize,
			startRegionId,
		)
		if localPath.is_empty():
			continue

		var localCost: float = _GetWaypointPathCost(start, localPath)
		if localCost < bestCost - EPSILON:
			bestCost = localCost
			bestPath = localPath
	localMs += _ProfileMilliseconds(phaseStartUs)

	phaseStartUs = Time.get_ticks_usec()
	var startConnections: Array[AnchorConnection] = (
		_MakeRegionAnchorConnectionsForRegions(start, halfSize, startRegionIds, footprintData)
	)
	startConnectionsMs = _ProfileMilliseconds(phaseStartUs)

	phaseStartUs = Time.get_ticks_usec()
	var targetConnections: Array[AnchorConnection] = (
		_MakeRegionAnchorConnectionsForRegions(
			resolvedTarget,
			halfSize,
			targetRegionIds,
			footprintData,
		)
	)
	targetConnectionsMs = _ProfileMilliseconds(phaseStartUs)

	if not startConnections.is_empty() and not targetConnections.is_empty():
		var graph: AnchorGraphData = _GetAnchorGraph(halfSize)
		if graph != null:
			phaseStartUs = Time.get_ticks_usec()
			var graphPath: AnchorGraphPath = _FindAnchorGraphPath(
				startConnections,
				targetConnections,
				footprintData,
				graph,
				resolvedTarget,
			)
			graphMs = _ProfileMilliseconds(phaseStartUs)

			if graphPath != null and graphPath.cost < bestCost - EPSILON:
				phaseStartUs = Time.get_ticks_usec()
				bestPath = _BuildHierarchicalPath(resolvedTarget, graphPath)
				bestCost = graphPath.cost
				buildMs = _ProfileMilliseconds(phaseStartUs)

	if navigationProfileEnabled:
		print(
			(
				"[Nav] HIER" + " | resolve=%.2f" + " | region=%.2f" + " | local=%.2f"
				+ " | startConn=%.2f (%d)" + " | targetConn=%.2f (%d)" + " | graph=%.2f"
				+ " | build=%.2f" + " | total=%.2f" + " | cache=%d/%d"
			)
			% [
				resolveMs,
				regionMs,
				localMs,
				startConnectionsMs,
				startConnections.size(),
				targetConnectionsMs,
				targetConnections.size(),
				graphMs,
				buildMs,
				_ProfileMilliseconds(totalStartUs),
				_anchorCacheHits,
				_anchorCacheMisses,
			]
		)

	if not bestPath.is_empty():
		return bestPath

	return _FindCompleteGridPath(start, resolvedTarget, halfSize)


func _GetRegionIds(position: Vector2) -> Array[int]:
	var result: Array[int] = []

	var cell: Vector2i = _WorldToCellFloor(position)
	if not _IsValidCell(cell):
		return result

	var index: int = _CellToIndex(cell)
	var regionId: int = _regionMap[index]
	if regionId >= 0:
		result.append(regionId)
		return result

	if _portalMap[index] == 0:
		return result

	return _GetPortalRegionIds(cell)


func _GetPortalRegionIds(startCell: Vector2i) -> Array[int]:
	var result: Array[int] = []
	var foundRegions: Dictionary = { }
	var visited: Dictionary = { }

	var queue: Array[Vector2i] = [startCell]
	visited[_CellToIndex(startCell)] = true

	var head: int = 0
	while head < queue.size():
		var currentCell: Vector2i = queue[head]
		head += 1

		for direction: Vector2i in DIRECTIONS:
			var nextCell: Vector2i = currentCell + direction
			if not _IsValidCell(nextCell):
				continue

			var nextIndex: int = _CellToIndex(nextCell)
			var regionId: int = _regionMap[nextIndex]
			if regionId >= 0:
				if not foundRegions.has(regionId):
					foundRegions[regionId] = true
					result.append(regionId)

				continue

			if _portalMap[nextIndex] == 0 or visited.has(nextIndex):
				continue

			visited[nextIndex] = true
			queue.append(nextCell)

	return result


func _FindCompleteGridPath(start: Vector2, target: Vector2, halfSize: int) -> PackedVector2Array:
	var path: PackedVector2Array = _FindGridPath(start, target, halfSize)
	if path.is_empty():
		return path

	var last: Vector2 = path[path.size() - 1]
	if last.distance_squared_to(target) > EPSILON:
		return PackedVector2Array()

	return path


func _MakeRegionAnchorConnectionsForRegions(
	position: Vector2,
	halfSize: int,
	regionIds: Array[int],
	footprint: NavigationFootprintData,
) -> Array[AnchorConnection]:
	var result: Array[AnchorConnection] = []

	var bestByNode: Dictionary = { }
	for regionId: int in regionIds:
		var connections: Array[AnchorConnection] = _MakeRegionAnchorConnections(
			position,
			halfSize,
			regionId,
			footprint,
		)

		for connection: AnchorConnection in connections:
			if not bestByNode.has(connection.nodeKey):
				bestByNode[connection.nodeKey] = connection
				continue

			var previous: AnchorConnection = bestByNode[connection.nodeKey]
			if connection.cost < previous.cost - EPSILON:
				bestByNode[connection.nodeKey] = connection

	for value: Variant in bestByNode.values():
		var connection: AnchorConnection = value as AnchorConnection
		if connection != null:
			result.append(connection)

	return result


func _FindPathInsideRegion(
	start: Vector2,
	target: Vector2,
	halfSize: int,
	regionId: int,
) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	if (SegmentClear(start, target, halfSize) and _IsSegmentInsideRegion(start, target, regionId)):
		result.append(target)
		return result

	result = _FindLocalPath(start, target, halfSize, regionId)
	if result.is_empty():
		return PackedVector2Array()

	# Local path에서는 partial path를 성공으로 인정하지 않는다.
	var last: Vector2 = result[result.size() - 1]
	if last.distance_squared_to(target) > EPSILON:
		return PackedVector2Array()

	return result


func _ResolveReachableTarget(start: Vector2, target: Vector2, halfSize: int) -> Vector2:
	var pathOffset: Vector2 = _PathLatticeOffset(halfSize)
	var navigationMap: FootprintNavigationMap = _GetFootprintMap(halfSize)

	# 시작점이 속한 실제 이동 가능 Component 확인
	var startCell: Vector2i = _GetNearestPathCell(start, halfSize, pathOffset)
	if startCell.x < 0:
		return start

	var startIndex: int = _CellToIndex(startCell)
	var componentId: int = navigationMap.componentMap[startIndex]
	if componentId < 0:
		return start

	# 클릭한 위치가 그대로 배치 가능하고, 시작점과 같은 Component라면 원래 좌표를 그대로 사용한다.
	if CanPlaceStatic(target, halfSize):
		var targetCell: Vector2i = _GetNearestPathCell(target, halfSize, pathOffset)
		if targetCell.x >= 0:
			var targetIndex: int = _CellToIndex(targetCell)
			if navigationMap.componentMap[targetIndex] == componentId:
				return target

	# 막힌 곳 / 맵 밖 / 도달 불가능한 Component라면 시작점과 같은 Component 안에서 클릭 위치에 가장 가까운 점으로 보정.
	var reachableCell: Vector2i = _GetNearestCellInComponent(
		target,
		pathOffset,
		componentId,
		navigationMap,
	)
	if reachableCell.x < 0:
		return start

	return _PathCellToWorld(reachableCell, pathOffset)


func _FindGridPath(start: Vector2, target: Vector2, halfSize: int) -> PackedVector2Array:
	return _FindGridPathInternal(start, target, halfSize, -1)


func _FindLocalPath(
	start: Vector2,
	target: Vector2,
	halfSize: int,
	regionId: int,
) -> PackedVector2Array:
	# 먼저 Start-Target 주변으로 제한된 A*를 시도한다.
	var quickPath: PackedVector2Array = _FindGridPathInternal(
		start,
		target,
		halfSize,
		regionId,
		localSearchMarginCells,
	)

	var completedQuickPath: PackedVector2Array = _CompleteLocalPathIfPossible(
		start,
		target,
		quickPath,
		halfSize,
		regionId,
	)

	if not completedQuickPath.is_empty():
		return completedQuickPath

	# 제한 범위 안에서 못 찾았으면 기존 전체 Region 탐색.
	return _FindGridPathInternal(start, target, halfSize, regionId, -1)


func _CompleteLocalPathIfPossible(
	start: Vector2,
	target: Vector2,
	path: PackedVector2Array,
	halfSize: int,
	regionId: int,
) -> PackedVector2Array:
	if path.is_empty():
		return PackedVector2Array()

	var result: PackedVector2Array = path
	var last: Vector2 = result[result.size() - 1]
	if last.distance_squared_to(target) <= EPSILON:
		return result

	if (
		not SegmentClear(last, target, halfSize)
		or not _IsSegmentInsideRegion(last, target, regionId)
	):
		return PackedVector2Array()

	result.append(target)

	return result


func _FindGridPathInternal(
	start: Vector2,
	target: Vector2,
	halfSize: int,
	regionId: int,
	searchMarginCells: int = -1,
) -> PackedVector2Array:
	var empty: PackedVector2Array = PackedVector2Array()
	if not _navigationReady:
		return empty

	var pathOffset: Vector2 = _PathLatticeOffset(halfSize)
	var navigationMap: FootprintNavigationMap = _GetFootprintMap(halfSize)

	var startCell: Vector2i = _GetNearestPathCell(start, halfSize, pathOffset)
	var targetCell: Vector2i = _GetNearestPathCell(target, halfSize, pathOffset)
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

	_EnsurePathBuffers()
	_ResetPathBuffers()

	_pathState.touchedMap[startIndex] = 1
	_pathState.touched.append(startIndex)
	_pathState.g[startIndex] = 0.0
	_pathState.turnCost[startIndex] = 0.0

	var heap: Heap = Heap.new(_HeapLess, Heap.PackedInt32IndexTracker.new(_pathState.heapPosition))
	var startH: float = _OctileHeuristic(startCell, targetCell)
	_pathState.h[startIndex] = startH
	_pathState.f[startIndex] = startH * 1.5

	heap.PushOrDecrease(startIndex)

	var bestIndex: int = startIndex
	var bestTargetDistance: float = (
		_PathCellToWorld(startCell, pathOffset).distance_squared_to(target)
	)

	var foundGoal: bool = false
	while not heap.IsEmpty():
		var currentIndex: int = int(heap.Pop())
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
			if (
				useSearchBounds
				and (
					not (searchMinX <= nextCell.x and nextCell.x <= searchMaxX)
					or not (searchMinY <= nextCell.y and nextCell.y <= searchMaxY)
				)
			):
				continue

			var nextIndex: int = _CellToIndex(nextCell)
			if _pathState.closed[nextIndex] != 0 or navigationMap.placeableMap[nextIndex] == 0:
				continue

			if (
				regionId >= 0
				and not _IsLocalPathCellAllowed(nextCell, regionId, targetCell, navigationMap)
			):
				continue

			if _pathState.touchedMap[nextIndex] == 0:
				_pathState.touchedMap[nextIndex] = 1
				_pathState.touched.append(nextIndex)
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

				if regionId >= 0:
					if (not _IsLocalPathCellAllowed(horizontal, regionId, targetCell, navigationMap)):
						continue
					if (not _IsLocalPathCellAllowed(vertical, regionId, targetCell, navigationMap)):
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

			heap.PushOrDecrease(nextIndex)

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
	if regionId >= 0:
		return _ShortcutLocalPath(start, compressedPath, halfSize, regionId)

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

		_AppendSlotIfReachable(result, slot, halfSize)

		return result

	# 2. Anchor waypoint 자체로 직선 합류 가능한지 검사
	for index: int in range(anchorPathSize - 1, -1, -1):
		if not SegmentClear(unitPosition, anchorPath[index], halfSize):
			continue

		for pathIndex: int in range(index, anchorPathSize):
			result.append(anchorPath[pathIndex])

		_AppendSlotIfReachable(result, slot, halfSize)

		return result

	# 3. 직선 합류가 불가능하면 가장 가까운 Anchor 지점까지 짧은 A*
	var joinData: Vector3 = _ClosestAnchorJoin(unitPosition, anchorPath)
	var joinNextIndex: int = int(joinData.z)
	if joinNextIndex < 0:
		return result

	var joinPoint: Vector2 = Vector2(joinData.x, joinData.y)
	var localPath: PackedVector2Array = _FindCompleteGridPath(unitPosition, joinPoint, halfSize)
	if localPath.is_empty():
		return result

	for point: Vector2 in localPath:
		result.append(point)

	# 합류한 선분 다음 waypoint부터 Anchor 경로를 이어 붙인다.
	for index: int in range(joinNextIndex, anchorPathSize):
		var point: Vector2 = anchorPath[index]

		if (result.is_empty() or result[result.size() - 1].distance_squared_to(point) > EPSILON):
			result.append(point)

	# 마지막으로 각 유닛의 formation slot
	_AppendSlotIfReachable(result, slot, halfSize)

	return result


func _AppendSlotIfReachable(path: PackedVector2Array, slot: Vector2, halfSize: int) -> void:
	if path.is_empty():
		return

	var last: Vector2 = path[path.size() - 1]
	if last.distance_squared_to(slot) <= EPSILON or not SegmentClear(last, slot, halfSize):
		return

	path.append(slot)


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


func _IsLocalPathCellAllowed(
	pathCell: Vector2i,
	regionId: int,
	targetPathCell: Vector2i,
	navigationMap: FootprintNavigationMap,
) -> bool:
	if not _IsValidCell(pathCell):
		return false

	if pathCell == targetPathCell:
		return true

	var pathRegionId: int = navigationMap.pathRegionMap[_CellToIndex(pathCell)]
	return (pathRegionId == regionId or pathRegionId == PATH_REGION_PORTAL)


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


func _GetNearestPathCell(position: Vector2, halfSize: int, pathOffset: Vector2) -> Vector2i:
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
				if (
					not CanPlaceStatic(center, halfSize)
					or not _IsStaticSegmentClear(position, center, halfSize)
				):
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
	var straight: int = maxi(dx, dy)

	return float(diagonal) * SQRT_2_MINUS_1 + float(straight)


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


func _IsSegmentInsideRegion(start: Vector2, end: Vector2, regionId: int) -> bool:
	var distance: float = start.distance_to(end)
	if distance <= EPSILON:
		return true

	var stepLength: float = _navCellSize * 0.5
	var stepCount: int = maxi(1, ceili(distance / stepLength))

	for step: int in range(stepCount + 1):
		var ratio: float = float(step) / float(stepCount)
		var point: Vector2 = start.lerp(end, ratio)

		var cell: Vector2i = _WorldToCellFloor(point)
		if not _IsValidCell(cell):
			return false

		var index: int = _CellToIndex(cell)
		if _regionMap[index] == regionId:
			continue

		# Portal 셀은 해당 Region의 경계 공간으로 취급한다.
		if _portalMap[index] != 0:
			continue

		# 다른 Region 내부로 들어간 경우만 실패.
		return false

	return true


func _ShortcutLocalPath(
	start: Vector2,
	path: Array[Vector2],
	halfSize: int,
	regionId: int,
) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	if path.is_empty():
		return result

	var current: Vector2 = start
	var index: int = 0
	while index < path.size():
		var farthest: int = -1
		for candidateIndex: int in range(index, path.size()):
			if (
				not _IsStaticSegmentClear(current, path[candidateIndex], halfSize)
				or not _IsSegmentInsideRegion(current, path[candidateIndex], regionId)
			):
				break

			farthest = candidateIndex

		if farthest < 0:
			break

		var point: Vector2 = path[farthest]
		if current.distance_squared_to(point) > EPSILON:
			result.append(point)

		current = point
		index = farthest + 1

	return result


# 경로 단순화 : 장애물과 충돌하지 않는 범위에서 중간 경로점을 건너뛰어 waypoint 수를 줄임
func _ShortcutPath(start: Vector2, path: Array[Vector2], halfSize: int) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	if path.is_empty():
		return result

	var current: Vector2 = start
	var index: int = 0
	while index < path.size():
		var farthest: int = -1
		for candidateIndex: int in range(index, path.size()):
			if not _IsStaticSegmentClear(current, path[candidateIndex], halfSize):
				break

			farthest = candidateIndex

		if farthest < 0:
			break

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

	# Bounding rect 안에 장애물 자체가 하나도 없으면 즉시 성공.
	if (_PrefixRectCount(minCell.x, minCell.y, maxCell.x + 1, maxCell.y + 1) == 0):
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
			if _SegmentIntersectsCenteredAabb(start - center, end - center, expandedHalf):
				return false

			blockedIndex += 1

	return true


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


func _GetRegionId(position: Vector2) -> int:
	var cell: Vector2i = _WorldToCellFloor(position)
	if not _IsValidCell(cell):
		return -1

	var index: int = _CellToIndex(cell)
	var regionId: int = _regionMap[index]
	if regionId >= 0:
		return regionId

	# Portal 셀 위에 있는 경우
	if _portalMap[index] != 0:
		return _GetNearestPortalRegionId(position, cell)

	return -1


func _GetNearestPortalRegionId(position: Vector2, portalCell: Vector2i) -> int:
	var bestRegionId: int = -1
	var bestDistance: float = BIG_NUMBER

	for direction: Vector2i in DIRECTIONS:
		var neighborCell: Vector2i = portalCell + direction
		if not _IsValidCell(neighborCell):
			continue

		var neighborIndex: int = _CellToIndex(neighborCell)
		var regionId: int = _regionMap[neighborIndex]
		if regionId < 0:
			continue

		var center: Vector2 = (
			_worldRect.position
			+ Vector2(
				(float(neighborCell.x) + 0.5) * _navCellSize,
				(float(neighborCell.y) + 0.5) * _navCellSize,
			)
		)

		var distance: float = center.distance_squared_to(position)
		if distance >= bestDistance:
			continue

		bestDistance = distance
		bestRegionId = regionId

	return bestRegionId


func _GetRegionAnchorNodes(regionId: int, footprint: NavigationFootprintData) -> Array[Vector2i]:
	var result: Array[Vector2i] = []

	if regionId < 0 or regionId >= _regions.size():
		return result

	var region: NavigationRegionData = _regions[regionId]
	if region == null:
		return result

	for portalId: int in region.portalIds:
		if portalId < 0 or portalId >= footprint.portals.size():
			continue

		var portal: NavigationFootprintPortalData = footprint.portals[portalId]
		if portal == null or not portal.traversable:
			continue

		for anchorIndex: int in range(portal.anchors.size()):
			result.append(Vector2i(portalId, anchorIndex))

	return result


func _MakeRegionAnchorComponentMap(
	regionId: int,
	nodes: Array[Vector2i],
	footprint: NavigationFootprintData,
) -> Dictionary:
	var adjacency: Dictionary = { }

	for nodeKey: Vector2i in nodes:
		adjacency[nodeKey] = []

	for route: NavigationPortalRouteData in footprint.portalRoutes:
		if route == null or route.regionId != regionId:
			continue

		var fromKey: Vector2i = Vector2i(route.fromPortalId, route.fromAnchorIndex)
		var toKey: Vector2i = Vector2i(route.toPortalId, route.toAnchorIndex)
		if not adjacency.has(fromKey) or not adjacency.has(toKey):
			continue

		var fromEdges: Array = adjacency[fromKey]
		fromEdges.append(toKey)

		var toEdges: Array = adjacency[toKey]
		toEdges.append(fromKey)

	var result: Dictionary = { }
	var componentId: int = 0

	for startNode: Vector2i in nodes:
		if result.has(startNode):
			continue

		var queue: Array[Vector2i] = [startNode]
		result[startNode] = componentId

		var head: int = 0
		while head < queue.size():
			var current: Vector2i = queue[head]
			head += 1

			var neighbors: Array = adjacency[current]

			for value: Variant in neighbors:
				var next: Vector2i = value

				if result.has(next):
					continue

				result[next] = componentId
				queue.append(next)

		componentId += 1

	return result


func _MakeRegionAnchorConnections(
	position: Vector2,
	halfSize: int,
	regionId: int,
	footprint: NavigationFootprintData,
) -> Array[AnchorConnection]:
	var cacheKey: Vector4 = Vector4(position.x, position.y, float(halfSize), float(regionId))
	if _anchorConnectionCache.has(cacheKey):
		_anchorCacheHits += 1
		var cachedEntry: AnchorConnectionCacheEntry = _anchorConnectionCache[cacheKey]
		_TouchAnchorConnectionCacheKey(cacheKey)

		return cachedEntry.connections
	_anchorCacheMisses += 1

	var connections: Array[AnchorConnection] = _BuildRegionAnchorConnections(
		position,
		halfSize,
		regionId,
		footprint,
	)

	var entry: AnchorConnectionCacheEntry = AnchorConnectionCacheEntry.new()
	entry.connections = connections

	_anchorConnectionCache[cacheKey] = entry
	_TouchAnchorConnectionCacheKey(cacheKey)
	_TrimAnchorConnectionCache()

	return connections


func _TouchAnchorConnectionCacheKey(cacheKey: Vector4) -> void:
	var existingIndex: int = _anchorConnectionCacheOrder.find(cacheKey)
	if existingIndex >= 0:
		_anchorConnectionCacheOrder.remove_at(existingIndex)

	_anchorConnectionCacheOrder.append(cacheKey)


func _TrimAnchorConnectionCache() -> void:
	var capacity: int = maxi(1, anchorConnectionCacheCapacity)
	while _anchorConnectionCacheOrder.size() > capacity:
		var oldestKey: Vector4 = _anchorConnectionCacheOrder[0]
		_anchorConnectionCacheOrder.remove_at(0)
		_anchorConnectionCache.erase(oldestKey)


func _GetRegionAnchorTopology(
	halfSize: int,
	regionId: int,
	footprint: NavigationFootprintData,
) -> RegionAnchorTopology:
	var cacheKey: Vector2i = Vector2i(halfSize, regionId)
	if _regionAnchorTopologyCache.has(cacheKey):
		return _regionAnchorTopologyCache[cacheKey]

	var topology: RegionAnchorTopology = RegionAnchorTopology.new()
	topology.nodes = _GetRegionAnchorNodes(regionId, footprint)

	if not topology.nodes.is_empty():
		topology.componentByNode = _MakeRegionAnchorComponentMap(
			regionId,
			topology.nodes,
			footprint,
		)

	_regionAnchorTopologyCache[cacheKey] = topology

	return topology


func _BuildRegionAnchorConnections(
	position: Vector2,
	halfSize: int,
	regionId: int,
	footprint: NavigationFootprintData,
) -> Array[AnchorConnection]:
	# jhw
	var profileStartUs: int = Time.get_ticks_usec()
	var phaseStartUs: int = 0

	var topologyMs: float = 0.0
	var directMs: float = 0.0
	var probeMs: float = 0.0
	var batchMs: float = 0.0
	var fallbackMs: float = 0.0

	var directCount: int = 0
	var probeCount: int = 0
	var batchCount: int = 0
	var fallbackCount: int = 0
	# jhw/
	var result: Array[AnchorConnection] = []
	phaseStartUs = Time.get_ticks_usec()
	var topology: RegionAnchorTopology = _GetRegionAnchorTopology(halfSize, regionId, footprint)
	topologyMs = _ProfileMilliseconds(phaseStartUs)
	var nodes: Array[Vector2i] = topology.nodes
	if nodes.is_empty():
		return result

	var componentByNode: Dictionary = topology.componentByNode

	var reachableComponents: Dictionary = { }
	var addedNodes: Dictionary = { }
	# 1. 직선 연결 가능한 Anchor는 즉시 추가
	phaseStartUs = Time.get_ticks_usec()
	for nodeKey: Vector2i in nodes:
		var anchor: Vector2 = _GetAnchorPosition(footprint, nodeKey)

		if (
			not SegmentClear(position, anchor, halfSize)
			or not _IsSegmentInsideRegion(position, anchor, regionId)
		):
			continue

		var path: PackedVector2Array = PackedVector2Array()
		path.append(anchor)

		var connection: AnchorConnection = AnchorConnection.new()
		connection.nodeKey = nodeKey
		connection.path = path
		connection.cost = position.distance_to(anchor)

		result.append(connection)
		addedNodes[nodeKey] = true
		directCount += 1

		var componentId: int = int(componentByNode[nodeKey])
		reachableComponents[componentId] = true
	directMs = _ProfileMilliseconds(phaseStartUs)

	# 2. 아직 reachability가 확인되지 않은 component마다 가장 가까운 Anchor 하나만 probe
	var probeByComponent: Dictionary = { }
	var probeDistanceByComponent: Dictionary = { }

	for nodeKey: Vector2i in nodes:
		if addedNodes.has(nodeKey):
			continue

		var componentId: int = int(componentByNode[nodeKey])
		if reachableComponents.has(componentId):
			continue

		var anchor: Vector2 = _GetAnchorPosition(footprint, nodeKey)
		var distance: float = position.distance_squared_to(anchor)

		var previousDistance: float = float(probeDistanceByComponent.get(componentId, BIG_NUMBER))
		if distance >= previousDistance:
			continue

		probeByComponent[componentId] = nodeKey
		probeDistanceByComponent[componentId] = distance

	phaseStartUs = Time.get_ticks_usec()
	var unreachableComponents: Dictionary = { }
	for componentValue: Variant in probeByComponent.keys():
		var componentId: int = int(componentValue)
		var nodeKey: Vector2i = probeByComponent[componentId]
		var anchor: Vector2 = _GetAnchorPosition(footprint, nodeKey)

		probeCount += 1
		var path: PackedVector2Array = _FindLocalPath(position, anchor, halfSize, regionId)
		if not _EnsurePathEndsAtAnchor(position, path, anchor, halfSize, regionId):
			# 같은 baked component의 다른 Anchor도
			# 도달 불가능하므로 전부 생략 가능.
			unreachableComponents[componentId] = true
			continue

		reachableComponents[componentId] = true
		addedNodes[nodeKey] = true

		var connection: AnchorConnection = AnchorConnection.new()
		connection.nodeKey = nodeKey
		connection.path = path
		connection.cost = _GetWaypointPathCost(position, path)

		result.append(connection)
	probeMs = _ProfileMilliseconds(phaseStartUs)

	# 3. 남은 Anchor를 Portal별로 묶어서 한 번의 A*로 계산.
	var nodesByPortal: Dictionary = { }
	for nodeKey: Vector2i in nodes:
		if addedNodes.has(nodeKey):
			continue

		var componentId: int = int(componentByNode[nodeKey])
		if (unreachableComponents.has(componentId) or not reachableComponents.has(componentId)):
			continue

		if not nodesByPortal.has(nodeKey.x):
			nodesByPortal[nodeKey.x] = []

		var portalNodes: Array = nodesByPortal[nodeKey.x]
		portalNodes.append(nodeKey)

	for portalValue: Variant in nodesByPortal.keys():
		var portalId: int = int(portalValue)
		var rawNodes: Array = nodesByPortal[portalId]

		var portalNodes: Array[Vector2i] = []
		for value: Variant in rawNodes:
			portalNodes.append(value as Vector2i)

		var batchStartUs: int = Time.get_ticks_usec()
		var pathsByNode: Dictionary = _FindLocalPathsToPortalAnchors(
			position,
			portalNodes,
			halfSize,
			regionId,
			footprint,
		)
		batchMs += _ProfileMilliseconds(batchStartUs)
		batchCount += 1

		for nodeKey: Vector2i in portalNodes:
			var path: PackedVector2Array
			if pathsByNode.has(nodeKey):
				path = pathsByNode[nodeKey]
			else:
				var anchor: Vector2 = _GetAnchorPosition(footprint, nodeKey)
				var fallbackStartUs: int = Time.get_ticks_usec()
				path = _FindLocalPath(position, anchor, halfSize, regionId)
				fallbackMs += _ProfileMilliseconds(fallbackStartUs)
				fallbackCount += 1
				if not _EnsurePathEndsAtAnchor(position, path, anchor, halfSize, regionId):
					continue

			var connection: AnchorConnection = AnchorConnection.new()
			connection.nodeKey = nodeKey
			connection.path = path
			connection.cost = _GetWaypointPathCost(position, path)

			result.append(connection)

	if navigationProfileEnabled:
		print(
			(
				"[NavConn]" + " region=%d" + " half=%d" + " nodes=%d" + " result=%d"
				+ " | topology=%.2f" + " | direct=%.2f (%d)" + " | probe=%.2f (%d)"
				+ " | batch=%.2f (%d)" + " | fallback=%.2f (%d)" + " | total=%.2f"
			)
			% [
				regionId,
				halfSize,
				nodes.size(),
				result.size(),
				topologyMs,
				directMs,
				directCount,
				probeMs,
				probeCount,
				batchMs,
				batchCount,
				fallbackMs,
				fallbackCount,
				_ProfileMilliseconds(profileStartUs),
			]
		)
	return result


func _IsRegionTraversalCellAllowed(
	pathCell: Vector2i,
	regionId: int,
	navigationMap: FootprintNavigationMap,
) -> bool:
	if not _IsValidCell(pathCell):
		return false

	var pathRegionId: int = navigationMap.pathRegionMap[_CellToIndex(pathCell)]
	return (pathRegionId == regionId or pathRegionId == PATH_REGION_PORTAL)


func _FindLocalPathsToPortalAnchors(
	start: Vector2,
	nodeKeys: Array[Vector2i],
	halfSize: int,
	regionId: int,
	footprint: NavigationFootprintData,
) -> Dictionary:
	# jhw
	var profileStartUs: int = Time.get_ticks_usec()
	var phaseStartUs: int = 0
	var prepareMs: float = 0.0
	var initMs: float = 0.0
	var searchMs: float = 0.0
	var postMs: float = 0.0
	var expandedCount: int = 0
	var relaxedCount: int = 0
	# jhw/
	var result: Dictionary = { }

	if nodeKeys.is_empty():
		return result

	var pathOffset: Vector2 = _PathLatticeOffset(halfSize)
	var navigationMap: FootprintNavigationMap = _GetFootprintMap(halfSize)

	var startCell: Vector2i = _GetNearestPathCell(start, halfSize, pathOffset)
	if startCell.x < 0:
		return result

	var startIndex: int = _CellToIndex(startCell)
	var startComponent: int = navigationMap.componentMap[startIndex]
	if startComponent < 0:
		return result

	# lattice target cell → 그 cell을 사용하는 Anchor들
	var nodesByTargetIndex: Dictionary = { }
	var targetCells: Array[Vector2i] = []

	for nodeKey: Vector2i in nodeKeys:
		var anchor: Vector2 = _GetAnchorPosition(footprint, nodeKey)

		var targetCell: Vector2i = _GetNearestPathCell(anchor, halfSize, pathOffset)
		if targetCell.x < 0:
			continue

		var targetIndex: int = _CellToIndex(targetCell)
		if navigationMap.componentMap[targetIndex] != startComponent:
			continue

		if not nodesByTargetIndex.has(targetIndex):
			nodesByTargetIndex[targetIndex] = []
			targetCells.append(targetCell)

		var nodes: Array = nodesByTargetIndex[targetIndex]
		nodes.append(nodeKey)

	if targetCells.is_empty():
		return result

	var heuristicWeight: float = 1.0
	# Target이 하나뿐이면 공유 shortest-tree가 필요 없으므로
	# 기존 Local A*와 동일한 Weighted A* 사용.
	if targetCells.size() == 1:
		heuristicWeight = 1.5

	var singleTargetMode: bool = targetCells.size() == 1
	var singleTargetCell: Vector2i = Vector2i(-1, -1)
	var singleTargetIndex: int = -1

	var singleTargetX: int = 0
	var singleTargetY: int = 0
	if singleTargetMode:
		singleTargetCell = targetCells[0]
		singleTargetIndex = _CellToIndex(singleTargetCell)

		singleTargetX = singleTargetCell.x
		singleTargetY = singleTargetCell.y

	# Portal 하나의 Anchor들은 서로 가까우므로
	# Start ↔ Portal 주변으로만 먼저 탐색한다.
	var searchMinX: int = startCell.x
	var searchMinY: int = startCell.y
	var searchMaxX: int = startCell.x
	var searchMaxY: int = startCell.y

	for targetCell: Vector2i in targetCells:
		searchMinX = mini(searchMinX, targetCell.x)
		searchMinY = mini(searchMinY, targetCell.y)
		searchMaxX = maxi(searchMaxX, targetCell.x)
		searchMaxY = maxi(searchMaxY, targetCell.y)

	searchMinX = maxi(0, searchMinX - localSearchMarginCells)
	searchMinY = maxi(0, searchMinY - localSearchMarginCells)
	searchMaxX = mini(_gridWidth - 1, searchMaxX + localSearchMarginCells)
	searchMaxY = mini(_gridHeight - 1, searchMaxY + localSearchMarginCells)

	prepareMs = _ProfileMilliseconds(profileStartUs)
	phaseStartUs = Time.get_ticks_usec()
	_EnsurePathBuffers()
	_ResetPathBuffers()

	_pathState.touchedMap[startIndex] = 1
	_pathState.touched.append(startIndex)
	_pathState.g[startIndex] = 0.0
	_pathState.turnCost[startIndex] = 0.0

	var startH: float
	if singleTargetMode:
		startH = _OctileHeuristic(startCell, singleTargetCell)
	else:
		startH = _GetNearestTargetHeuristic(startCell, targetCells)

	_pathState.h[startIndex] = startH
	_pathState.f[startIndex] = startH * heuristicWeight

	var heap: Heap = Heap.new(_HeapLess, Heap.PackedInt32IndexTracker.new(_pathState.heapPosition))
	heap.PushOrDecrease(startIndex)

	var remainingTargetIndices: Dictionary = { }
	if not singleTargetMode:
		for targetCell: Vector2i in targetCells:
			remainingTargetIndices[_CellToIndex(targetCell)] = true

	initMs = _ProfileMilliseconds(phaseStartUs)
	var searchStartUs: int = Time.get_ticks_usec()
	while not heap.IsEmpty():
		if (not singleTargetMode and remainingTargetIndices.is_empty()):
			break
		var currentIndex: int = int(heap.Pop())
		if _pathState.closed[currentIndex] != 0:
			continue
		_pathState.closed[currentIndex] = 1
		expandedCount += 1

		# Anchor lattice cell 하나 도착.
		var reachedTarget: bool
		if singleTargetMode:
			reachedTarget = currentIndex == singleTargetIndex
		else:
			reachedTarget = remainingTargetIndices.has(currentIndex)

		if reachedTarget:
			var postStartUs: int = Time.get_ticks_usec()
			var rawPath: Array[Vector2] = _ReconstructPath(
				_pathState.parent,
				startIndex,
				currentIndex,
				pathOffset,
			)

			if not rawPath.is_empty():
				var compressed: Array[Vector2] = _CompressPath(rawPath)
				var basePath: PackedVector2Array = _ShortcutLocalPath(
					start,
					compressed,
					halfSize,
					regionId,
				)

				var nodeValues: Array = nodesByTargetIndex[currentIndex]
				for nodeValue: Variant in nodeValues:
					var nodeKey: Vector2i = nodeValue

					# Anchor마다 마지막 Portal Anchor 좌표가 다를 수 있으므로
					# 각각 복사해서 endpoint를 완성한다.
					var path: PackedVector2Array = basePath.duplicate()
					var anchor: Vector2 = _GetAnchorPosition(footprint, nodeKey)
					if _EnsurePathEndsAtAnchor(start, path, anchor, halfSize, regionId):
						result[nodeKey] = path

			if singleTargetMode:
				postMs += _ProfileMilliseconds(postStartUs)
				break

			remainingTargetIndices.erase(currentIndex)
			postMs += _ProfileMilliseconds(postStartUs)

		var currentCell: Vector2i = _IndexToCell(currentIndex)
		var previousDirection: int = _pathState.incomingDirection[currentIndex]
		var currentPathRegionId: int = (navigationMap.pathRegionMap[currentIndex])

		var usePrecomputedRegionMask: bool = (currentPathRegionId == regionId)

		var walkMask: int

		if usePrecomputedRegionMask:
			walkMask = navigationMap.regionWalkMask[currentIndex]
		else:
			walkMask = navigationMap.walkMask[currentIndex]

		for dirIndex: int in range(DIRECTIONS.size()):
			if (walkMask & (1 << dirIndex)) == 0:
				continue

			var direction: Vector2i = DIRECTIONS[dirIndex]
			var nextCell: Vector2i = currentCell + direction
			if (
				not (searchMinX <= nextCell.x and nextCell.x <= searchMaxX)
				or not (searchMinY <= nextCell.y and nextCell.y <= searchMaxY)
			):
				continue

			var nextIndex: int = _CellToIndex(nextCell)
			if _pathState.closed[nextIndex] != 0:
				continue

			if not usePrecomputedRegionMask:
				var pathRegionId: int = (navigationMap.pathRegionMap[nextIndex])
				if (pathRegionId != regionId and pathRegionId != PATH_REGION_PORTAL):
					continue

				# Portal 셀에서 대각선으로 빠져나갈 때만 side cell Region을 런타임 검사.
				if direction.x != 0 and direction.y != 0:
					var horizontalIndex: int = (currentIndex + direction.x)
					var verticalIndex: int = (currentIndex + direction.y * _gridWidth)

					var horizontalRegionId: int = (navigationMap.pathRegionMap[horizontalIndex])
					var verticalRegionId: int = (navigationMap.pathRegionMap[verticalIndex])
					if (horizontalRegionId != regionId and horizontalRegionId != PATH_REGION_PORTAL):
						continue
					if (verticalRegionId != regionId and verticalRegionId != PATH_REGION_PORTAL):
						continue

			if _pathState.touchedMap[nextIndex] == 0:
				_pathState.touchedMap[nextIndex] = 1
				_pathState.touched.append(nextIndex)

			var stepCost: float = 1.0
			if direction.x != 0 and direction.y != 0:
				stepCost = SQRT_2

			var directionChange: float = 0.0
			if previousDirection >= 0:
				var difference: int = absi(dirIndex - previousDirection)
				difference = mini(difference, 8 - difference)
				directionChange = float(difference)

			var tentativeG: float = (_pathState.g[currentIndex] + stepCost)
			var tentativeTurn: float = (_pathState.turnCost[currentIndex] + directionChange)
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
			relaxedCount += 1

			_pathState.g[nextIndex] = tentativeG
			_pathState.turnCost[nextIndex] = tentativeTurn
			_pathState.parent[nextIndex] = currentIndex
			_pathState.incomingDirection[nextIndex] = dirIndex

			var h: float
			if singleTargetMode:
				h = _OctileHeuristic(nextCell, singleTargetCell)
			else:
				h = _GetNearestTargetHeuristic(nextCell, targetCells)

			_pathState.h[nextIndex] = h
			# 여러 Target이면 공유 탐색을 위해 1.0.
			# Target 하나면 기존 Local A*와 동일하게 1.5 Weighted A*.
			_pathState.f[nextIndex] = tentativeG + h * heuristicWeight

			heap.PushOrDecrease(nextIndex)

	var loopMs: float = _ProfileMilliseconds(searchStartUs)
	searchMs = maxf(0.0, loopMs - postMs)

	if navigationProfileEnabled:
		print(
			(
				"[NavBatch]" + " region=%d" + " nodes=%d" + " targets=%d" + " expanded=%d"
				+ " relaxed=%d" + " touched=%d" + " | prepare=%.2f" + " | init=%.2f"
				+ " | search=%.2f" + " | post=%.2f" + " | total=%.2f"
			)
			% [
				regionId,
				nodeKeys.size(),
				targetCells.size(),
				expandedCount,
				relaxedCount,
				_pathState.touched.size(),
				prepareMs,
				initMs,
				searchMs,
				postMs,
				_ProfileMilliseconds(profileStartUs),
			]
		)

	return result


func _GetNearestTargetHeuristic(cell: Vector2i, targetCells: Array[Vector2i]) -> float:
	var best: float = BIG_NUMBER
	for targetCell: Vector2i in targetCells:
		best = minf(best, _OctileHeuristic(cell, targetCell))

	return best


func _EnsurePathEndsAtAnchor(
	start: Vector2,
	path: PackedVector2Array,
	anchor: Vector2,
	halfSize: int,
	regionId: int,
) -> bool:
	var last: Vector2 = start
	if not path.is_empty():
		last = path[path.size() - 1]

	if last.distance_squared_to(anchor) <= EPSILON:
		return true

	if (
		not SegmentClear(last, anchor, halfSize)
		or not _IsSegmentInsideRegion(last, anchor, regionId)
	):
		return false

	path.append(anchor)
	return true


func _GetWaypointPathCost(start: Vector2, path: PackedVector2Array) -> float:
	var cost: float = 0.0
	var current: Vector2 = start

	for point: Vector2 in path:
		cost += current.distance_to(point)
		current = point

	return cost


func _FindAnchorGraphPath(
	startConnections: Array[AnchorConnection],
	targetConnections: Array[AnchorConnection],
	footprint: NavigationFootprintData,
	graph: AnchorGraphData,
	target: Vector2,
) -> AnchorGraphPath:
	var open: Array[Vector2i] = []
	var closed: Dictionary = { }

	var gScore: Dictionary = { }
	var fScore: Dictionary = { }

	var parentNode: Dictionary = { }
	var parentEdge: Dictionary = { }
	var sourceConnection: Dictionary = { }

	var targetByNode: Dictionary = { }
	for connection: AnchorConnection in targetConnections:
		if not targetByNode.has(connection.nodeKey):
			targetByNode[connection.nodeKey] = connection
			continue

		var previous: AnchorConnection = targetByNode[connection.nodeKey]
		if connection.cost < previous.cost - EPSILON:
			targetByNode[connection.nodeKey] = connection

	# Multi-source 시작점
	for connection: AnchorConnection in startConnections:
		var nodeKey: Vector2i = connection.nodeKey
		var previousCost: float = float(gScore.get(nodeKey, BIG_NUMBER))
		if connection.cost >= previousCost - EPSILON:
			continue

		gScore[nodeKey] = connection.cost
		fScore[nodeKey] = (
			connection.cost + _GetAnchorPosition(footprint, nodeKey).distance_to(target)
		)

		sourceConnection[nodeKey] = connection

		if not open.has(nodeKey):
			open.append(nodeKey)

	var bestGoalNode: Vector2i = Vector2i(-1, -1)
	var bestGoalCost: float = BIG_NUMBER

	while not open.is_empty():
		var currentKey: Vector2i = _PopBestAnchorNode(open, fScore)
		if closed.has(currentKey):
			continue

		var currentF: float = float(fScore.get(currentKey, BIG_NUMBER))
		if currentF >= bestGoalCost - EPSILON:
			break

		closed[currentKey] = true
		var currentG: float = float(gScore.get(currentKey, BIG_NUMBER))

		# 이 Anchor에서 바로 Target Region local path로 연결 가능
		if targetByNode.has(currentKey):
			var targetConnection: AnchorConnection = targetByNode[currentKey]
			var totalCost: float = (currentG + targetConnection.cost)
			if totalCost < bestGoalCost - EPSILON:
				bestGoalCost = totalCost
				bestGoalNode = currentKey

		if not graph.edgesByNode.has(currentKey):
			continue

		var edges: Array = graph.edgesByNode[currentKey]
		for edgeValue: Variant in edges:
			var edge: AnchorGraphEdge = edgeValue as AnchorGraphEdge
			if edge == null or edge.route == null:
				continue

			var nextKey: Vector2i = Vector2i(edge.toPortalId, edge.toAnchorIndex)
			if closed.has(nextKey):
				continue

			var tentativeG: float = (currentG + edge.route.cost)
			var previousG: float = float(gScore.get(nextKey, BIG_NUMBER))
			if tentativeG >= previousG - EPSILON:
				continue

			gScore[nextKey] = tentativeG

			var nextPosition: Vector2 = _GetAnchorPosition(footprint, nextKey)

			fScore[nextKey] = (tentativeG + nextPosition.distance_to(target))

			parentNode[nextKey] = currentKey
			parentEdge[nextKey] = edge
			sourceConnection[nextKey] = sourceConnection[currentKey]

			if not open.has(nextKey):
				open.append(nextKey)

	if bestGoalNode.x < 0:
		return null

	var result: AnchorGraphPath = AnchorGraphPath.new()
	result.startConnection = sourceConnection[bestGoalNode]
	result.targetConnection = targetByNode[bestGoalNode]
	result.cost = bestGoalCost

	var reversedEdges: Array[AnchorGraphEdge] = []
	var currentKey: Vector2i = bestGoalNode

	while parentNode.has(currentKey):
		var edge: AnchorGraphEdge = parentEdge[currentKey]
		reversedEdges.append(edge)

		currentKey = parentNode[currentKey]

	reversedEdges.reverse()
	result.edges = reversedEdges

	return result


func _GetAnchorPosition(footprint: NavigationFootprintData, nodeKey: Vector2i) -> Vector2:
	if not _IsValidPortalAnchor(footprint, nodeKey.x, nodeKey.y):
		return Vector2.ZERO

	return footprint.portals[nodeKey.x].anchors[nodeKey.y]


func _PopBestAnchorNode(open: Array[Vector2i], fScore: Dictionary) -> Vector2i:
	var bestIndex: int = 0
	var bestScore: float = BIG_NUMBER

	for index: int in range(open.size()):
		var nodeKey: Vector2i = open[index]
		var score: float = float(fScore.get(nodeKey, BIG_NUMBER))

		if score >= bestScore:
			continue

		bestScore = score
		bestIndex = index

	var result: Vector2i = open[bestIndex]
	open.remove_at(bestIndex)

	return result


func _BuildHierarchicalPath(target: Vector2, graphPath: AnchorGraphPath) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()

	# Start → 첫 Portal Anchor
	for point: Vector2 in graphPath.startConnection.path:
		_AppendUniquePoint(result, point)

	# Portal Anchor → Portal Anchor
	for edge: AnchorGraphEdge in graphPath.edges:
		var routePath: PackedVector2Array = edge.route.path

		if edge.reversed:
			for index: int in range(routePath.size() - 1, -1, -1):
				_AppendUniquePoint(result, routePath[index])
		else:
			for point: Vector2 in routePath:
				_AppendUniquePoint(result, point)

	# targetConnection.path는
	# Target → 마지막 Anchor 방향으로 만들어졌으므로 뒤집는다.
	var targetPath: PackedVector2Array = graphPath.targetConnection.path

	for index: int in range(targetPath.size() - 1, -1, -1):
		_AppendUniquePoint(result, targetPath[index])

	_AppendUniquePoint(result, target)

	return result


func _AppendUniquePoint(path: PackedVector2Array, point: Vector2) -> void:
	if (not path.is_empty() and path[path.size() - 1].distance_squared_to(point) <= EPSILON):
		return

	path.append(point)

#region HeapLess
func _HeapLess(aIndex: int, bIndex: int) -> bool:
	if absf(_pathState.f[aIndex] - _pathState.f[bIndex]) > EPSILON:
		return _pathState.f[aIndex] < _pathState.f[bIndex]

	if absf(_pathState.turnCost[aIndex] - _pathState.turnCost[bIndex]) > EPSILON:
		return _pathState.turnCost[aIndex] < _pathState.turnCost[bIndex]

	if absf(_pathState.h[aIndex] - _pathState.h[bIndex]) > EPSILON:
		return _pathState.h[aIndex] < _pathState.h[bIndex]

	return aIndex < bIndex

#endregion
