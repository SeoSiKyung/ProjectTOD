class_name NavigationBaker
extends Node

@export var navigationMask: Texture2D
@export var cellSize: int = 8
@export var worldOrigin: Vector2 = Vector2.ZERO
@export var bakeHalfSizes: PackedInt32Array = PackedInt32Array([16, 32])
@export_range(0.0, 1.0, 0.01) var blockedThreshold: float = 0.5
@export_range(0.0, 1.0, 0.01) var portalRedThreshold: float = 0.8
@export_range(0.0, 1.0, 0.01) var portalOtherThreshold: float = 0.2
@export_range(1, 5, 1) var maxPortalAnchors: int = 4
@export_dir var outputDirectory: String = "res://maps"

#region Class
class MaskBakeData:
	var blocked: PackedByteArray = PackedByteArray()
	var portalMap: PackedByteArray = PackedByteArray()


class PortalBakeResult:
	var portals: Array[NavigationPortalData] = []
	var success: bool = true


class RouteSearchState:
	var g: PackedFloat64Array = PackedFloat64Array()
	var f: PackedFloat64Array = PackedFloat64Array()
	var parent: PackedInt32Array = PackedInt32Array()
	var closed: PackedByteArray = PackedByteArray()
	var heapPosition: PackedInt32Array = PackedInt32Array()

	var touched: Array[int] = []
	var touchedMap: PackedByteArray = PackedByteArray()


	func Resize(size: int) -> void:
		g.resize(size)
		f.resize(size)
		parent.resize(size)
		closed.resize(size)
		heapPosition.resize(size)

		touchedMap.resize(size)

		g.fill(Math.BIG_NUMBER)
		f.fill(Math.BIG_NUMBER)
		parent.fill(-1)
		closed.fill(0)
		heapPosition.fill(-1)

		touchedMap.fill(0)
		touched.clear()


	func Reset() -> void:
		for index: int in touched:
			g[index] = Math.BIG_NUMBER
			f[index] = Math.BIG_NUMBER
			parent[index] = -1
			closed[index] = 0
			heapPosition[index] = -1

			touchedMap[index] = 0

		touched.clear()


	func Touch(index: int) -> void:
		if touchedMap[index] != 0:
			return

		touchedMap[index] = 1
		touched.append(index)


class RouteHeap extends Heap.IndexedIntHeap:
	var _state: RouteSearchState


	func _init(state: RouteSearchState) -> void:
		_state = state
		super(state.heapPosition)


	func _Less(a: Variant, b: Variant) -> bool:
		var aIndex: int = int(a)
		var bIndex: int = int(b)
		if absf(_state.f[aIndex] - _state.f[bIndex]) > Math.EPSILON:
			return _state.f[aIndex] < _state.f[bIndex]

		return aIndex < bIndex

#endregion

#region Public
func BakeNavigation() -> bool:
	if not _ValidateBakeSettings():
		return false

	var outputPath: String = _GetOutputPath()
	var image: Image = navigationMask.get_image()
	if not _ValidateBakeImage(image):
		return false

	var gridWidth: int = image.get_width() / cellSize
	var gridHeight: int = image.get_height() / cellSize
	var maskData: MaskBakeData = _AnalyzeMask(image, gridWidth, gridHeight)

	var prefixSum = _MakePrefixSum(maskData.blocked, gridWidth, gridHeight)

	var data: NavigationData = _MakeNavigationData(
		maskData.blocked,
		maskData.portalMap,
		prefixSum,
		gridWidth,
		gridHeight,
	)
	if data == null:
		return false

	if not _SaveNavigationData(data, outputPath):
		return false

	return true

#endregion

#region Validation / Setup
func _ValidateBakeSettings() -> bool:
	if navigationMask == null:
		push_error("Navigation Mask가 지정되지 않았습니다.")
		return false

	if cellSize <= 0:
		push_error("cellSize는 1 이상이어야 합니다.")
		return false

	if not _ValidateBakeHalfSizes():
		return false

	if _GetOutputPath().is_empty():
		push_error("Navigation Mask의 파일 경로를 찾을 수 없습니다.")
		return false

	return true


