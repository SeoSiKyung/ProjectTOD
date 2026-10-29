class_name NavigationAnchorConnector
extends RefCounted

var _gridPathfinder: NavigationGridPathfinder
var _localPathfinder: NavigationLocalPathfinder

var _gridWidth: int = 0
var _regions: Array[NavigationRegionData] = []

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

var _useIndividualPortalPaths: bool = true
var _individualPortalHeuristicWeight: float = 1.5


func _init(
	navigationData: NavigationData,
	gridPathfinder: NavigationGridPathfinder,
	localPathfinder: NavigationLocalPathfinder,
) -> void:
	_gridPathfinder = gridPathfinder
	_localPathfinder = localPathfinder

	_gridWidth = navigationData.gridSize.x
	_regions = navigationData.regions

	_anchorConnectionCache = NavigationAnchorConnectionCache.new()


func ClearRequestCache() -> void:
	_anchorConnectionCache.Clear()


func BuildRegionConnectionsForBenchmark(
	position: Vector2,
	halfSize: int,
	regionId: int,
	footprint: NavigationFootprintData,
	localSearchMarginCells: int,
	cacheCapacity: int,
	individual: bool,
	heuristicWeight: float,
	metrics: NavigationProfileMetrics,
) -> Array[NavigationAnchorTypes.Connection]:
	var previousIndividual: bool = _useIndividualPortalPaths
	var previousWeight: float = _individualPortalHeuristicWeight

	_useIndividualPortalPaths = individual
	_individualPortalHeuristicWeight = heuristicWeight

	var result: Array[NavigationAnchorTypes.Connection] = (
		_BuildConnectionsForRegion(
			position,
			halfSize,
			regionId,
			footprint,
			localSearchMarginCells,
			cacheCapacity,
			metrics,
		)
	)

	_useIndividualPortalPaths = previousIndividual
	_individualPortalHeuristicWeight = previousWeight

	return result


#region Topology Cache

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

func BuildConnectionsForRegions(
	position: Vector2,
	halfSize: int,
	regionIds: Array[int],
	footprint: NavigationFootprintData,
	localSearchMarginCells: int,
	cacheCapacity: int,
	metrics: NavigationProfileMetrics = null,
) -> Array[NavigationAnchorTypes.Connection]:
	if regionIds.size() == 1:
		return _BuildConnectionsForRegion(
			position,
			halfSize,
			regionIds[0],
			footprint,
			localSearchMarginCells,
			cacheCapacity,
			metrics,
		)

	var result: Array[NavigationAnchorTypes.Connection] = []

	if regionIds.is_empty():
		return result

	_bestAnchorConnectionByNode.clear()
	for regionId: int in regionIds:
		var connections: Array[NavigationAnchorTypes.Connection] = _BuildConnectionsForRegion(
			position,
			halfSize,
			regionId,
			footprint,
			localSearchMarginCells,
			cacheCapacity,
			metrics,
		)
		for connection: NavigationAnchorTypes.Connection in connections:
			if not _bestAnchorConnectionByNode.has(connection.nodeKey):
				_bestAnchorConnectionByNode[connection.nodeKey] = connection
				continue

			var previous: NavigationAnchorTypes.Connection = (
				_bestAnchorConnectionByNode[connection.nodeKey]
			)
			if Math.IsLess(connection.cost, previous.cost):
				_bestAnchorConnectionByNode[connection.nodeKey] = connection

	for nodeKey: Vector2i in _bestAnchorConnectionByNode:
		result.append(_bestAnchorConnectionByNode[nodeKey])

	return result


func _BuildConnectionsForRegion(
	position: Vector2,
	halfSize: int,
	regionId: int,
	footprint: NavigationFootprintData,
	localSearchMarginCells: int,
	cacheCapacity: int,
	metrics: NavigationProfileMetrics,
) -> Array[NavigationAnchorTypes.Connection]:
	var cacheKey := Vector4(position.x, position.y, float(halfSize), float(regionId))

	if _anchorConnectionCache.Has(cacheKey):
		if metrics != null:
			metrics.anchorCacheHits += 1
		return _anchorConnectionCache.Get(cacheKey)

	if metrics != null:
		metrics.anchorCacheMisses += 1

	var connections := _BuildRegionAnchorConnections(
		position,
		halfSize,
		regionId,
		footprint,
		localSearchMarginCells,
		metrics,
	)

	_anchorConnectionCache.Set(cacheKey, connections, cacheCapacity)

	return connections


