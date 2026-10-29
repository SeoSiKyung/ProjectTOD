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

var _startRegionIds: Array[int] = []
var _targetRegionIds: Array[int] = []

var _footprintDataByHalfSize: Dictionary[int, NavigationFootprintData] = { }

var _anchorGraphByHalfSize: Dictionary[int, NavigationAnchorTypes.GraphData] = { }

var _anchorConnector: NavigationAnchorConnector

var _localPathfinder: NavigationLocalPathfinder

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
	return _localPathfinder.SegmentClear(start, end, halfSize, _benchmarkMetrics)


func GetNearestPlaceablePoint(
	position: Vector2,
	halfSize: int,
	referencePosition: Vector2,
) -> Vector2:
	return _localPathfinder.GetNearestPlaceablePoint(position, halfSize, referencePosition)


func GetComponentId(position: Vector2, halfSize: int) -> int:
	if not _navigationReady:
		return -1

	return _localPathfinder.GetComponentId(position, halfSize, _benchmarkMetrics)


func GetNearestReachablePoint(
	position: Vector2,
	halfSize: int,
	referencePosition: Vector2,
) -> Vector2:
	if not _navigationReady:
		return referencePosition

	return _localPathfinder.GetNearestReachablePoint(
		position,
		halfSize,
		referencePosition,
		_benchmarkMetrics,
	)