func _ValidateBakeHalfSizes() -> bool:
	if bakeHalfSizes.is_empty():
		push_error("bakeHalfSizes에는 하나 이상의 halfSize가 필요합니다.")
		return false

	var usedHalfSizes: Dictionary[int, bool] = { }
	for halfSize: int in bakeHalfSizes:
		if halfSize <= 0:
			push_error("bakeHalfSizes의 halfSize는 1 이상이어야 합니다: %d" % halfSize)
			return false

		if usedHalfSizes.has(halfSize):
			push_error("bakeHalfSizes에 중복된 halfSize가 있습니다: %d" % halfSize)
			return false

		usedHalfSizes[halfSize] = true

	return true


func _ValidateBakeImage(image: Image) -> bool:
	if image == null or image.is_empty():
		push_error("Navigation Mask 이미지를 읽을 수 없습니다.")
		return false

	var imageWidth: int = image.get_width()
	var imageHeight: int = image.get_height()
	if imageWidth <= 0 or imageHeight <= 0:
		push_error("Navigation Mask 크기가 잘못되었습니다.")
		return false

	if imageWidth % cellSize != 0 or imageHeight % cellSize != 0:
		push_error("Navigation Mask 크기는 cellSize의 배수여야 합니다.")
		return false

	return true


func _GetOutputPath() -> String:
	if navigationMask == null:
		return ""

	var texturePath: String = navigationMask.resource_path
	if texturePath.is_empty():
		return ""

	return outputDirectory.path_join(texturePath.get_file().get_basename() + "_navigation.res")

#endregion

#region Analyze Mask
func _AnalyzeMask(image: Image, gridWidth: int, gridHeight: int) -> MaskBakeData:
	var result: MaskBakeData = MaskBakeData.new()
	var total: int = gridWidth * gridHeight

	result.blocked.resize(total)
	result.blocked.fill(0)

	result.portalMap.resize(total)
	result.portalMap.fill(0)

	for gridY: int in range(gridHeight):
		for gridX: int in range(gridWidth):
			var isBlocked: bool = false
			var isPortal: bool = false

			var startX: int = gridX * cellSize
			var startY: int = gridY * cellSize
			for pixelY: int in range(startY, startY + cellSize):
				for pixelX: int in range(startX, startX + cellSize):
					var color: Color = image.get_pixel(pixelX, pixelY)

					# Portal은 실제 장애물이 아니므로 먼저 판별한다.
					if _IsPortalPixel(color):
						isPortal = true
						continue

					if _IsBlockedPixel(color):
						isBlocked = true

			var index: int = gridY * gridWidth + gridX
			result.blocked[index] = 1 if isBlocked else 0
			result.portalMap[index] = 1 if isPortal else 0

	return result


func _IsPortalPixel(color: Color) -> bool:
	return (
		color.r >= portalRedThreshold and color.g <= portalOtherThreshold
		and color.b <= portalOtherThreshold
	)


func _IsBlockedPixel(color: Color) -> bool:
	var brightness: float = (color.r + color.g + color.b) / 3.0
	return brightness < blockedThreshold

#endregion

#region Make Prefix Sum
func _MakePrefixSum(blocked: PackedByteArray, gridWidth: int, gridHeight: int) -> PackedInt32Array:
	var prefixWidth: int = gridWidth + 1

	var prefixSum: PackedInt32Array = PackedInt32Array()
	prefixSum.resize(prefixWidth * (gridHeight + 1))
	prefixSum.fill(0)

	for y: int in range(gridHeight):
		var rowSum: int = 0
		for x: int in range(gridWidth):
			var blockedIndex: int = y * gridWidth + x
			rowSum += blocked[blockedIndex]

			var prefixIndex: int = (y + 1) * prefixWidth + (x + 1)
			var previousRowIndex: int = y * prefixWidth + (x + 1)
			prefixSum[prefixIndex] = prefixSum[previousRowIndex] + rowSum

	return prefixSum

