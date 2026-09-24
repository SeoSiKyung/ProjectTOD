class_name NavigationService
extends Resource

@export var navigationData: NavigationData

@export_range(8, 256, 8) var localSearchMarginCells: int = 64
@export_range(8, 256, 8) var anchorConnectionCacheCapacity: int = 64
@export_range(1.0, 3.0, 0.05) var formationCompactRadiusScale: float = 1.25

var _navigationReady: bool = false

var _navCellSize: float = 8.0
var _gridWidth: int = 0
var _gridHeight: int = 0
var _worldRect: Rect2 = Rect2()

var _blocked: PackedByteArray = PackedByteArray()
var _prefixSum: PackedInt32Array = PackedInt32Array()

var _regionQuery: NavigationRegionQuery

var _portalMap: PackedByteArray = PackedByteArray()
var _regionMap: PackedInt32Array = PackedInt32Array()
var _regions: Array[NavigationRegionData] = []

var _startRegionIds: Array[int] = []
var _targetRegionIds: Array[int] = []

var _footprintDataByHalfSize: Dictionary[int, NavigationFootprintData] = { }

var _anchorGraphByHalfSize: Dictionary[int, NavigationAnchorTypes.GraphData] = { }
var _regionAnchorTopologyCache: Dictionary[Vector2i, NavigationAnchorTypes.RegionTopology] = { }

var _anchorConnectionCache: NavigationAnchorConnectionCache

var _bestAnchorConnectionByNode: Dictionary[Vector2i, NavigationAnchorTypes.Connection] = { }
var _reachableAnchorComponents: Dictionary[int, bool] = { }
var _addedAnchorNodes: Dictionary[Vector2i, bool] = { }
var _unreachableAnchorComponents: Dictionary[int, bool] = { }
var _probeAnchorByComponent: Dictionary[int, Vector2i] = { }
var _probeDistanceByComponent: Dictionary[int, float] = { }
var _remainingAnchorNodesByPortal: Dictionary[int, Array] = { }

var _portalAnchorPathsByNode: Dictionary[Vector2i, PackedVector2Array] = { }
var _portalNodesByTargetIndex: Dictionary[int, Array] = { }
var _portalActiveTargetIndices: Array[int] = []
var _portalTargetCells: Array[Vector2i] = []
var _portalGridPathsByTargetIndex: Dictionary[int, PackedVector2Array] = { }

var _gridPathfinder: NavigationGridPathfinder
var _hierarchicalPathfinder: NavigationHierarchicalPathfinder

var _staticQuery: NavigationStaticQuery

var _benchmarkMetrics: NavigationProfileMetrics = null


#region Public API

func Ready() -> void:
	_LoadNavigationData()


func IsReady() -> bool:
	return _navigationReady


func Reload() -> void:
	_LoadNavigationData()


func CanPlaceStatic(center: Vector2, halfSize: int) -> bool:
	return _staticQuery.CanPlace(center, halfSize)


func SegmentClear(start: Vector2, end: Vector2, halfSize: int) -> bool:
	if _benchmarkMetrics != null:
		_benchmarkMetrics.segmentClearQueryCalls += 1

		var startTime: int = Time.get_ticks_usec()
		var result: bool = _staticQuery.SegmentClear(start, end, halfSize, _benchmarkMetrics)

		_benchmarkMetrics.segmentClearQueryUsec += (Time.get_ticks_usec() - startTime)

		return result

	return _staticQuery.SegmentClear(start, end, halfSize)


func GetNearestPlaceablePoint(
	position: Vector2,
	halfSize: int,
	referencePosition: Vector2,
) -> Vector2:
	if CanPlaceStatic(position, halfSize):
		return position

	var navigationMap: NavigationFootprintMapData = _GetFootprintMap(halfSize)

	var pathOffset: Vector2 = _PathLatticeOffset(halfSize)
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
			if targetDistance < bestTargetDistance - Math.EPSILON:
				better = true
			elif absf(targetDistance - bestTargetDistance) <= Math.EPSILON:
				if referenceDistance < bestReferenceDistance - Math.EPSILON:
					better = true
				elif absf(referenceDistance - bestReferenceDistance) <= Math.EPSILON:
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


func GetComponentId(position: Vector2, halfSize: int) -> int:
	if not _navigationReady or not CanPlaceStatic(position, halfSize):
		return -1

	var navigationMap: NavigationFootprintMapData = _GetFootprintMap(halfSize)

	var pathOffset: Vector2 = _PathLatticeOffset(halfSize)
	var pathCell: Vector2i = _GetNearestPathCell(position, halfSize, pathOffset)
	if pathCell.x < 0:
		return -1

	var index: int = Grid.CellToIndex(pathCell, _gridWidth)
	return navigationMap.componentMap[index]


func GetNearestReachablePoint(
	position: Vector2,
	halfSize: int,
	referencePosition: Vector2,
) -> Vector2:
	var componentId: int = GetComponentId(referencePosition, halfSize)
	if componentId < 0:
		return referencePosition

	# 원하는 위치가 그대로 배치 가능하고 기준 위치와 같은 Component라면 정확한 원래 좌표를 사용한다.
	if GetComponentId(position, halfSize) == componentId:
		return position

	# 막혀 있거나 다른 Component라면 기준 Component 안에서 가장 가까운 Path Cell을 찾는다.
	var navigationMap: NavigationFootprintMapData = _GetFootprintMap(halfSize)

	var pathOffset: Vector2 = _PathLatticeOffset(halfSize)

	var reachableCell: Vector2i = _GetNearestCellInComponent(
		position,
		pathOffset,
		componentId,
		navigationMap,
	)
	if reachableCell.x < 0:
		return referencePosition

	return _PathCellToWorld(reachableCell, pathOffset)


