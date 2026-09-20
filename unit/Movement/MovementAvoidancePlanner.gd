class_name MovementAvoidancePlanner
extends RefCounted

const CORNER_CLEARANCE: float = 0.05
const EPSILON: float = 0.001
const MAX_BLOCKERS: int = 12

class Obstacle:
	var agent: MovementAgent
	var position: Vector2
	var halfSize: int

class Detour:
	var agent: MovementAgent
	var movementRevision: int
	var halfSize: int
	var obstacles: Array[Obstacle] = []
	var targetPosition: Vector2
	var waypoints: PackedVector2Array = []
	var waypointIndex: int = 0

var _navigationService: NavigationService
var _detours: Dictionary[int, Detour] = {}


func _init(navigationService: NavigationService) -> void:
	_navigationService = navigationService


func BeginTick(group: CollisionGroup) -> void:
	for unitId: int in _detours.keys():
		var detour: Detour = _detours[unitId]
		if not _IsValid(detour, group):
			_detours.erase(unitId)
			detour.agent.OnAvoidanceEnded()


func GetDetour(data: CollisionGroup.AgentData) -> Detour:
	var detour: Detour = _detours.get(data.unitId)
	if detour == null:
		return null
	if _CanResumePath(data, detour):
		_detours.erase(data.unitId)
		data.agent.OnAvoidanceEnded()
		return null
	_AdvanceWaypoint(data.startPosition, detour)
	return detour


func BeginDetour(data: CollisionGroup.AgentData, blocker: CollisionGroup.AgentData) -> Detour:
	if _SharesArrival(data.agent, blocker.agent):
		return null
	if data.agent.GetSteeringTarget().distance_squared_to(data.startPosition) <= EPSILON * EPSILON:
		return null
	var detour: Detour = Detour.new()
	detour.agent = data.agent
	detour.movementRevision = data.agent.movementRevision
	detour.halfSize = data.halfSize
	detour.targetPosition = data.agent.GetSteeringTarget()
	_AddObstacle(detour, blocker)
	detour.waypoints = _FindRoute(
		data.startPosition, detour.targetPosition, detour,
	)
	_detours[data.unitId] = detour
	data.agent.OnAvoidanceStarted()
	return detour


func ExtendDetour(data: CollisionGroup.AgentData, blocker: CollisionGroup.AgentData) -> Detour:
	var detour: Detour = _detours.get(data.unitId)
	if detour == null or detour.obstacles.size() >= MAX_BLOCKERS:
		return null
	if _SharesArrival(data.agent, blocker.agent):
		return null
	for obstacle: Obstacle in detour.obstacles:
		if obstacle.agent == blocker.agent:
			return null
	_AddObstacle(detour, blocker)
	detour.waypoints = _FindRoute(data.startPosition, detour.targetPosition, detour)
	detour.waypointIndex = 0
	return detour


func _AddObstacle(detour: Detour, blocker: CollisionGroup.AgentData) -> void:
	var obstacle: Obstacle = Obstacle.new()
	obstacle.agent = blocker.agent
	obstacle.position = blocker.nextPosition
	obstacle.halfSize = blocker.halfSize
	detour.obstacles.append(obstacle)


func GetDesiredPosition(data: CollisionGroup.AgentData, detour: Detour) -> Vector2:
	if detour.waypointIndex >= detour.waypoints.size():
		return data.startPosition
	return data.startPosition.move_toward(
		detour.waypoints[detour.waypointIndex], data.maxStepDistance,
	)


func _IsValid(detour: Detour, group: CollisionGroup) -> bool:
	var data: CollisionGroup.AgentData = group.GetAgent(detour.agent.unitId)
	if (
		data == null or data.agent != detour.agent
		or data.agent.movementRevision != detour.movementRevision
		or data.halfSize != detour.halfSize or not data.canMove
	):
		return false
	for obstacle: Obstacle in detour.obstacles:
		if not _IsObstacleValid(data.agent, obstacle, group):
			return false
	return true