#endregion

#region Navigation Data
func _MakeNavigationData(
	blocked: PackedByteArray,
	portalMap: PackedByteArray,
	prefixSum: PackedInt32Array,
	gridWidth: int,
	gridHeight: int,
) -> NavigationData:
	var regionMap: PackedInt32Array = _MakeRegionMap(blocked, portalMap, gridWidth, gridHeight)

	var regions: Array[NavigationRegionData] = _MakeRegions(regionMap)

	var portalBakeResult: PortalBakeResult = _MakePortals(
		portalMap,
		regionMap,
		gridWidth,
		gridHeight,
	)
	if not portalBakeResult.success:
		return null

	var portals: Array[NavigationPortalData] = portalBakeResult.portals

	_ConnectRegionsToPortals(regions, portals)
	_ConnectPortalNeighbors(regions, portals)

	var data: NavigationData = NavigationData.new()
	data.cellSize = cellSize
	data.gridSize = Vector2i(gridWidth, gridHeight)
	data.worldOrigin = worldOrigin

	data.blocked = blocked
	data.prefixSum = prefixSum
	data.portalMap = portalMap
	data.regionMap = regionMap

	data.regions = regions
	data.portals = portals

	data.footprints = _MakeFootprints(regions, portals, regionMap, prefixSum, gridWidth, gridHeight)

	return data


func _SaveNavigationData(data: NavigationData, outputPath: String) -> bool:
	var directory: String = outputPath.get_base_dir()
	var absoluteDirectory: String = ProjectSettings.globalize_path(directory)

	var dirError: Error = DirAccess.make_dir_recursive_absolute(absoluteDirectory)
	if dirError != OK and dirError != ERR_ALREADY_EXISTS:
		push_error("Navigation 저장 폴더 생성 실패: %s" % directory)
		return false

	var saveError: Error = ResourceSaver.save(data, outputPath)
	if saveError != OK:
		push_error("Navigation Data 저장 실패: %s" % error_string(saveError))
		return false

	return true

#endregion

#region Region / Portal
func _MakeRegionMap(
	blocked: PackedByteArray,
	portalMap: PackedByteArray,
	gridWidth: int,
	gridHeight: int,
) -> PackedInt32Array:
	var total: int = gridWidth * gridHeight

	var regionMap: PackedInt32Array = PackedInt32Array()
	regionMap.resize(total)
	regionMap.fill(-1)

	var queue: Array[int] = []
	var regionId: int = 0
	for startIndex: int in range(total):
		if blocked[startIndex] != 0 or portalMap[startIndex] != 0 or regionMap[startIndex] >= 0:
			continue

		queue.clear()
		queue.append(startIndex)
		regionMap[startIndex] = regionId

		var head: int = 0
		while head < queue.size():
			var currentIndex: int = queue[head]
			head += 1

			var currentX: int = currentIndex % gridWidth
			var currentY: int = int(currentIndex / gridWidth)
			for direction: Vector2i in Math.DIRECTIONS_8:
				var nextX: int = currentX + direction.x
				var nextY: int = currentY + direction.y
				if (!(0 <= nextX and nextX < gridWidth) or !(0 <= nextY and nextY < gridHeight)):
					continue

				if direction.x != 0 and direction.y != 0:
					var horizontalX: int = currentX + direction.x
					var horizontalY: int = currentY
					var verticalX: int = currentX
					var verticalY: int = currentY + direction.y

					var horizontalIndex: int = horizontalY * gridWidth + horizontalX
					var verticalIndex: int = verticalY * gridWidth + verticalX
					if (
						blocked[horizontalIndex] != 0 or portalMap[horizontalIndex] != 0
						or blocked[verticalIndex] != 0 or portalMap[verticalIndex] != 0
					):
						continue

				# Region을 나눌 때만 Portal을 벽으로 취급
				var nextIndex: int = nextY * gridWidth + nextX
				if blocked[nextIndex] != 0 or portalMap[nextIndex] != 0 or regionMap[nextIndex] >= 0:
					continue

				regionMap[nextIndex] = regionId
				queue.append(nextIndex)

		regionId += 1

	return regionMap