func FindPath(start: Vector2, target: Vector2, halfSize: int) -> PackedVector2Array:
	if not _navigationReady:
		return PackedVector2Array()

	if start.distance_squared_to(target) <= Math.EPSILON:
		return PackedVector2Array()

	# FindPath()는 목적지를 보정하지 않는다. 전달된 목적지 자체가 이동 불가능하면 실패한다.
	if not CanPlaceStatic(target, halfSize):
		return PackedVector2Array()

	# 처음부터 직선 이동 가능하면 A*를 생략한다.
	if SegmentClear(start, target, halfSize):
		var directPath: PackedVector2Array = PackedVector2Array()
		directPath.append(target)
		return directPath

	var phaseStart: int = 0

	var footprintData: NavigationFootprintData = _GetFootprintData(halfSize)
	if footprintData == null:
		return _FindFallbackGridPath(start, target, halfSize)

	_regionQuery.FillRegionIds(_startRegionIds, start)
	_regionQuery.FillRegionIds(_targetRegionIds, target)
	if _startRegionIds.is_empty() or _targetRegionIds.is_empty():
		return _FindFallbackGridPath(start, target, halfSize)

	var bestPath: PackedVector2Array = PackedVector2Array()
	var bestCost: float = Math.BIG_NUMBER

	var isSingleSharedRegion: bool = (
		_startRegionIds.size() == 1 and _targetRegionIds.size() == 1
		and _startRegionIds[0] == _targetRegionIds[0]
	)

	if isSingleSharedRegion:
		var localPath: PackedVector2Array = _FindPathInsideRegion(
			start,
			target,
			halfSize,
			_startRegionIds[0],
		)
		if not localPath.is_empty():
			return localPath
	else:
		# Portal 위의 시작/목표처럼 여러 Region에 연결되는 경우에는 양쪽이 공유하는 Region들의 Local Path를 후보로 비교한다.
		for startRegionId: int in _startRegionIds:
			if not _targetRegionIds.has(startRegionId):
				continue

			var localPath: PackedVector2Array = _FindPathInsideRegion(
				start,
				target,
				halfSize,
				startRegionId,
			)
			if localPath.is_empty():
				continue

			var localCost: float = _GetWaypointPathCost(start, localPath)
			if localCost < bestCost - Math.EPSILON:
				bestCost = localCost
				bestPath = localPath

	if _benchmarkMetrics != null:
		phaseStart = Time.get_ticks_usec()
	var startConnections: Array[NavigationAnchorTypes.Connection] = _MakeRegionAnchorConnectionsForRegions(
		start,
		halfSize,
		_startRegionIds,
		footprintData,
	)
	if _benchmarkMetrics != null:
		_benchmarkMetrics.startAnchorConnectionUsec += (Time.get_ticks_usec() - phaseStart)

	if _benchmarkMetrics != null:
		phaseStart = Time.get_ticks_usec()
	var targetConnections: Array[NavigationAnchorTypes.Connection] = _MakeRegionAnchorConnectionsForRegions(
		target,
		halfSize,
		_targetRegionIds,
		footprintData,
	)
	if _benchmarkMetrics != null:
		_benchmarkMetrics.targetAnchorConnectionUsec += (Time.get_ticks_usec() - phaseStart)

	if not startConnections.is_empty() and not targetConnections.is_empty():
		var graph: NavigationAnchorTypes.GraphData = _GetAnchorGraph(halfSize)
		if graph != null:
			if _benchmarkMetrics != null:
				phaseStart = Time.get_ticks_usec()

			var graphPathFound: bool = _hierarchicalPathfinder.FindGraphPath(
				startConnections,
				targetConnections,
				footprintData,
				graph,
				target,
				_benchmarkMetrics,
			)
			if _benchmarkMetrics != null:
				_benchmarkMetrics.anchorGraphUsec += (Time.get_ticks_usec() - phaseStart)

			if graphPathFound and _hierarchicalPathfinder.lastPathCost < bestCost - Math.EPSILON:
				bestPath = _hierarchicalPathfinder.BuildPath(target)
				bestCost = _hierarchicalPathfinder.lastPathCost

	if not bestPath.is_empty():
		return bestPath

	return _FindFallbackGridPath(start, target, halfSize)


func RebuildPath(start: Vector2, target: Vector2, halfSize: int) -> PackedVector2Array:
	return FindPath(start, target, halfSize)


