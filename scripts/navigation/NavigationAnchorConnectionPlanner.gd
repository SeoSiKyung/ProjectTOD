class_name NavigationAnchorConnectionPlanner
extends RefCounted


static func FillProbeByComponent(
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


static func FillRemainingByPortal(
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