func _MakeRegions(regionMap: PackedInt32Array) -> Array[NavigationRegionData]:
	var maxRegionId: int = -1
	for regionId: int in regionMap:
		maxRegionId = maxi(maxRegionId, regionId)

	var result: Array[NavigationRegionData] = []
	for regionId: int in range(maxRegionId + 1):
		var region: NavigationRegionData = NavigationRegionData.new()
		region.id = regionId
		result.append(region)

	return result


func _MakePortals(
	portalMap: PackedByteArray,
	regionMap: PackedInt32Array,
	gridWidth: int,
	gridHeight: int,
) -> PortalBakeResult:
	var result: PortalBakeResult = PortalBakeResult.new()

	var total: int = gridWidth * gridHeight
	var visited: PackedByteArray = PackedByteArray()
	visited.resize(total)
	visited.fill(0)

	var queue: Array[int] = []
	for startIndex: int in range(total):
		if portalMap[startIndex] == 0 or visited[startIndex] != 0:
			continue

		var portalCells: Array[Vector2i] = []

		queue.clear()
		queue.append(startIndex)
		visited[startIndex] = 1

		var head: int = 0
		while head < queue.size():
			var currentIndex: int = queue[head]
			head += 1

			var currentCell: Vector2i = Vector2i(
				currentIndex % gridWidth,
				int(currentIndex / gridWidth),
			)

			portalCells.append(currentCell)
			for direction: Vector2i in Math.DIRECTIONS_8:
				var nextCell: Vector2i = currentCell + direction
				if (
					!(0 <= nextCell.x and nextCell.x < gridWidth)
					or !(0 <= nextCell.y and nextCell.y < gridHeight)
				):
					continue

				var nextIndex: int = nextCell.y * gridWidth + nextCell.x
				if portalMap[nextIndex] == 0 or visited[nextIndex] != 0:
					continue

				visited[nextIndex] = 1
				queue.append(nextIndex)

		var portal: NavigationPortalData = _MakePortalData(
			result.portals.size(),
			portalCells,
			regionMap,
			gridWidth,
			gridHeight,
		)
		if portal == null:
			result.success = false
			return result

		result.portals.append(portal)

	return result


# 포탈 양쪽 Region 찾기
func _MakePortalData(
	portalId: int,
	portalCells: Array[Vector2i],
	regionMap: PackedInt32Array,
	gridWidth: int,
	gridHeight: int,
) -> NavigationPortalData:
	if portalCells.is_empty():
		return null

	var adjacentRegions: Dictionary[int, bool] = { }
	for cell: Vector2i in portalCells:
		for direction: Vector2i in Math.DIRECTIONS_8:
			var neighbor: Vector2i = cell + direction
			if (
				!(0 <= neighbor.x and neighbor.x < gridWidth)
				or !(0 <= neighbor.y and neighbor.y < gridHeight)
			):
				continue

			var neighborIndex: int = neighbor.y * gridWidth + neighbor.x
			var regionId: int = regionMap[neighborIndex]
			if regionId >= 0:
				adjacentRegions[regionId] = true

	var regionIds: Array[int] = []
	for regionId: int in adjacentRegions:
		regionIds.append(regionId)

	regionIds.sort()
	if regionIds.size() != 2:
		push_error("Portal %d의 인접 Region 수가 %d개입니다." % [portalId, regionIds.size()])
		return null

	var endpoints: Array[Vector2i] = _FindPortalEndpoints(portalCells)

	var portal: NavigationPortalData = NavigationPortalData.new()
	portal.id = portalId
	portal.startCell = endpoints[0]
	portal.endCell = endpoints[1]
	portal.regionA = regionIds[0]
	portal.regionB = regionIds[1]

	return portal