func BuildPaths(
	unitStarts: PackedVector2Array,
	target: Vector2,
	halfSize: int,
) -> Array[PackedVector2Array]:
	if unitStarts.is_empty():
		return []

	var paths: Array[PackedVector2Array] = []
	paths.resize(unitStarts.size())

	var targetComponent: int = GetComponentId(target, halfSize)
	if targetComponent < 0:
		for index: int in range(unitStarts.size()):
			paths[index] = PackedVector2Array()

		return paths

	for unitStart: Vector2 in unitStarts:
		if GetComponentId(unitStart, halfSize) == targetComponent:
			continue

		# BuildPaths()는 같은 Component로 묶인 유닛만 받는 것을 전제로 한다.
		for index: int in range(unitStarts.size()):
			paths[index] = PackedVector2Array()

		return paths

	# 1. 유닛들의 평균 위치 계산
	var center: Vector2 = Vector2.ZERO
	for unitStart: Vector2 in unitStarts:
		center += unitStart
	center /= float(unitStarts.size())

	# 2. 그룹 반경 계산
	var groupRadiusSquared: float = 0.0
	for unitStart: Vector2 in unitStarts:
		var offset: Vector2 = unitStart - center
		groupRadiusSquared = maxf(groupRadiusSquared, offset.length_squared())

	# 3. 목적지가 그룹 범위 밖에 있는지 판단
	var targetDistanceSquared: float = center.distance_squared_to(target)
	var isTargetOutsideGroup: bool = targetDistanceSquared > groupRadiusSquared

	# 4. 현재 그룹이 충분히 촘촘하게 모여 있는지 판단
	# 유닛들의 총 점유 면적을 같은 면적의 원으로 환산한 반경을 기준으로 사용한다.
	var unitDiameter: float = float(halfSize * 2)
	var compactRadiusSquared: float = float(unitStarts.size()) * unitDiameter * unitDiameter / PI
	compactRadiusSquared *= (formationCompactRadiusScale * formationCompactRadiusScale)
	var isCompactGroup: bool = groupRadiusSquared <= compactRadiusSquared

	# 5. 목적지가 그룹 밖에 있고, 현재 그룹이 촘촘할 때만 진형 유지
	var shouldPreserveFormation: bool = (isTargetOutsideGroup and isCompactGroup)

	var phaseStart: int = 0

	# 진형 유지 조건을 만족하면 그룹 중심에서 목적지까지 개별 유닛 크기로 공용 경로를 한 번 탐색한다.
	if shouldPreserveFormation:
		var formationPaths: Array[PackedVector2Array] = _BuildFormationPaths(
			unitStarts,
			center,
			target,
			halfSize,
		)
		if not formationPaths.is_empty():
			return formationPaths
	# Formation을 사용할 수 없으면 기존 방식으로 그대로 FallBack한다.

	# 6. 평균 위치를 target과 같은 Component의 실제 합류 지점으로 보정
	phaseStart = _ProfileBegin()
	var joinPoint: Vector2 = GetNearestReachablePoint(center, halfSize, target)
	_ProfileGroupJoinPoint(phaseStart)

	# 7. 합류 지점 → 목적지 공통 Path를 한 번만 생성
	phaseStart = _ProfileBegin()
	var sharedPath: PackedVector2Array = PackedVector2Array()
	if joinPoint.distance_squared_to(target) <= Math.EPSILON:
		sharedPath.append(target)
	else:
		sharedPath = FindPath(joinPoint, target, halfSize)
	_ProfileGroupSharedPath(phaseStart)

	if not _PathEndsAtPoint(sharedPath, target):
		for index: int in range(unitStarts.size()):
			paths[index] = PackedVector2Array()

		return paths

	# 각 유닛의 개별 합류 경로 구성
	phaseStart = _ProfileBegin()
	for index: int in range(unitStarts.size()):
		var unitPath: PackedVector2Array = _BuildPathToSharedPath(
			unitStarts[index],
			joinPoint,
			sharedPath,
			halfSize,
		)
		if not unitPath.is_empty() and not _PathEndsAtPoint(unitPath, target):
			unitPath = PackedVector2Array()

		paths[index] = unitPath
	_ProfileGroupUnitPaths(phaseStart)

	return paths


func WorldToCell(position: Vector2) -> Vector2i:
	return _WorldToCellFloor(position)


func CellToWorld(cell: Vector2i) -> Vector2:
	return (
		_worldRect.position
		+ Vector2((float(cell.x) + 0.5) * _navCellSize, (float(cell.y) + 0.5) * _navCellSize)
	)


func IsCellInGrid(cell: Vector2i) -> bool:
	return Grid.IsCellInGrid(cell, _gridWidth, _gridHeight)

#endregion


#region Initialization

func _LoadNavigationData() -> void:
	_navigationReady = false

	if navigationData == null:
		push_error("NavigationData가 지정되지 않았습니다.")
		return

	_ApplyNavigationData()

	if not _ValidateNavigationData():
		return

	_InitNavigationRuntimeData()

	_navigationReady = true


func _ApplyNavigationData() -> void:
	_navCellSize = float(navigationData.cellSize)
	_gridWidth = navigationData.gridSize.x
	_gridHeight = navigationData.gridSize.y
	_worldRect = navigationData.GetWorldRect()

	_blocked = navigationData.blocked
	_prefixSum = navigationData.prefixSum
	_portalMap = navigationData.portalMap
	_regionMap = navigationData.regionMap

	_regions = navigationData.regions


func _ValidateNavigationData() -> bool:
	if _navCellSize <= 0.0:
		push_error("NavigationData의 cell_size가 잘못되었습니다.")
		return false

	if _gridWidth <= 0 or _gridHeight <= 0:
		push_error("NavigationData의 gridSize가 잘못되었습니다.")
		return false

	var expectedBlocked: int = _gridWidth * _gridHeight
	var expectedPrefix: int = (_gridWidth + 1) * (_gridHeight + 1)

	if _blocked.size() != expectedBlocked:
		push_error("NavigationData의 blocked 크기가 잘못되었습니다.")
		return false

	if _prefixSum.size() != expectedPrefix:
		push_error("NavigationData의 prefix_sum 크기가 잘못되었습니다.")
		return false

	if _portalMap.size() != expectedBlocked:
		push_error("NavigationData의 portalMap 크기가 잘못되었습니다.")
		return false

	if _regionMap.size() != expectedBlocked:
		push_error("NavigationData의 regionMap 크기가 잘못되었습니다.")
		return false

	for footprint: NavigationFootprintData in navigationData.footprints:
		if footprint == null or footprint.halfSize <= 0:
			continue

		if footprint.navigationMap == null:
			push_error(
				"NavigationFootprintData에 NavigationMap이 없습니다. halfSize=%d" % footprint.halfSize
			)
			return false

		var navigationMap: NavigationFootprintMapData = footprint.navigationMap
		if navigationMap.placeableMap.size() != expectedBlocked:
			push_error("Footprint placeableMap 크기가 잘못되었습니다. halfSize=%d" % footprint.halfSize)
			return false
		if navigationMap.componentMap.size() != expectedBlocked:
			push_error("Footprint componentMap 크기가 잘못되었습니다. halfSize=%d" % footprint.halfSize)
			return false
		if navigationMap.pathRegionMap.size() != expectedBlocked:
			push_error("Footprint pathRegionMap 크기가 잘못되었습니다. halfSize=%d" % footprint.halfSize)
			return false
		if navigationMap.walkMask.size() != expectedBlocked:
			push_error("Footprint walkMask 크기가 잘못되었습니다. halfSize=%d" % footprint.halfSize)
			return false
		if navigationMap.regionWalkMask.size() != expectedBlocked:
			push_error("Footprint regionWalkMask 크기가 잘못되었습니다. halfSize=%d" % footprint.halfSize)
			return false

	return true


