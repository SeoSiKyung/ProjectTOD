class_name NavigationHierarchicalPathfinder
extends RefCounted

var _open: Array[Vector2i] = []
var _closed: Dictionary[Vector2i, bool] = { }

var _gScore: Dictionary[Vector2i, float] = { }
var _fScore: Dictionary[Vector2i, float] = { }

var _parentNode: Dictionary[Vector2i, Vector2i] = { }
var _parentEdge: Dictionary[Vector2i, NavigationAnchorTypes.GraphEdge] = { }

var _startConnectionByNode: Dictionary[Vector2i, NavigationAnchorTypes.Connection] = { }

var _targetConnectionByNode: Dictionary[Vector2i, NavigationAnchorTypes.Connection] = { }

var lastPathCost: float = Math.BIG_NUMBER

var _resultStartConnection: NavigationAnchorTypes.Connection = null
var _resultTargetConnection: NavigationAnchorTypes.Connection = null
var _resultEdges: Array[NavigationAnchorTypes.GraphEdge] = []


func FindGraphPath(
	startConnections: Array[NavigationAnchorTypes.Connection],
	targetConnections: Array[NavigationAnchorTypes.Connection],
	footprint: NavigationFootprintData,
	graph: NavigationAnchorTypes.GraphData,
	target: Vector2,
	metrics: NavigationProfileMetrics = null,
) -> bool:
	_ResetSearch()
	_ResetResult()

	if metrics != null:
		metrics.anchorGraphSearchCalls += 1

	for connection: NavigationAnchorTypes.Connection in targetConnections:
		var nodeKey: Vector2i = connection.nodeKey
		var previousCost: float = Math.BIG_NUMBER
		if _targetConnectionByNode.has(nodeKey):
			var previous: NavigationAnchorTypes.Connection = _targetConnectionByNode[nodeKey]
			previousCost = previous.cost

		if connection.cost >= previousCost - Math.EPSILON:
			continue

		_targetConnectionByNode[nodeKey] = connection

	for connection: NavigationAnchorTypes.Connection in startConnections:
		var nodeKey: Vector2i = connection.nodeKey
		var previousCost: float = float(_gScore.get(nodeKey, Math.BIG_NUMBER))
		if connection.cost >= previousCost - Math.EPSILON:
			continue

		_gScore[nodeKey] = connection.cost
		_fScore[nodeKey] = (
			connection.cost
			+ NavigationAnchorGraph.GetAnchorPosition(footprint, nodeKey).distance_to(target)
		)

		_startConnectionByNode[nodeKey] = connection

		if not _open.has(nodeKey):
			_open.append(nodeKey)

	var bestGoalNode: Vector2i = Vector2i(-1, -1)
	var bestGoalCost: float = Math.BIG_NUMBER

	while not _open.is_empty():
		var currentKey: Vector2i = _PopBestNode(_open, _fScore)
		if _closed.has(currentKey):
			continue

		var currentF: float = float(_fScore.get(currentKey, Math.BIG_NUMBER))
		if currentF >= bestGoalCost - Math.EPSILON:
			break

		_closed[currentKey] = true

		if metrics != null:
			metrics.anchorGraphExpanded += 1

		var currentG: float = float(_gScore.get(currentKey, Math.BIG_NUMBER))

		if _targetConnectionByNode.has(currentKey):
			var targetConnection: NavigationAnchorTypes.Connection = _targetConnectionByNode[
				currentKey
			]

			var totalCost: float = currentG + targetConnection.cost
			if totalCost < bestGoalCost - Math.EPSILON:
				bestGoalCost = totalCost
				bestGoalNode = currentKey

		if not graph.edgesByNode.has(currentKey):
			continue

		var edges: Array = graph.edgesByNode[currentKey]
		for edge: NavigationAnchorTypes.GraphEdge in edges:
			if edge == null or edge.route == null:
				continue

			var nextKey: Vector2i = Vector2i(edge.toPortalId, edge.toAnchorIndex)
			if _closed.has(nextKey):
				continue

			var tentativeG: float = currentG + edge.route.cost
			var previousG: float = float(_gScore.get(nextKey, Math.BIG_NUMBER))
			if tentativeG >= previousG - Math.EPSILON:
				continue

			if metrics != null:
				metrics.anchorGraphRelaxed += 1

			_gScore[nextKey] = tentativeG

			var nextPosition: Vector2 = NavigationAnchorGraph.GetAnchorPosition(footprint, nextKey)

			_fScore[nextKey] = tentativeG + nextPosition.distance_to(target)

			_parentNode[nextKey] = currentKey
			_parentEdge[nextKey] = edge

			if not _open.has(nextKey):
				_open.append(nextKey)

	if bestGoalNode.x < 0:
		return false

	var startNode: Vector2i = bestGoalNode
	while _parentNode.has(startNode):
		var edge: NavigationAnchorTypes.GraphEdge = _parentEdge[startNode]

		_resultEdges.append(edge)
		startNode = _parentNode[startNode]

	_resultEdges.reverse()

	_resultStartConnection = _startConnectionByNode[startNode]
	_resultTargetConnection = _targetConnectionByNode[bestGoalNode]
	lastPathCost = bestGoalCost

	return true


func BuildPath(target: Vector2) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()

	for point: Vector2 in _resultStartConnection.path:
		_AppendUniquePoint(result, point)

	for edge: NavigationAnchorTypes.GraphEdge in _resultEdges:
		var routePath: PackedVector2Array = edge.route.path

		if edge.reversed:
			for index: int in range(routePath.size() - 1, -1, -1):
				_AppendUniquePoint(result, routePath[index])
		else:
			for point: Vector2 in routePath:
				_AppendUniquePoint(result, point)

	var targetPath: PackedVector2Array = (_resultTargetConnection.path)
	for index: int in range(targetPath.size() - 1, -1, -1):
		_AppendUniquePoint(result, targetPath[index])

	_AppendUniquePoint(result, target)

	return result


func _ResetSearch() -> void:
	_open.clear()
	_closed.clear()

	_gScore.clear()
	_fScore.clear()

	_parentNode.clear()
	_parentEdge.clear()

	_startConnectionByNode.clear()
	_targetConnectionByNode.clear()


static func _PopBestNode(open: Array[Vector2i], fScore: Dictionary[Vector2i, float]) -> Vector2i:
	var bestIndex: int = 0
	var bestScore: float = Math.BIG_NUMBER

	for index: int in range(open.size()):
		var nodeKey: Vector2i = open[index]
		var score: float = float(fScore.get(nodeKey, Math.BIG_NUMBER))
		if score >= bestScore:
			continue

		bestScore = score
		bestIndex = index

	var result: Vector2i = open[bestIndex]
	open.remove_at(bestIndex)

	return result


static func _AppendUniquePoint(path: PackedVector2Array, point: Vector2) -> void:
	if not path.is_empty() and path[path.size() - 1].distance_squared_to(point) <= Math.EPSILON:
		return

	path.append(point)


func _ResetResult() -> void:
	lastPathCost = Math.BIG_NUMBER

	_resultStartConnection = null
	_resultTargetConnection = null
	_resultEdges.clear()