func _FindPortalEndpoints(cells: Array[Vector2i]) -> Array[Vector2i]:
	if cells.size() == 1:
		return [cells[0], cells[0]]

	var bestA: Vector2i = cells[0]
	var bestB: Vector2i = cells[1]
	var bestDistance: int = -1
	for aIndex: int in range(cells.size()):
		for bIndex: int in range(aIndex + 1, cells.size()):
			var delta: Vector2i = cells[bIndex] - cells[aIndex]
			var distance: int = delta.x * delta.x + delta.y * delta.y
			if distance <= bestDistance:
				continue

			bestDistance = distance
			bestA = cells[aIndex]
			bestB = cells[bIndex]

	return [bestA, bestB]


func _ConnectRegionsToPortals(
	regions: Array[NavigationRegionData],
	portals: Array[NavigationPortalData],
) -> void:
	for portal: NavigationPortalData in portals:
		regions[portal.regionA].portalIds.append(portal.id)
		regions[portal.regionB].portalIds.append(portal.id)


func _ConnectPortalNeighbors(
	regions: Array[NavigationRegionData],
	portals: Array[NavigationPortalData],
) -> void:
	for region: NavigationRegionData in regions:
		var portalCount: int = region.portalIds.size()
		for aIndex: int in range(portalCount):
			var portalAId: int = region.portalIds[aIndex]

			for bIndex: int in range(aIndex + 1, portalCount):
				var portalBId: int = region.portalIds[bIndex]

				var portalA: NavigationPortalData = portals[portalAId]
				if portalA.neighborPortalIds.find(portalBId) < 0:
					portalA.neighborPortalIds.append(portalBId)

				var portalB: NavigationPortalData = portals[portalBId]
				if portalB.neighborPortalIds.find(portalAId) < 0:
					portalB.neighborPortalIds.append(portalAId)

	for portal: NavigationPortalData in portals:
		portal.neighborPortalIds.sort()

#endregion

#region Footprint
func _MakeFootprints(
	regions: Array[NavigationRegionData],
	portals: Array[NavigationPortalData],
	regionMap: PackedInt32Array,
	prefixSum: PackedInt32Array,
	gridWidth: int,
	gridHeight: int,
) -> Array[NavigationFootprintData]:
	var result: Array[NavigationFootprintData] = []

	for halfSize: int in bakeHalfSizes:
		var placeableMap: PackedByteArray = _MakePlaceableMap(
			halfSize,
			prefixSum,
			gridWidth,
			gridHeight,
		)

		var footprint: NavigationFootprintData = NavigationFootprintData.new()
		footprint.halfSize = halfSize

		for portal: NavigationPortalData in portals:
			var portalData: NavigationFootprintPortalData = _MakeFootprintPortalData(
				portal,
				halfSize,
				placeableMap,
				gridWidth,
			)
			footprint.portals.append(portalData)

		footprint.portalRoutes = _MakePortalRoutes(
			regions,
			footprint,
			regionMap,
			placeableMap,
			gridWidth,
			gridHeight,
		)

		result.append(footprint)

	return result


func _MakeFootprintPortalData(
	portal: NavigationPortalData,
	halfSize: int,
	placeableMap: PackedByteArray,
	gridWidth: int,
) -> NavigationFootprintPortalData:
	var result: NavigationFootprintPortalData = NavigationFootprintPortalData.new()

	var candidates: Array[Vector2i] = _GetTraversablePortalCells(portal, placeableMap, gridWidth)

	result.anchors = _MakePortalAnchors(candidates, halfSize)

	return result