func _InitNavigationRuntimeData() -> void:
	_regionQuery = NavigationRegionQuery.new(navigationData)

	_footprintDataByHalfSize.clear()
	_anchorGraphByHalfSize.clear()

	for footprint: NavigationFootprintData in navigationData.footprints:
		if footprint == null or footprint.halfSize <= 0:
			continue

		if _footprintDataByHalfSize.has(footprint.halfSize):
			push_warning("중복된 NavigationFootprintData halfSize: %d" % footprint.halfSize)

		_footprintDataByHalfSize[footprint.halfSize] = footprint
		_anchorGraphByHalfSize[footprint.halfSize] = NavigationAnchorGraph.Build(footprint)

	_anchorConnectionCache = NavigationAnchorConnectionCache.new()
	_regionAnchorTopologyCache.clear()

	_gridPathfinder = NavigationGridPathfinder.new(
		_gridWidth,
		_gridHeight,
		_navCellSize,
		_worldRect,
	)
	_hierarchicalPathfinder = NavigationHierarchicalPathfinder.new()

	_staticQuery = NavigationStaticQuery.new(navigationData)

#endregion


#region Group Path

func _BuildFormationPaths(
	unitStarts: PackedVector2Array,
	center: Vector2,
	target: Vector2,
	halfSize: int,
) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []

	var phaseStart: int = _ProfileBegin()
	var sharedPath: PackedVector2Array = FindPath(center, target, halfSize)
	_ProfileGroupSharedPath(phaseStart)

	if not _PathEndsAtPoint(sharedPath, target):
		return result

	result.resize(unitStarts.size())

	phaseStart = _ProfileBegin()

	for index: int in range(unitStarts.size()):
		var offset: Vector2 = unitStarts[index] - center
		result[index] = _BuildOffsetPath(sharedPath, offset)

	_ProfileGroupUnitPaths(phaseStart)

	return result


