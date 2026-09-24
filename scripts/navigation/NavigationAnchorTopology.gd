class_name NavigationAnchorTopology
extends RefCounted


static func Build(
	regionId: int,
	region: NavigationRegionData,
	footprint: NavigationFootprintData,
) -> NavigationAnchorTypes.RegionTopology:
	var topology: NavigationAnchorTypes.RegionTopology = NavigationAnchorTypes.RegionTopology.new()

	if region == null or footprint == null:
		return topology

	topology.nodes = _GetNodes(region, footprint)
	if not topology.nodes.is_empty():
		topology.componentByNode = _MakeComponentMap(regionId, topology.nodes, footprint)

	return topology


static func _GetNodes(
	region: NavigationRegionData,
	footprint: NavigationFootprintData,
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []

	for portalId: int in region.portalIds:
		if portalId < 0 or portalId >= footprint.portals.size():
			continue

		var portal: NavigationFootprintPortalData = footprint.portals[portalId]
		if portal == null or portal.anchors.is_empty():
			continue

		for anchorIndex: int in range(portal.anchors.size()):
			result.append(Vector2i(portalId, anchorIndex))

	return result


static func _MakeComponentMap(
	regionId: int,
	nodes: Array[Vector2i],
	footprint: NavigationFootprintData,
) -> Dictionary[Vector2i, int]:
	var adjacency: Dictionary[Vector2i, Array] = { }

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

	var result: Dictionary[Vector2i, int] = { }
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
			for next: Vector2i in neighbors:
				if result.has(next):
					continue

				result[next] = componentId
				queue.append(next)

		componentId += 1

	return result