func _MakePortalAnchors(candidates: Array[Vector2i], halfSize: int) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	if candidates.is_empty():
		return result

	var maximumCount: int = mini(maxPortalAnchors, candidates.size())
	if maximumCount == 1:
		result.append(_CellCenterToWorld(candidates[0]))
		return result

	var firstPoint: Vector2 = _CellCenterToWorld(candidates[0])
	var lastPoint: Vector2 = _CellCenterToWorld(candidates[candidates.size() - 1])
	var usableLength: float = firstPoint.distance_to(lastPoint)

	# 진입로끼리 너무 촘촘하지 않게 유닛 지름 정도를 간격으로
	var desiredSpacing: float = maxf(float(halfSize * 2), float(cellSize * 4))
	var desiredCount: int = (int(floor(usableLength / desiredSpacing)) + 1)

	# 충분히 긴 Portal이면 최소 3개, 짧은 Portal이면 1~2개도 허용
	var minimumCount: int = mini(3, maximumCount)
	var anchorCount: int = clampi(desiredCount, minimumCount, maximumCount)
	if anchorCount == 1:
		var middleIndex: int = candidates.size() >> 1
		result.append(_CellCenterToWorld(candidates[middleIndex]))

		return result

	for anchorIndex: int in range(anchorCount):
		var ratio: float = (float(anchorIndex) / float(anchorCount - 1))
		var candidateIndex: int = roundi(ratio * float(candidates.size() - 1))
		result.append(_CellCenterToWorld(candidates[candidateIndex]))

	return result