func _BuildOffsetPath(sharedPath: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	result.resize(sharedPath.size())
	for index: int in range(sharedPath.size()):
		result[index] = sharedPath[index] + offset

	return result


func _BuildPathToSharedPath(
	unitStart: Vector2,
	joinPoint: Vector2,
	sharedPath: PackedVector2Array,
	halfSize: int,
) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()

	if sharedPath.is_empty():
		return result

	var sharedPathStartIndex: int = 0
	if sharedPath[0].distance_squared_to(joinPoint) <= Math.EPSILON:
		sharedPathStartIndex = 1

	# 1. 목적지 쪽부터 같은 방향으로 이어진 Raw Segment들을 하나의 직선 구간으로 묶어서 합류 가능 여부를 검사한다.
	var routeSize: int = 1 + sharedPath.size() - sharedPathStartIndex
	var runEndIndex: int = routeSize - 1
	while runEndIndex > 0:
		var runStartIndex: int = runEndIndex - 1

		var runEndPoint: Vector2 = _GetSharedRoutePoint(
			sharedPath,
			joinPoint,
			sharedPathStartIndex,
			runEndIndex,
		)
		var runStartPoint: Vector2 = _GetSharedRoutePoint(
			sharedPath,
			joinPoint,
			sharedPathStartIndex,
			runStartIndex,
		)
		var runDirection: Vector2 = runEndPoint - runStartPoint

		while runStartIndex > 0:
			var previousPoint: Vector2 = _GetSharedRoutePoint(
				sharedPath,
				joinPoint,
				sharedPathStartIndex,
				runStartIndex - 1,
			)
			var currentPoint: Vector2 = _GetSharedRoutePoint(
				sharedPath,
				joinPoint,
				sharedPathStartIndex,
				runStartIndex,
			)
			var previousDirection: Vector2 = currentPoint - previousPoint

			if (
				absf(previousDirection.cross(runDirection)) > Math.EPSILON
				or previousDirection.dot(runDirection) <= 0.0
			):
				break

			runStartIndex -= 1

		var runStart: Vector2 = _GetSharedRoutePoint(
			sharedPath,
			joinPoint,
			sharedPathStartIndex,
			runStartIndex,
		)
		var runEnd: Vector2 = _GetSharedRoutePoint(
			sharedPath,
			joinPoint,
			sharedPathStartIndex,
			runEndIndex,
		)
		var joinCandidate: Vector2 = Geometry2D.get_closest_point_to_segment(
			unitStart,
			runStart,
			runEnd,
		)

		if _benchmarkMetrics != null:
			_benchmarkMetrics.groupJoinSegmentAttempts += 1

		if SegmentClear(unitStart, joinCandidate, halfSize):
			if _benchmarkMetrics != null:
				_benchmarkMetrics.groupJoinSegmentSuccesses += 1

			if unitStart.distance_squared_to(joinCandidate) > Math.EPSILON:
				_AppendUniquePoint(result, joinCandidate)

			# joinCandidate가 이 직선 구간의 어느 Raw Segment에 있는지 찾는다.
			# 그 지점 이후의 Raw waypoint는 하나도 생략하지 않고 그대로 넣는다.
			var runDelta: Vector2 = runEnd - runStart
			var candidateProgress: float = (joinCandidate - runStart).dot(runDelta)

			var resumeIndex: int = runEndIndex

			for index: int in range(runStartIndex + 1, runEndIndex + 1):
				var routePoint: Vector2 = _GetSharedRoutePoint(
					sharedPath,
					joinPoint,
					sharedPathStartIndex,
					index,
				)

				var pointProgress: float = (routePoint - runStart).dot(runDelta)
				if pointProgress + Math.EPSILON < candidateProgress:
					continue

				resumeIndex = index
				break

			for index: int in range(resumeIndex, routeSize):
				_AppendUniquePoint(
					result,
					_GetSharedRoutePoint(sharedPath, joinPoint, sharedPathStartIndex, index),
				)

			return result

		# 이 직선 구간에는 합류할 수 없었으므로 바로 앞쪽 직선 구간을 검사한다.
		runEndIndex = runStartIndex

	# 2. 선분 합류가 안 되면 목적지 쪽 waypoint부터 역순으로 확인
	for index: int in range(routeSize - 1, -1, -1):
		var routePoint: Vector2 = _GetSharedRoutePoint(
			sharedPath,
			joinPoint,
			sharedPathStartIndex,
			index,
		)

		if _benchmarkMetrics != null:
			_benchmarkMetrics.groupJoinWaypointAttempts += 1

		if not SegmentClear(unitStart, routePoint, halfSize):
			continue

		if _benchmarkMetrics != null:
			_benchmarkMetrics.groupJoinWaypointSuccesses += 1

		for pathIndex: int in range(index, routeSize):
			_AppendUniquePoint(
				result,
				_GetSharedRoutePoint(sharedPath, joinPoint, sharedPathStartIndex, pathIndex),
			)

		return result

	# 3. 전부 실패한 유닛만 joinPoint까지 A*
	if _benchmarkMetrics != null:
		_benchmarkMetrics.groupJoinFallbackCalls += 1
	var localPath: PackedVector2Array = FindPath(unitStart, joinPoint, halfSize)
	if localPath.is_empty():
		# 이미 joinPoint에 있는 경우 FindPath()가 빈 배열을 반환하는 것은 정상.
		if unitStart.distance_squared_to(joinPoint) > Math.EPSILON:
			return result
	else:
		if _benchmarkMetrics != null:
			_benchmarkMetrics.groupJoinFallbackSuccesses += 1
		for point: Vector2 in localPath:
			_AppendUniquePoint(result, point)

	# 4. joinPoint 이후 공통 Raw Path 연결
	for point: Vector2 in sharedPath:
		_AppendUniquePoint(result, point)

	return result


func _GetSharedRoutePoint(
	sharedPath: PackedVector2Array,
	joinPoint: Vector2,
	sharedPathStartIndex: int,
	routeIndex: int,
) -> Vector2:
	if routeIndex == 0:
		return joinPoint

	return sharedPath[sharedPathStartIndex + routeIndex - 1]

#endregion


#region Footprint Data

func _GetFootprintMap(halfSize: int) -> NavigationFootprintMapData:
	var footprintData: NavigationFootprintData = _GetFootprintData(halfSize)
	if footprintData == null:
		return null

	return footprintData.navigationMap


func _GetFootprintData(halfSize: int) -> NavigationFootprintData:
	if not _footprintDataByHalfSize.has(halfSize):
		return null

	return _footprintDataByHalfSize[halfSize]

#endregion


#region Nearest Cell Search

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
			if distance < bestDistance - Math.EPSILON:
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


func _GetNearestPathCell(position: Vector2, halfSize: int, pathOffset: Vector2) -> Vector2i:
	var navigationMap: NavigationFootprintMapData = _GetFootprintMap(halfSize)

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
			if not _staticQuery.SegmentClear(position, center, halfSize, _benchmarkMetrics):
				continue

			var distance: float = center.distance_squared_to(position)
			if distance < bestDistance - Math.EPSILON:
				bestDistance = distance
				best = cell
			elif absf(distance - bestDistance) <= Math.EPSILON:
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

	return outerMinDistance * outerMinDistance > bestDistance + Math.EPSILON

#endregion


#region Grid Pathfinding

func _FindFallbackGridPath(start: Vector2, target: Vector2, halfSize: int) -> PackedVector2Array:
	var startUsec: int = 0
	if _benchmarkMetrics != null:
		startUsec = Time.get_ticks_usec()
	var path: PackedVector2Array = _FindCompleteGridPath(start, target, halfSize)
	if _benchmarkMetrics != null:
		_benchmarkMetrics.fallbackGridUsec += (Time.get_ticks_usec() - startUsec)

	return path


func _FindCompleteGridPath(start: Vector2, target: Vector2, halfSize: int) -> PackedVector2Array:
	var path: PackedVector2Array = _FindGridPath(start, target, halfSize)
	if not _PathEndsAtPoint(path, target):
		return PackedVector2Array()

	return path


func _FindGridPath(start: Vector2, target: Vector2, halfSize: int) -> PackedVector2Array:
	return _FindGridPathInternal(start, target, halfSize, -1)


func _FindPathInsideRegion(
	start: Vector2,
	target: Vector2,
	halfSize: int,
	regionId: int,
) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()

	if _IsSegmentClearInsideRegion(start, target, halfSize, regionId):
		result.append(target)
		return result

	result = _FindLocalPath(start, target, halfSize, regionId)
	if not _PathEndsAtPoint(result, target):
		return PackedVector2Array()

	return result


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
	target: Vector2,
	path: PackedVector2Array,
	halfSize: int,
	regionId: int,
) -> PackedVector2Array:
	if path.is_empty():
		return PackedVector2Array()

	var result: PackedVector2Array = path
	var last: Vector2 = result[result.size() - 1]
	if last.distance_squared_to(target) <= Math.EPSILON:
		return result

	if not _IsSegmentClearInsideRegion(last, target, halfSize, regionId):
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
	if not _navigationReady:
		return PackedVector2Array()

	if _benchmarkMetrics != null:
		_benchmarkMetrics.gridSearchCalls += 1

	var navigationMap: NavigationFootprintMapData = _GetFootprintMap(halfSize)

	var pathOffset: Vector2 = _PathLatticeOffset(halfSize)

	var startCell: Vector2i = _GetNearestPathCell(start, halfSize, pathOffset)
	var targetCell: Vector2i = _GetNearestPathCell(target, halfSize, pathOffset)
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
		_benchmarkMetrics,
	)
	if path.is_empty():
		return path

	var last: Vector2 = path[path.size() - 1]
	var finalPoint: Vector2 = _staticQuery.FurthestClearPoint(
		last,
		target,
		halfSize,
		_benchmarkMetrics,
	)
	if last.distance_squared_to(finalPoint) > Math.EPSILON:
		path.append(finalPoint)

	return path