func _IsObstacleValid(agent: MovementAgent, obstacle: Obstacle, group: CollisionGroup) -> bool:
	var blocker: CollisionGroup.AgentData = group.GetAgent(obstacle.agent.unitId)
	return (
		blocker != null and blocker.agent == obstacle.agent
		and blocker.halfSize == obstacle.halfSize
		and blocker.desiredPosition == blocker.startPosition
		and blocker.startPosition == obstacle.position
		and not _SharesArrival(agent, blocker.agent)
	)


func _SharesArrival(agent: MovementAgent, blocker: MovementAgent) -> bool:
	return (
		blocker.isSettled and agent.moveCommandId >= 0
		and agent.moveCommandId == blocker.moveCommandId
		and agent.moveTarget.distance_squared_to(blocker.moveTarget) <= EPSILON * EPSILON
	)


func _CanResumePath(data: CollisionGroup.AgentData, detour: Detour) -> bool:
	if not _IsEdgeClear(data.startPosition, detour.targetPosition, detour):
		return false
	var target: Vector2 = data.agent.GetSteeringTarget()
	if target.distance_squared_to(data.startPosition) <= EPSILON * EPSILON:
		return true
	if target == detour.targetPosition:
		return true
	return _IsEdgeClear(data.startPosition, target, detour)


func _AdvanceWaypoint(position: Vector2, detour: Detour) -> void:
	while detour.waypointIndex < detour.waypoints.size():
		if position.distance_squared_to(detour.waypoints[detour.waypointIndex]) > EPSILON * EPSILON:
			return
		detour.waypointIndex += 1


func _FindRoute(start: Vector2, target: Vector2, detour: Detour) -> PackedVector2Array:
	var nodes: PackedVector2Array = _BuildNodes(start, target, detour)
	var distances: PackedFloat64Array = []
	var parents: PackedInt32Array = []
	var visited: PackedByteArray = []
	distances.resize(nodes.size())
	distances.fill(INF)
	parents.resize(nodes.size())
	parents.fill(-1)
	visited.resize(nodes.size())
	distances[0] = 0.0
	for iteration: int in range(nodes.size()):
		var current: int = _FindClosestNode(distances, visited)
		if current < 0:
			break
		if current == 1:
			return _ReconstructRoute(nodes, parents)
		visited[current] = 1
		for neighbor: int in range(nodes.size()):
			if visited[neighbor] != 0:
				continue
			var distance: float = distances[current] + nodes[current].distance_to(nodes[neighbor])
			if distance >= distances[neighbor]:
				continue
			if not _IsEdgeClear(nodes[current], nodes[neighbor], detour):
				continue
			distances[neighbor] = distance
			parents[neighbor] = current
	return PackedVector2Array()


func _BuildNodes(start: Vector2, target: Vector2, detour: Detour) -> PackedVector2Array:
	var nodes: PackedVector2Array = [start, target]
	for obstacle: Obstacle in detour.obstacles:
		var extent: float = float(detour.halfSize + obstacle.halfSize) + CORNER_CLEARANCE
		for offset: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			nodes.append(obstacle.position + offset * extent)
	return nodes


func _FindClosestNode(distances: PackedFloat64Array, visited: PackedByteArray) -> int:
	var closest: int = -1
	var shortest: float = INF
	for index: int in range(distances.size()):
		if visited[index] == 0 and distances[index] < shortest:
			shortest = distances[index]
			closest = index
	return closest


func _ReconstructRoute(nodes: PackedVector2Array, parents: PackedInt32Array) -> PackedVector2Array:
	var route: PackedVector2Array = []
	var index: int = 1
	while index != 0:
		route.append(nodes[index])
		index = parents[index]
	route.reverse()
	return route


func _IsEdgeClear(start: Vector2, end: Vector2, detour: Detour) -> bool:
	var length: float = start.distance_to(end)
	var direction: Vector2 = start.direction_to(end)
	for obstacle: Obstacle in detour.obstacles:
		var contact: float = MovementCollisionQuery.FirstContactDistance(
			start, direction, obstacle.position, float(detour.halfSize + obstacle.halfSize),
		)
		if contact < length:
			return false
	return _navigationService == null or _navigationService.SegmentClear(start, end, detour.halfSize)