func _BuildRegionAnchorConnections(
	position: Vector2,
	halfSize: int,
	regionId: int,
	footprint: NavigationFootprintData,
	localSearchMarginCells: int,
	metrics: NavigationProfileMetrics,
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
	if metrics != null:
		directCheckStartUsec = Time.get_ticks_usec()

	# 1. 직선 연결 가능한 Anchor는 즉시 추가
	for nodeKey: Vector2i in nodes:
		if metrics != null:
			metrics.anchorDirectCheckCount += 1

		var anchor: Vector2 = NavigationAnchorGraph.GetAnchorPosition(footprint, nodeKey)
		if not _localPathfinder.IsSegmentClearInsideRegion(
			position,
			anchor,
			halfSize,
			regionId,
			metrics,
		):
			continue
		if metrics != null:
			metrics.anchorDirectSuccessCount += 1

		var path: PackedVector2Array = PackedVector2Array()
		path.append(anchor)

		result.append(_CreateAnchorConnection(nodeKey, path, position.distance_to(anchor)))
		_addedAnchorNodes[nodeKey] = true

		var componentId: int = int(componentByNode[nodeKey])
		_reachableAnchorComponents[componentId] = true

	if metrics != null:
		metrics.anchorDirectCheckUsec += (Time.get_ticks_usec() - directCheckStartUsec)

	# 2. 아직 reachability가 확인되지 않은 component마다 가장 가까운 Anchor 하나만 probe
	_FillProbeByComponent(
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
	if metrics != null:
		probeStartUsec = Time.get_ticks_usec()

	for componentId: int in _probeAnchorByComponent:
		if metrics != null:
			metrics.anchorProbeCount += 1

		var nodeKey: Vector2i = _probeAnchorByComponent[componentId]
		var anchor: Vector2 = NavigationAnchorGraph.GetAnchorPosition(footprint, nodeKey)

		var path: PackedVector2Array = _localPathfinder.FindLocalPath(
			position,
			anchor,
			halfSize,
			regionId,
			localSearchMarginCells,
			metrics,
		)
		if not _EnsurePathEndsAtAnchor(position, path, anchor, halfSize, regionId, metrics):
			# 같은 baked component의 다른 Anchor도 도달 불가능하므로 전부 생략 가능.
			_unreachableAnchorComponents[componentId] = true
			continue

		if metrics != null:
			metrics.anchorProbeSuccessCount += 1

		_reachableAnchorComponents[componentId] = true
		_addedAnchorNodes[nodeKey] = true

		result.append(_CreateAnchorConnection(nodeKey, path, _GetWaypointPathCost(position, path)))

	if metrics != null:
		metrics.anchorProbeUsec += (Time.get_ticks_usec() - probeStartUsec)

	# 3. 남은 Anchor를 Portal별로 묶어 경로를 계산한다.
	_FillRemainingByPortal(
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
		if metrics != null:
			batchStartUsec = Time.get_ticks_usec()
		_FillLocalPathsToPortalAnchors(
			position,
			portalNodes,
			halfSize,
			regionId,
			footprint,
			localSearchMarginCells,
			metrics,
		)
		if metrics != null:
			metrics.anchorPortalBatchUsec += (Time.get_ticks_usec() - batchStartUsec)

		for nodeKey: Vector2i in portalNodes:
			var path: PackedVector2Array
			if _portalAnchorPathsByNode.has(nodeKey):
				path = _portalAnchorPathsByNode[nodeKey]
			else:
				var fallbackStartUsec: int = 0
				if metrics != null:
					fallbackStartUsec = Time.get_ticks_usec()
					metrics.anchorIndividualFallbackCount += 1

				var anchor: Vector2 = NavigationAnchorGraph.GetAnchorPosition(footprint, nodeKey)
				path = _localPathfinder.FindLocalPath(
					position,
					anchor,
					halfSize,
					regionId,
					localSearchMarginCells,
					metrics,
				)
				var fallbackSuccess: bool = _EnsurePathEndsAtAnchor(
					position,
					path,
					anchor,
					halfSize,
					regionId,
					metrics,
				)

				if metrics != null:
					metrics.anchorIndividualFallbackUsec += (
						Time.get_ticks_usec() - fallbackStartUsec
					)

				if not fallbackSuccess:
					continue

				if metrics != null:
					metrics.anchorIndividualFallbackSuccessCount += 1

			result.append(
				_CreateAnchorConnection(nodeKey, path, _GetWaypointPathCost(position, path))
			)

	return result


func _GetWaypointPathCost(start: Vector2, path: PackedVector2Array) -> float:
	var cost: float = 0.0
	var current: Vector2 = start

	for point: Vector2 in path:
		cost += current.distance_to(point)
		current = point

	return cost


func _EnsurePathEndsAtAnchor(
	start: Vector2,
	path: PackedVector2Array,
	anchor: Vector2,
	halfSize: int,
	regionId: int,
	metrics: NavigationProfileMetrics,
) -> bool:
	var last: Vector2 = start
	if not path.is_empty():
		last = path[path.size() - 1]

	if Math.IsSamePoint(last, anchor):
		return true

	if not _localPathfinder.IsSegmentClearInsideRegion(last, anchor, halfSize, regionId, metrics):
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
	localSearchMarginCells: int,
	metrics: NavigationProfileMetrics,
) -> void:
	var details: NavigationProfileMetrics = (
		metrics
		if metrics != null and metrics.capturePortalBatchDetails
		else null
	)
	var detailStart: int = Time.get_ticks_usec() if details != null else 0
	_ResetPortalAnchorSearchScratch()

	if nodeKeys.is_empty():
		if details != null:
			details.RecordPortalBatchDetails(
				start,
				regionId,
				Time.get_ticks_usec() - detailStart,
				0,
				0,
			)
		return

	var benchmarkStartUsec: int = 0
	if metrics != null:
		benchmarkStartUsec = Time.get_ticks_usec()
		metrics.anchorPortalBatchSearchCalls += 1

	var navigationMap: NavigationFootprintMapData = _localPathfinder.GetFootprintMap(halfSize)

	var pathOffset: Vector2 = _localPathfinder.GetPathLatticeOffset(halfSize)
	var startCell: Vector2i = _localPathfinder.GetNearestPathCell(
		start,
		halfSize,
		pathOffset,
		metrics,
	)
	if startCell.x < 0:
		if details != null:
			details.RecordPortalBatchDetails(
				start,
				regionId,
				Time.get_ticks_usec() - detailStart,
				0,
				0,
			)
		return

	var startIndex: int = Grid.CellToIndex(startCell, _gridWidth)
	var startComponent: int = navigationMap.componentMap[startIndex]
	if startComponent < 0:
		if details != null:
			details.RecordPortalBatchDetails(
				start,
				regionId,
				Time.get_ticks_usec() - detailStart,
				0,
				0,
			)
		return

	for nodeKey: Vector2i in nodeKeys:
		var anchor: Vector2 = NavigationAnchorGraph.GetAnchorPosition(footprint, nodeKey)
		var targetCell: Vector2i = _localPathfinder.GetNearestPathCell(
			anchor,
			halfSize,
			pathOffset,
			metrics,
		)
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
		if details != null:
			details.RecordPortalBatchDetails(
				start,
				regionId,
				Time.get_ticks_usec() - detailStart,
				0,
				0,
			)
		return

	var gridStart: int = Time.get_ticks_usec() if details != null else 0
	if _useIndividualPortalPaths:
		_gridPathfinder.FillPathsToTargetsIndividually(
			_portalGridPathsByTargetIndex,
			startCell,
			_portalTargetCells,
			pathOffset,
			navigationMap,
			regionId,
			localSearchMarginCells,
			details != null,
			_individualPortalHeuristicWeight,
		)
	else:
		_gridPathfinder.FillPathsToTargets(
			_portalGridPathsByTargetIndex,
			startCell,
			_portalTargetCells,
			pathOffset,
			navigationMap,
			regionId,
			localSearchMarginCells,
			details != null,
		)
	var gridEnd: int = Time.get_ticks_usec() if details != null else 0

	if metrics != null:
		metrics.anchorPortalBatchExpanded += _gridPathfinder.lastExpandedCount
		metrics.anchorPortalBatchRelaxed += _gridPathfinder.lastRelaxedCount

	for targetIndex: int in _portalGridPathsByTargetIndex:
		var basePath: PackedVector2Array = _portalGridPathsByTargetIndex[targetIndex]

		var nodeValues: Array = _portalNodesByTargetIndex[targetIndex]

		for nodeKey: Vector2i in nodeValues:
			var path: PackedVector2Array = basePath.duplicate()

			var anchor: Vector2 = NavigationAnchorGraph.GetAnchorPosition(footprint, nodeKey)

			if _EnsurePathEndsAtAnchor(start, path, anchor, halfSize, regionId, metrics):
				_portalAnchorPathsByNode[nodeKey] = path

	var detailEnd: int = Time.get_ticks_usec() if details != null else 0
	if metrics != null:
		var elapsedUsec: int = (Time.get_ticks_usec() - benchmarkStartUsec)
		if elapsedUsec > metrics.anchorBatchMaxUsec:
			metrics.anchorBatchMaxUsec = elapsedUsec
			metrics.anchorBatchMaxExpanded = _gridPathfinder.lastExpandedCount
			metrics.anchorBatchMaxRelaxed = _gridPathfinder.lastRelaxedCount
			metrics.anchorBatchMaxTargetCount = _portalTargetCells.size()
			metrics.anchorBatchMaxSearchArea = _gridPathfinder.lastSearchArea
	if details != null:
		details.RecordPortalBatchDetails(
			start,
			regionId,
			gridStart - detailStart,
			gridEnd - gridStart,
			detailEnd - gridEnd,
			_portalTargetCells.size(),
			_gridPathfinder.lastExpandedCount,
			_gridPathfinder.lastRelaxedCount,
			_gridPathfinder.lastSearchArea,
			true,
			_gridPathfinder.lastBatchPreparationUsec,
			_gridPathfinder.lastBatchSearchUsec,
			_gridPathfinder.lastBatchReconstructionUsec,
			_gridPathfinder.lastBatchReconstructionCalls,
			_portalGridPathsByTargetIndex.size(),
			_gridPathfinder.lastBatchReconstructedWaypoints,
		)


func _ResetPortalAnchorSearchScratch() -> void:
	_portalAnchorPathsByNode.clear()
	_portalGridPathsByTargetIndex.clear()

	for targetIndex: int in _portalActiveTargetIndices:
		var nodes: Array = _portalNodesByTargetIndex[targetIndex]
		nodes.clear()

	_portalActiveTargetIndices.clear()
	_portalTargetCells.clear()

#endregion


func _FillProbeByComponent(
	result: Dictionary[int, Vector2i],
	distanceByComponent: Dictionary[int, float],
	position: Vector2,
	nodes: Array[Vector2i],
	componentByNode: Dictionary[Vector2i, int],
	addedNodes: Dictionary[Vector2i, bool],
	reachableComponents: Dictionary[int, bool],
	footprint: NavigationFootprintData,
) -> void:
	result.clear()
	distanceByComponent.clear()

	for nodeKey: Vector2i in nodes:
		if addedNodes.has(nodeKey):
			continue

		var componentId: int = int(componentByNode[nodeKey])
		if reachableComponents.has(componentId):
			continue

		var anchor: Vector2 = NavigationAnchorGraph.GetAnchorPosition(footprint, nodeKey)

		var distance: float = position.distance_squared_to(anchor)
		var previousDistance: float = float(distanceByComponent.get(componentId, Math.BIG_NUMBER))

		if distance >= previousDistance:
			continue

		result[componentId] = nodeKey
		distanceByComponent[componentId] = distance


func _FillRemainingByPortal(
	result: Dictionary[int, Array],
	nodes: Array[Vector2i],
	componentByNode: Dictionary[Vector2i, int],
	addedNodes: Dictionary[Vector2i, bool],
	reachableComponents: Dictionary[int, bool],
	unreachableComponents: Dictionary[int, bool],
) -> void:
	for portalId: int in result:
		var portalNodes: Array = result[portalId]
		portalNodes.clear()

	for nodeKey: Vector2i in nodes:
		if addedNodes.has(nodeKey):
			continue

		var componentId: int = int(componentByNode[nodeKey])
		if unreachableComponents.has(componentId) or not reachableComponents.has(componentId):
			continue

		if not result.has(nodeKey.x):
			result[nodeKey.x] = []

		var portalNodes: Array = result[nodeKey.x]
		portalNodes.append(nodeKey)