#endregion


#region Region / Portal

func _IsSegmentClearInsideRegion(
	start: Vector2,
	end: Vector2,
	halfSize: int,
	regionId: int,
) -> bool:
	return (
		SegmentClear(start, end, halfSize)
		and _regionQuery.IsSegmentInsideRegion(start, end, regionId)
	)

#endregion


#region Anchor Graph / Topology Cache

func _GetAnchorGraph(halfSize: int) -> NavigationAnchorTypes.GraphData:
	if not _anchorGraphByHalfSize.has(halfSize):
		return null

	return _anchorGraphByHalfSize[halfSize]


func _GetRegionAnchorTopology(
	halfSize: int,
	regionId: int,
	footprint: NavigationFootprintData,
) -> NavigationAnchorTypes.RegionTopology:
	var cacheKey: Vector2i = Vector2i(halfSize, regionId)
	if _regionAnchorTopologyCache.has(cacheKey):
		return _regionAnchorTopologyCache[cacheKey]

	var region: NavigationRegionData = null
	if 0 <= regionId and regionId < _regions.size():
		region = _regions[regionId]

	var topology: NavigationAnchorTypes.RegionTopology = NavigationAnchorTopology.Build(
		regionId,
		region,
		footprint,
	)

	_regionAnchorTopologyCache[cacheKey] = topology

	return topology

#endregion


#region Anchor Connection

func _MakeRegionAnchorConnectionsForRegions(
	position: Vector2,
	halfSize: int,
	regionIds: Array[int],
	footprint: NavigationFootprintData,
) -> Array[NavigationAnchorTypes.Connection]:
	if regionIds.size() == 1:
		return _MakeRegionAnchorConnections(position, halfSize, regionIds[0], footprint)

	var result: Array[NavigationAnchorTypes.Connection] = []

	if regionIds.is_empty():
		return result

	_bestAnchorConnectionByNode.clear()
	for regionId: int in regionIds:
		var connections: Array[NavigationAnchorTypes.Connection] = _MakeRegionAnchorConnections(
			position,
			halfSize,
			regionId,
			footprint,
		)
		for connection: NavigationAnchorTypes.Connection in connections:
			if not _bestAnchorConnectionByNode.has(connection.nodeKey):
				_bestAnchorConnectionByNode[connection.nodeKey] = connection
				continue

			var previous: NavigationAnchorTypes.Connection = (
				_bestAnchorConnectionByNode[connection.nodeKey]
			)
			if connection.cost < previous.cost - Math.EPSILON:
				_bestAnchorConnectionByNode[connection.nodeKey] = connection

	for nodeKey: Vector2i in _bestAnchorConnectionByNode:
		result.append(_bestAnchorConnectionByNode[nodeKey])

	return result


func _MakeRegionAnchorConnections(
	position: Vector2,
	halfSize: int,
	regionId: int,
	footprint: NavigationFootprintData,
) -> Array[NavigationAnchorTypes.Connection]:
	var cacheKey: Vector4 = Vector4(position.x, position.y, float(halfSize), float(regionId))
	if _anchorConnectionCache.Has(cacheKey):
		if _benchmarkMetrics != null:
			_benchmarkMetrics.anchorCacheHits += 1
		return _anchorConnectionCache.Get(cacheKey)
	if _benchmarkMetrics != null:
		_benchmarkMetrics.anchorCacheMisses += 1

	var connections: Array[NavigationAnchorTypes.Connection] = _BuildRegionAnchorConnections(
		position,
		halfSize,
		regionId,
		footprint,
	)
	_anchorConnectionCache.Set(cacheKey, connections, anchorConnectionCacheCapacity)

	return connections