func _GetTraversablePortalCells(
	portal: NavigationPortalData,
	placeableMap: PackedByteArray,
	gridWidth: int,
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []

	for cell: Vector2i in _GetPortalCells(portal):
		var index: int = cell.y * gridWidth + cell.x
		if placeableMap[index] == 0:
			continue

		result.append(cell)

	return result


func _GetPortalCells(portal: NavigationPortalData) -> Array[Vector2i]:
	var result: Array[Vector2i] = []

	var x0: int = portal.startCell.x
	var y0: int = portal.startCell.y
	var x1: int = portal.endCell.x
	var y1: int = portal.endCell.y

	var dx: int = absi(x1 - x0)
	var dy: int = -absi(y1 - y0)
	var error: int = dx + dy

	var stepX: int = 1 if x0 < x1 else -1
	var stepY: int = 1 if y0 < y1 else -1
	while true:
		result.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break

		var error2: int = error * 2
		if error2 >= dy:
			error += dy
			x0 += stepX
		if error2 <= dx:
			error += dx
			y0 += stepY

	return result


func _MakePlaceableMap(
	halfSize: int,
	prefixSum: PackedInt32Array,
	gridWidth: int,
	gridHeight: int,
) -> PackedByteArray:
	var total: int = gridWidth * gridHeight
	var result: PackedByteArray = PackedByteArray()
	result.resize(total)
	result.fill(0)

	for index: int in range(total):
		var cell: Vector2i = Vector2i(index % gridWidth, int(index / gridWidth))
		var center: Vector2 = _CellCenterToWorld(cell)
		if _CanPlaceStatic(center, halfSize, prefixSum, gridWidth, gridHeight):
			result[index] = 1

	return result


func _CanPlaceStatic(
	center: Vector2,
	halfSize: int,
	prefixSum: PackedInt32Array,
	gridWidth: int,
	gridHeight: int,
) -> bool:
	var half: Vector2 = Vector2(float(halfSize), float(halfSize))

	var rectMin: Vector2 = center - half
	var rectMax: Vector2 = center + half
	var worldSize: Vector2 = Vector2(float(gridWidth * cellSize), float(gridHeight * cellSize))
	var worldEnd: Vector2 = worldOrigin + worldSize
	if rectMin.x < worldOrigin.x or rectMin.y < worldOrigin.y:
		return false

	if rectMax.x > worldEnd.x or rectMax.y > worldEnd.y:
		return false

	var localMin: Vector2 = rectMin - worldOrigin
	var localMax: Vector2 = rectMax - worldOrigin

	var minX: int = floori(localMin.x / float(cellSize))
	var minY: int = floori(localMin.y / float(cellSize))
	var maxX: int = floori((localMax.x - Math.EPSILON) / float(cellSize))
	var maxY: int = floori((localMax.y - Math.EPSILON) / float(cellSize))

	var prefixWidth: int = gridWidth + 1
	var blockedCount: int = (
		prefixSum[(maxY + 1) * prefixWidth + (maxX + 1)]
		- prefixSum[minY * prefixWidth + (maxX + 1)] - prefixSum[(maxY + 1) * prefixWidth + minX]
		+ prefixSum[minY * prefixWidth + minX]
	)

	return blockedCount == 0

#endregion

#region Portal Route
func _MakePortalRoutes(
	regions: Array[NavigationRegionData],
	footprint: NavigationFootprintData,
	regionMap: PackedInt32Array,
	placeableMap: PackedByteArray,
	gridWidth: int,
	gridHeight: int,
) -> Array[NavigationPortalRouteData]:
	var result: Array[NavigationPortalRouteData] = []

	var searchState: RouteSearchState = RouteSearchState.new()
	searchState.Resize(gridWidth * gridHeight)

	for region: NavigationRegionData in regions:
		var portalCount: int = region.portalIds.size()
		for aIndex: int in range(portalCount - 1):
			var portalAId: int = region.portalIds[aIndex]
			var portalAData: NavigationFootprintPortalData = footprint.portals[portalAId]
			if portalAData.anchors.is_empty():
				continue

			for bIndex: int in range(aIndex + 1, portalCount):
				var portalBId: int = region.portalIds[bIndex]
				var portalBData: NavigationFootprintPortalData = footprint.portals[portalBId]
				if portalBData.anchors.is_empty():
					continue

				for fromAnchorIndex: int in range(portalAData.anchors.size()):
					var fromPoint: Vector2 = portalAData.anchors[fromAnchorIndex]
					var startCell: Vector2i = _WorldToCell(fromPoint)

					for toAnchorIndex: int in range(portalBData.anchors.size()):
						var toPoint: Vector2 = portalBData.anchors[toAnchorIndex]
						var targetCell: Vector2i = _WorldToCell(toPoint)

						var path: PackedVector2Array = _FindPortalRoute(
							startCell,
							targetCell,
							region.id,
							regionMap,
							placeableMap,
							gridWidth,
							gridHeight,
							searchState,
						)
						if path.is_empty():
							continue

						var cost: float = _GetPathCost(path)

						var route: NavigationPortalRouteData = NavigationPortalRouteData.new()
						route.regionId = region.id
						route.fromPortalId = portalAId
						route.fromAnchorIndex = fromAnchorIndex
						route.toPortalId = portalBId
						route.toAnchorIndex = toAnchorIndex
						route.path = path
						route.cost = cost

						result.append(route)

	return result


func _FindPortalRoute(
	startCell: Vector2i,
	targetCell: Vector2i,
	regionId: int,
	regionMap: PackedInt32Array,
	placeableMap: PackedByteArray,
	gridWidth: int,
	gridHeight: int,
	state: RouteSearchState,
) -> PackedVector2Array:
	if (
		not Grid.IsCellInGrid(startCell, gridWidth, gridHeight)
		or not Grid.IsCellInGrid(targetCell, gridWidth, gridHeight)
	):
		return PackedVector2Array()

	state.Reset()

	var startIndex: int = startCell.y * gridWidth + startCell.x
	var targetIndex: int = targetCell.y * gridWidth + targetCell.x

	state.Touch(startIndex)
	state.g[startIndex] = 0.0
	state.f[startIndex] = Math.OctileDistance(startCell, targetCell)
	state.parent[startIndex] = -1

	var heap: RouteHeap = RouteHeap.new(state)
	heap.PushOrUpdate(startIndex)
	while not heap.IsEmpty():
		var currentIndex: int = int(heap.Pop())
		if state.closed[currentIndex] != 0:
			continue

		state.closed[currentIndex] = 1
		if currentIndex == targetIndex:
			return _ReconstructPortalRoute(state.parent, targetIndex, gridWidth)

		var currentCell: Vector2i = Vector2i(
			currentIndex % gridWidth,
			int(currentIndex / gridWidth),
		)
		for direction: Vector2i in Math.DIRECTIONS_8:
			var nextCell: Vector2i = currentCell + direction
			if not _IsRouteCellAllowed(
				nextCell,
				regionId,
				startCell,
				targetCell,
				regionMap,
				placeableMap,
				gridWidth,
				gridHeight,
			):
				continue

			# 대각선 corner-cut 방지
			if direction.x != 0 and direction.y != 0:
				var horizontal: Vector2i = Vector2i(currentCell.x + direction.x, currentCell.y)
				var vertical: Vector2i = Vector2i(currentCell.x, currentCell.y + direction.y)

				if not _IsRouteCellAllowed(
					horizontal,
					regionId,
					startCell,
					targetCell,
					regionMap,
					placeableMap,
					gridWidth,
					gridHeight,
				):
					continue

				if not _IsRouteCellAllowed(
					vertical,
					regionId,
					startCell,
					targetCell,
					regionMap,
					placeableMap,
					gridWidth,
					gridHeight,
				):
					continue

			var nextIndex: int = nextCell.y * gridWidth + nextCell.x
			if state.closed[nextIndex] != 0:
				continue

			var stepCost: float = 1.0
			if direction.x != 0 and direction.y != 0:
				stepCost = Math.SQRT_2

			var tentativeG: float = (state.g[currentIndex] + stepCost)
			if tentativeG >= state.g[nextIndex] - Math.EPSILON:
				continue

			state.Touch(nextIndex)
			state.g[nextIndex] = tentativeG
			state.parent[nextIndex] = currentIndex
			state.f[nextIndex] = (tentativeG + Math.OctileDistance(nextCell, targetCell))

			heap.PushOrUpdate(nextIndex)

	return PackedVector2Array()


func _ReconstructPortalRoute(
	parent: PackedInt32Array,
	targetIndex: int,
	gridWidth: int,
) -> PackedVector2Array:
	var reversed: PackedVector2Array = PackedVector2Array()

	var current: int = targetIndex
	while current >= 0:
		var cell: Vector2i = Vector2i(current % gridWidth, int(current / gridWidth))
		reversed.append(_CellCenterToWorld(cell))
		current = parent[current]

	reversed.reverse()

	return reversed


func _IsRouteCellAllowed(
	cell: Vector2i,
	regionId: int,
	startCell: Vector2i,
	targetCell: Vector2i,
	regionMap: PackedInt32Array,
	placeableMap: PackedByteArray,
	gridWidth: int,
	gridHeight: int,
) -> bool:
	if not Grid.IsCellInGrid(cell, gridWidth, gridHeight):
		return false

	var index: int = cell.y * gridWidth + cell.x
	if placeableMap[index] == 0:
		return false

	if cell == startCell or cell == targetCell:
		return true

	# 현재 Region 내부 또는 Portal 셀은 이동 가능.
	return regionMap[index] == regionId or regionMap[index] < 0

#endregion

#region Coordinates / Utility
func _CellCenterToWorld(cell: Vector2i) -> Vector2:
	return (
		worldOrigin
		+ Vector2((float(cell.x) + 0.5) * float(cellSize), (float(cell.y) + 0.5) * float(cellSize))
	)


func _WorldToCell(position: Vector2) -> Vector2i:
	var local: Vector2 = position - worldOrigin
	return Vector2i(floori(local.x / float(cellSize)), floori(local.y / float(cellSize)))


func _GetPathCost(path: PackedVector2Array) -> float:
	var result: float = 0.0
	for index: int in range(1, path.size()):
		result += path[index - 1].distance_to(path[index])

	return result

#endregion
