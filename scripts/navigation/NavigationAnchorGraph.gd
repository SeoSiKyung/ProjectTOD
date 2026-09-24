class_name NavigationAnchorGraph
extends RefCounted


static func Build(footprint: NavigationFootprintData) -> NavigationAnchorTypes.GraphData:
	var result: NavigationAnchorTypes.GraphData = NavigationAnchorTypes.GraphData.new()

	for route: NavigationPortalRouteData in footprint.portalRoutes:
		if route == null:
			continue
		if (
			not _IsValidAnchor(footprint, route.fromPortalId, route.fromAnchorIndex)
			or not _IsValidAnchor(footprint, route.toPortalId, route.toAnchorIndex)
		):
			continue

		var fromKey: Vector2i = Vector2i(route.fromPortalId, route.fromAnchorIndex)
		var toKey: Vector2i = Vector2i(route.toPortalId, route.toAnchorIndex)

		var forwardEdge: NavigationAnchorTypes.GraphEdge = (NavigationAnchorTypes.GraphEdge.new())
		forwardEdge.toPortalId = route.toPortalId
		forwardEdge.toAnchorIndex = route.toAnchorIndex
		forwardEdge.route = route
		forwardEdge.reversed = false

		_AppendEdge(result, fromKey, forwardEdge)

		var reverseEdge: NavigationAnchorTypes.GraphEdge = (NavigationAnchorTypes.GraphEdge.new())
		reverseEdge.toPortalId = route.fromPortalId
		reverseEdge.toAnchorIndex = route.fromAnchorIndex
		reverseEdge.route = route
		reverseEdge.reversed = true

		_AppendEdge(result, toKey, reverseEdge)

	return result


static func GetAnchorPosition(footprint: NavigationFootprintData, nodeKey: Vector2i) -> Vector2:
	if not _IsValidAnchor(footprint, nodeKey.x, nodeKey.y):
		return Vector2.ZERO

	return footprint.portals[nodeKey.x].anchors[nodeKey.y]


static func _IsValidAnchor(
	footprint: NavigationFootprintData,
	portalId: int,
	anchorIndex: int,
) -> bool:
	if footprint == null:
		return false

	if portalId < 0 or portalId >= footprint.portals.size():
		return false

	var portalData: NavigationFootprintPortalData = footprint.portals[portalId]
	if portalData == null:
		return false

	return 0 <= anchorIndex and anchorIndex < portalData.anchors.size()


static func _AppendEdge(
	graph: NavigationAnchorTypes.GraphData,
	nodeKey: Vector2i,
	edge: NavigationAnchorTypes.GraphEdge,
) -> void:
	if not graph.edgesByNode.has(nodeKey):
		graph.edgesByNode[nodeKey] = []

	var edges: Array = graph.edgesByNode[nodeKey]
	edges.append(edge)