func _BuildRegionAnchorConnections(
	position: Vector2,
	halfSize: int,
	regionId: int,
	footprint: NavigationFootprintData,
) -> Array[NavigationAnchorTypes.Connection]:
	var result: Array[NavigationAnchorTypes.Connection] = []

	_reachableAnchorComponents.clear()
	_addedAnchorNodes.clear()
	_unreachableAnchorComponents.clear()

	var topology: NavigationAnchorTypes.RegionTopology = _GetRegionAnchorTopology(
		halfSize,
		regionId,
		footprint,
	)
	var nodes: Array[Vector2i] = topology.nodes
	if nodes.is_empty():
		return result

	var componentByNode: Dictionary[Vector2i, int] = topology.componentByNode

	var directCheckStartUsec: int = 0
	if _benchmarkMetrics != null:
		directCheckStartUsec = Time.get_ticks_usec()

	# 1. 직선 연결 가능한 Anchor는 즉시 추가
	for nodeKey: Vector2i in nodes:
		if _benchmarkMetrics != null:
			_benchmarkMetrics.anchorDirectCheckCount += 1

		var anchor: Vector2 = NavigationAnchorGraph.GetAnchorPosition(footprint, nodeKey)
		if not _IsSegmentClearInsideRegion(position, anchor, halfSize, regionId):
			continue

		if _benchmarkMetrics != null:
			_benchmarkMetrics.anchorDirectSuccessCount += 1

		var path: PackedVector2Array = PackedVector2Array()
		path.append(anchor)

		result.append(_CreateAnchorConnection(nodeKey, path, position.distance_to(anchor)))
		_addedAnchorNodes[nodeKey] = true

		var componentId: int = int(componentByNode[nodeKey])
		_reachableAnchorComponents[componentId] = true

	if _benchmarkMetrics != null:
		_benchmarkMetrics.anchorDirectCheckUsec += (Time.get_ticks_usec() - directCheckStartUsec)

	# 2. 아직 reachability가 확인되지 않은 component마다 가장 가까운 Anchor 하나만 probe
	NavigationAnchorConnectionPlanner.FillProbeByComponent(
		_probeAnchorByComponent,
		_probeDistanceByComponent,
		position,
		nodes,
		componentByNode,
		_addedAnchorNodes,
		_reachableAnchorComponents,
		footprint,
	)

	var probeStartUsec: int = 0
	if _benchmarkMetrics != null:
		probeStartUsec = Time.get_ticks_usec()

	for componentId: int in _probeAnchorByComponent:
		if _benchmarkMetrics != null:
			_benchmarkMetrics.anchorProbeCount += 1

		var nodeKey: Vector2i = _probeAnchorByComponent[componentId]
		var anchor: Vector2 = NavigationAnchorGraph.GetAnchorPosition(footprint, nodeKey)

		var path: PackedVector2Array = _FindLocalPath(position, anchor, halfSize, regionId)
		if not _EnsurePathEndsAtAnchor(position, path, anchor, halfSize, regionId):
			# 같은 baked component의 다른 Anchor도 도달 불가능하므로 전부 생략 가능.
			_unreachableAnchorComponents[componentId] = true
			continue

		if _benchmarkMetrics != null:
			_benchmarkMetrics.anchorProbeSuccessCount += 1

		_reachableAnchorComponents[componentId] = true
		_addedAnchorNodes[nodeKey] = true

		result.append(_CreateAnchorConnection(nodeKey, path, _GetWaypointPathCost(position, path)))

	if _benchmarkMetrics != null:
		_benchmarkMetrics.anchorProbeUsec += (Time.get_ticks_usec() - probeStartUsec)

	# 3. 남은 Anchor를 Portal별로 묶어서 한 번의 A*로 계산.
	NavigationAnchorConnectionPlanner.FillRemainingByPortal(
		_remainingAnchorNodesByPortal,
		nodes,
		componentByNode,
		_addedAnchorNodes,
		_reachableAnchorComponents,
		_unreachableAnchorComponents,
	)

	for portalId: int in _remainingAnchorNodesByPortal:
		var portalNodes: Array = _remainingAnchorNodesByPortal[portalId]
		if portalNodes.is_empty():
			continue

		var batchStartUsec: int = 0
		if _benchmarkMetrics != null:
			batchStartUsec = Time.get_ticks_usec()
		_FillLocalPathsToPortalAnchors(position, portalNodes, halfSize, regionId, footprint)
		if _benchmarkMetrics != null:
			_benchmarkMetrics.anchorPortalBatchUsec += (Time.get_ticks_usec() - batchStartUsec)

		for nodeKey: Vector2i in portalNodes:
			var path: PackedVector2Array
			if _portalAnchorPathsByNode.has(nodeKey):
				path = _portalAnchorPathsByNode[nodeKey]
			else:
				var fallbackStartUsec: int = 0
				if _benchmarkMetrics != null:
					fallbackStartUsec = Time.get_ticks_usec()
					_benchmarkMetrics.anchorIndividualFallbackCount += 1

				var anchor: Vector2 = NavigationAnchorGraph.GetAnchorPosition(footprint, nodeKey)
				path = _FindLocalPath(position, anchor, halfSize, regionId)
				var fallbackSuccess: bool = _EnsurePathEndsAtAnchor(
					position,
					path,
					anchor,
					halfSize,
					regionId,
				)

				if _benchmarkMetrics != null:
					_benchmarkMetrics.anchorIndividualFallbackUsec += (
						Time.get_ticks_usec() - fallbackStartUsec
					)

				if not fallbackSuccess:
					continue

				if _benchmarkMetrics != null:
					_benchmarkMetrics.anchorIndividualFallbackSuccessCount += 1

			result.append(
				_CreateAnchorConnection(nodeKey, path, _GetWaypointPathCost(position, path))
			)

	return result


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

	if last.distance_squared_to(anchor) <= Math.EPSILON:
		return true

	if not _IsSegmentClearInsideRegion(last, anchor, halfSize, regionId):
		return false

	path.append(anchor)
	return true


func _CreateAnchorConnection(
	nodeKey: Vector2i,
	path: PackedVector2Array,
	cost: float,
) -> NavigationAnchorTypes.Connection:
	var connection: NavigationAnchorTypes.Connection = NavigationAnchorTypes.Connection.new()
	connection.nodeKey = nodeKey
	connection.path = path
	connection.cost = cost

	return connection

#endregion


#region Portal Anchor