func FindPath(start: Vector2, target: Vector2, halfSize: int) -> PackedVector2Array:
	if not _navigationReady:
		return PackedVector2Array()

	if Math.IsSamePoint(start, target):
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

	phaseStart = _ProfileBegin()
	_regionQuery.FillRegionIds(_startRegionIds, start)
	_regionQuery.FillRegionIds(_targetRegionIds, target)
	if _benchmarkMetrics != null:
		_benchmarkMetrics.regionLookupUsec += Time.get_ticks_usec() - phaseStart
	if _startRegionIds.is_empty() or _targetRegionIds.is_empty():
		return _FindFallbackGridPath(start, target, halfSize)

	var bestPath: PackedVector2Array = PackedVector2Array()
	var bestCost: float = Math.BIG_NUMBER

	var isSingleSharedRegion: bool = (
		_startRegionIds.size() == 1 and _targetRegionIds.size() == 1
		and _startRegionIds[0] == _targetRegionIds[0]
	)

	phaseStart = _ProfileBegin()
	if isSingleSharedRegion:
		var localPath: PackedVector2Array = _localPathfinder.FindPathInsideRegion(
			start,
			target,
			halfSize,
			_startRegionIds[0],
			localSearchMarginCells,
			_benchmarkMetrics,
		)
		if not localPath.is_empty():
			if _benchmarkMetrics != null:
				_benchmarkMetrics.sameRegionPathUsec += Time.get_ticks_usec() - phaseStart
			return localPath
	else:
		# Portal 위의 시작/목표처럼 여러 Region에 연결되는 경우에는 양쪽이 공유하는 Region들의 Local Path를 후보로 비교한다.
		for startRegionId: int in _startRegionIds:
			if not _targetRegionIds.has(startRegionId):
				continue

			var localPath: PackedVector2Array = _localPathfinder.FindPathInsideRegion(
				start,
				target,
				halfSize,
				startRegionId,
				localSearchMarginCells,
				_benchmarkMetrics,
			)
			if localPath.is_empty():
				continue

			var localCost: float = _GetWaypointPathCost(start, localPath)
			if Math.IsLess(localCost, bestCost):
				bestCost = localCost
				bestPath = localPath

	if _benchmarkMetrics != null:
		_benchmarkMetrics.sameRegionPathUsec += Time.get_ticks_usec() - phaseStart
		phaseStart = Time.get_ticks_usec()
	var startConnections: Array[NavigationAnchorTypes.Connection] = _anchorConnector.BuildConnectionsForRegions(
		start,
		halfSize,
		_startRegionIds,
		footprintData,
		localSearchMarginCells,
		anchorConnectionCacheCapacity,
		_benchmarkMetrics,
	)
	if _benchmarkMetrics != null:
		_benchmarkMetrics.startAnchorConnectionUsec += (Time.get_ticks_usec() - phaseStart)

	if _benchmarkMetrics != null:
		phaseStart = Time.get_ticks_usec()
	var targetConnections: Array[NavigationAnchorTypes.Connection] = _anchorConnector.BuildConnectionsForRegions(
		target,
		halfSize,
		_targetRegionIds,
		footprintData,
		localSearchMarginCells,
		anchorConnectionCacheCapacity,
		_benchmarkMetrics,
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

			if graphPathFound and Math.IsLess(_hierarchicalPathfinder.lastPathCost, bestCost):
				phaseStart = _ProfileBegin()
				bestPath = _hierarchicalPathfinder.BuildPath(target)
				bestCost = _hierarchicalPathfinder.lastPathCost
				if _benchmarkMetrics != null:
					_benchmarkMetrics.pathAssemblyUsec += Time.get_ticks_usec() - phaseStart

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
	if Math.IsSamePoint(joinPoint, target):
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

	_gridPathfinder = NavigationGridPathfinder.new(
		_gridWidth,
		_gridHeight,
		_navCellSize,
		_worldRect,
	)

	_hierarchicalPathfinder = NavigationHierarchicalPathfinder.new()

	_staticQuery = NavigationStaticQuery.new(navigationData)

	_localPathfinder = NavigationLocalPathfinder.new(
		navigationData,
		_gridPathfinder,
		_staticQuery,
		_regionQuery,
	)

	_anchorConnector = NavigationAnchorConnector.new(
		navigationData,
		_gridPathfinder,
		_localPathfinder,
	)

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
	if Math.IsSamePoint(sharedPath[0], joinPoint):
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
				not Math.IsNearlyZero(previousDirection.cross(runDirection))
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

			if not Math.IsSamePoint(unitStart, joinCandidate):
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
				if Math.IsLess(pointProgress, candidateProgress):
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
		if not Math.IsSamePoint(unitStart, joinPoint):
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


func _GetFootprintData(halfSize: int) -> NavigationFootprintData:
	if not _footprintDataByHalfSize.has(halfSize):
		return null

	return _footprintDataByHalfSize[halfSize]


#region Grid Pathfinding

func _FindFallbackGridPath(start: Vector2, target: Vector2, halfSize: int) -> PackedVector2Array:
	var startUsec: int = 0
	if _benchmarkMetrics != null:
		startUsec = Time.get_ticks_usec()
	var path: PackedVector2Array = _localPathfinder.FindCompleteGridPath(
		start,
		target,
		halfSize,
		_benchmarkMetrics,
	)
	if _benchmarkMetrics != null:
		_benchmarkMetrics.fallbackGridUsec += (Time.get_ticks_usec() - startUsec)

	return path

#endregion


#region Anchor Graph

func _GetAnchorGraph(halfSize: int) -> NavigationAnchorTypes.GraphData:
	if not _anchorGraphByHalfSize.has(halfSize):
		return null

	return _anchorGraphByHalfSize[halfSize]

#endregion


#region Path Utility

func _PathEndsAtPoint(path: PackedVector2Array, point: Vector2) -> bool:
	if path.is_empty():
		return false

	return Math.IsSamePoint(path[path.size() - 1], point)


func _AppendUniquePoint(path: PackedVector2Array, point: Vector2) -> void:
	if not path.is_empty() and Math.IsSamePoint(path[path.size() - 1], point):
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

func GetProfileMetrics() -> NavigationProfileMetrics:
	return _benchmarkMetrics


func SetProfileMetrics(metrics: NavigationProfileMetrics) -> void:
	_benchmarkMetrics = metrics


func ClearProfileMetrics() -> void:
	_benchmarkMetrics = null


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


#region Benchmark

func ClearBenchmarkRequestCache() -> void:
	if _anchorConnector != null:
		_anchorConnector.ClearRequestCache()


func BuildRegionConnectionsForBenchmark(
	position: Vector2,
	halfSize: int,
	regionId: int,
	individual: bool,
	heuristicWeight: float = 1.0,
) -> Array[NavigationAnchorTypes.Connection]:
	var footprint: NavigationFootprintData = _GetFootprintData(halfSize)
	if footprint == null:
		return []

	return _anchorConnector.BuildRegionConnectionsForBenchmark(
		position,
		halfSize,
		regionId,
		footprint,
		localSearchMarginCells,
		anchorConnectionCacheCapacity,
		individual,
		heuristicWeight,
		_benchmarkMetrics,
	)


func ValidateRegionConnectionsForBenchmark(
	position: Vector2,
	halfSize: int,
	regionId: int,
	connections: Array[NavigationAnchorTypes.Connection],
) -> int:
	var footprint: NavigationFootprintData = _GetFootprintData(halfSize)
	if footprint == null:
		return maxi(1, connections.size())
	var invalidCount: int = 0
	for connection: NavigationAnchorTypes.Connection in connections:
		var anchor: Vector2 = NavigationAnchorGraph.GetAnchorPosition(footprint, connection.nodeKey)
		var valid: bool = _PathEndsAtPoint(connection.path, anchor)
		var previous: Vector2 = position
		for waypoint: Vector2 in connection.path:
			if not _localPathfinder.IsSegmentClearInsideRegion(
				previous,
				waypoint,
				halfSize,
				regionId,
				_benchmarkMetrics,
			):
				valid = false
				break
			previous = waypoint
		if not valid:
			invalidCount += 1
	return invalidCount

#endregion


#region Coordinates

func _WorldToCellFloor(position: Vector2) -> Vector2i:
	var local: Vector2 = position - _worldRect.position
	return Vector2i(floori(local.x / _navCellSize), floori(local.y / _navCellSize))

#endregion