func _FillLocalPathsToPortalAnchors(
	start: Vector2,
	nodeKeys: Array,
	halfSize: int,
	regionId: int,
	footprint: NavigationFootprintData,
) -> void:
	_ResetPortalAnchorSearchScratch()

	if nodeKeys.is_empty():
		return

	var benchmarkStartUsec: int = 0
	if _benchmarkMetrics != null:
		benchmarkStartUsec = Time.get_ticks_usec()
		_benchmarkMetrics.anchorPortalBatchSearchCalls += 1

	var navigationMap: NavigationFootprintMapData = _GetFootprintMap(halfSize)

	var pathOffset: Vector2 = _PathLatticeOffset(halfSize)
	var startCell: Vector2i = _GetNearestPathCell(start, halfSize, pathOffset)
	if startCell.x < 0:
		return

	var startIndex: int = Grid.CellToIndex(startCell, _gridWidth)
	var startComponent: int = navigationMap.componentMap[startIndex]
	if startComponent < 0:
		return

	for nodeKey: Vector2i in nodeKeys:
		var anchor: Vector2 = NavigationAnchorGraph.GetAnchorPosition(footprint, nodeKey)
		var targetCell: Vector2i = _GetNearestPathCell(anchor, halfSize, pathOffset)
		if targetCell.x < 0:
			continue

		var targetIndex: int = Grid.CellToIndex(targetCell, _gridWidth)
		if navigationMap.componentMap[targetIndex] != startComponent:
			continue

		if not _portalNodesByTargetIndex.has(targetIndex):
			_portalNodesByTargetIndex[targetIndex] = []

		var nodes: Array = _portalNodesByTargetIndex[targetIndex]

		# Reset 단계에서 이전 호출의 Array는 모두 비워져 있으므로 empty이면 이번 호출에서 처음 등장한 targetIndex다.
		if nodes.is_empty():
			_portalActiveTargetIndices.append(targetIndex)
			_portalTargetCells.append(targetCell)

		nodes.append(nodeKey)

	if _portalTargetCells.is_empty():
		return

	_gridPathfinder.FillPathsToTargets(
		_portalGridPathsByTargetIndex,
		startCell,
		_portalTargetCells,
		pathOffset,
		navigationMap,
		regionId,
		localSearchMarginCells,
	)

	if _benchmarkMetrics != null:
		_benchmarkMetrics.anchorPortalBatchExpanded += _gridPathfinder.lastExpandedCount
		_benchmarkMetrics.anchorPortalBatchRelaxed += _gridPathfinder.lastRelaxedCount

	for targetIndex: int in _portalGridPathsByTargetIndex:
		var basePath: PackedVector2Array = _portalGridPathsByTargetIndex[targetIndex]

		var nodeValues: Array = _portalNodesByTargetIndex[targetIndex]

		for nodeKey: Vector2i in nodeValues:
			var path: PackedVector2Array = basePath.duplicate()

			var anchor: Vector2 = NavigationAnchorGraph.GetAnchorPosition(footprint, nodeKey)

			if _EnsurePathEndsAtAnchor(start, path, anchor, halfSize, regionId):
				_portalAnchorPathsByNode[nodeKey] = path

	if _benchmarkMetrics != null:
		var elapsedUsec: int = (Time.get_ticks_usec() - benchmarkStartUsec)
		if elapsedUsec > _benchmarkMetrics.anchorBatchMaxUsec:
			_benchmarkMetrics.anchorBatchMaxUsec = elapsedUsec
			_benchmarkMetrics.anchorBatchMaxExpanded = _gridPathfinder.lastExpandedCount
			_benchmarkMetrics.anchorBatchMaxRelaxed = _gridPathfinder.lastRelaxedCount
			_benchmarkMetrics.anchorBatchMaxTargetCount = _portalTargetCells.size()
			_benchmarkMetrics.anchorBatchMaxSearchArea = _gridPathfinder.lastSearchArea

#endregion


#region Coordinates

func _PathLatticeOffset(halfSize: int) -> Vector2:
	var offset: float = _LatticeAxisOffset(float(halfSize))
	return Vector2(offset, offset)


func _LatticeAxisOffset(halfExtent: float) -> float:
	var offset: float = fposmod(maxf(halfExtent, 0.0), _navCellSize)
	if offset <= Math.EPSILON or _navCellSize - offset <= Math.EPSILON:
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


func _WorldToCellFloor(position: Vector2) -> Vector2i:
	var local: Vector2 = position - _worldRect.position
	return Vector2i(floori(local.x / _navCellSize), floori(local.y / _navCellSize))

#endregion


#region Path Utility

func _PathEndsAtPoint(path: PackedVector2Array, point: Vector2) -> bool:
	if path.is_empty():
		return false

	return path[path.size() - 1].distance_squared_to(point) <= Math.EPSILON


func _AppendUniquePoint(path: PackedVector2Array, point: Vector2) -> void:
	if not path.is_empty() and path[path.size() - 1].distance_squared_to(point) <= Math.EPSILON:
		return

	path.append(point)


func _GetWaypointPathCost(start: Vector2, path: PackedVector2Array) -> float:
	var cost: float = 0.0
	var current: Vector2 = start
	for point: Vector2 in path:
		cost += current.distance_to(point)
		current = point

	return cost

#endregion


#region Profiling

func SetProfileMetrics(metrics: NavigationProfileMetrics) -> void:
	_benchmarkMetrics = metrics


func ClearProfileMetrics() -> void:
	_benchmarkMetrics = null


func ClearBenchmarkRequestCache() -> void:
	# 같은 Start/Target 반복 측정에서 exact-position Anchor cache가 실제 path request 비용을 가리지 않도록 요청 단위 cache만 비운다.
	# Footprint map / baked graph / topology는 유지한다.
	if _anchorConnectionCache != null:
		_anchorConnectionCache.Clear()


func _ProfileBegin() -> int:
	if _benchmarkMetrics == null:
		return 0

	return Time.get_ticks_usec()


func _ProfileGroupSharedPath(startUsec: int) -> void:
	if _benchmarkMetrics == null:
		return

	_benchmarkMetrics.groupSharedPathUsec += (Time.get_ticks_usec() - startUsec)


func _ProfileGroupUnitPaths(startUsec: int) -> void:
	if _benchmarkMetrics == null:
		return

	_benchmarkMetrics.groupUnitPathsUsec += (Time.get_ticks_usec() - startUsec)


func _ProfileGroupJoinPoint(startUsec: int) -> void:
	if _benchmarkMetrics == null:
		return

	_benchmarkMetrics.groupJoinPointUsec += (Time.get_ticks_usec() - startUsec)

#endregion


func _ResetPortalAnchorSearchScratch() -> void:
	_portalAnchorPathsByNode.clear()
	_portalGridPathsByTargetIndex.clear()

	for targetIndex: int in _portalActiveTargetIndices:
		var nodes: Array = _portalNodesByTargetIndex[targetIndex]
		nodes.clear()

	_portalActiveTargetIndices.clear()
	_portalTargetCells.clear()
