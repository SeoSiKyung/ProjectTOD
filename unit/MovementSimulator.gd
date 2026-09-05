class_name MovementSimulator
extends RefCounted


const INVALID_INDEX: int = -1
const EPSILON: float = 0.00001
const MAX_ITERATIONS: int = 128


var _navigationService: NavigationService
var _collisionResolver: CollisionResolver

var _agents: Array = []
var _agentIndexByUnitId: Dictionary = {}
var _units: Dictionary = {}

var _desiredPositions: Dictionary = {}
var _nextPositions: Dictionary = {}

var _slideDirections: Dictionary = {}
var _slideIdleIds: Dictionary = {}


func _init(navigationService: NavigationService) -> void:
	_navigationService = navigationService
	_collisionResolver = CollisionResolver.new(navigationService)
	PathFollower.SetNavigationService(navigationService)


func SetNavigationService(navigationService: NavigationService) -> void:
	_navigationService = navigationService
	_collisionResolver = CollisionResolver.new(navigationService)
	PathFollower.SetNavigationService(navigationService)


func RegisterAgent(agent: MovementAgent) -> bool:
	if not is_instance_valid(agent):
		return false

	if agent.unitId < 0:
		return false

	if _agentIndexByUnitId.has(agent.unitId):
		return false

	if _agents.has(agent):
		return false

	_agentIndexByUnitId[agent.unitId] = _agents.size()
	_agents.append(agent)

	var unit: Unit = _findUnit(agent.unitId)

	if unit != null:
		_units[agent.unitId] = unit

	return true


func UnregisterAgent(unitId: int) -> MovementAgent:
	var index: int = _agentIndexByUnitId.get(unitId, INVALID_INDEX)

	if index == INVALID_INDEX:
		return null

	var removedAgent: MovementAgent = _agents[index]
	var lastIndex: int = _agents.size() - 1

	if index != lastIndex:
		var lastAgent: MovementAgent = _agents[lastIndex]
		_agents[index] = lastAgent
		_agentIndexByUnitId[lastAgent.unitId] = index

	_agents.pop_back()
	_agentIndexByUnitId.erase(unitId)
	_units.erase(unitId)
	_desiredPositions.erase(unitId)
	_nextPositions.erase(unitId)
	_slideDirections.erase(unitId)
	_slideIdleIds.erase(unitId)

	return removedAgent


func SetPath(unitId: int, path: PackedVector2Array) -> bool:
	var agent: MovementAgent = _getAgent(unitId)

	if agent == null:
		return false

	_clearAvoidance(unitId)
	agent.SetPath(path)

	return true


func SetMoveCommand(unitId: int, path: PackedVector2Array, commandId: int, target: Vector2, arrivalRadius: float) -> bool:
	var agent: MovementAgent = _getAgent(unitId)

	if agent == null:
		return false

	_clearAvoidance(unitId)
	agent.BeginMove(path, commandId, target, arrivalRadius)

	return true


func StopUnit(unitId: int) -> bool:
	var agent: MovementAgent = _getAgent(unitId)

	if agent == null:
		return false

	_clearAvoidance(unitId)
	agent.Stop()

	return true


func PauseUnit(unitId: int) -> bool:
	var agent: MovementAgent = _getAgent(unitId)

	if agent == null:
		return false

	_clearAvoidance(unitId)
	agent.Pause()

	return true


func ResumeUnit(unitId: int) -> bool:
	var agent: MovementAgent = _getAgent(unitId)

	if agent == null:
		return false

	_clearAvoidance(unitId)
	agent.Resume()

	return true


func IsUnitMoving(unitId: int) -> bool:
	var agent: MovementAgent = _getAgent(unitId)

	if agent == null:
		return false

	return agent.HasPath()


func TeleportUnit(unitId: int, position: Vector2, snapshot: StageSnapshot) -> bool:
	if snapshot == null:
		return false

	var agent: MovementAgent = _getAgent(unitId)

	if agent == null or not snapshot.HasUnit(unitId):
		return false

	if _navigationService != null:
		if not _navigationService.CanPlaceStatic(position, agent.halfSize):
			return false

	if _overlapsRegistered(position, agent.halfSize, unitId):
		return false

	agent.Teleport(position)
	snapshot.UpdatePosition(unitId, position)
	_clearAvoidance(unitId)

	return true


func SimulateTick(snapshot: StageSnapshot, fixedDelta: float) -> bool:
	if snapshot == null:
		return false

	if fixedDelta <= EPSILON:
		return false

	_captureDesiredPositions(fixedDelta)
	_clearFinishedSlides()

	_nextPositions.clear()

	for agent: MovementAgent in _agents:
		_nextPositions[agent.unitId] = _desiredPositions[agent.unitId]

	var desiredCollisions: Array = _findDesiredCollisions()

	if desiredCollisions.is_empty():
		return _commit(snapshot, fixedDelta)

	for _iteration: int in range(MAX_ITERATIONS):
		var resultCollisions: Array = _findResultCollisions()

		if resultCollisions.is_empty():
			return _commit(snapshot, fixedDelta)

		var groups: Array = _buildGroups(resultCollisions)

		if groups.is_empty():
			return false

		var changed: bool = false

		for group: CollisionGroup in groups:
			if not _collisionResolver.Resolve(group, fixedDelta):
				continue

			for data: CollisionGroup.AgentData in group.agents:
				_nextPositions[data.agent.unitId] = data.nextPosition
				_updateSlideState(data)

			changed = true
			break

		if not changed:
			return false

	if not _findResultCollisions().is_empty():
		return false

	return _commit(snapshot, fixedDelta)


func Clear() -> void:
	_agents.clear()
	_agentIndexByUnitId.clear()
	_units.clear()
	_desiredPositions.clear()
	_nextPositions.clear()
	_slideDirections.clear()
	_slideIdleIds.clear()


func _captureDesiredPositions(fixedDelta: float) -> void:
	_desiredPositions.clear()

	for agent: MovementAgent in _agents:
		var unit: Unit = _getUnit(agent.unitId)

		if unit != null and unit.fsm != null and unit.fsm.currentState == UnitFSM.State.IDLE:
			_desiredPositions[agent.unitId] = agent.position
		else:
			_desiredPositions[agent.unitId] = agent.GetDesiredPosition(fixedDelta)


func _findDesiredCollisions() -> Array:
	var result: Array = []

	for firstIndex: int in range(_agents.size()):
		var first: MovementAgent = _agents[firstIndex]

		for secondIndex: int in range(firstIndex + 1, _agents.size()):
			var second: MovementAgent = _agents[secondIndex]

			if not _overlap(
				_desiredPositions[first.unitId],
				first.halfSize,
				_desiredPositions[second.unitId],
				second.halfSize
			):
				continue

			result.append(Vector2i(first.unitId, second.unitId))

	return result


func _findResultCollisions() -> Array:
	var result: Array = []

	for firstIndex: int in range(_agents.size()):
		var first: MovementAgent = _agents[firstIndex]

		for secondIndex: int in range(firstIndex + 1, _agents.size()):
			var second: MovementAgent = _agents[secondIndex]

			if not _overlap(
				_nextPositions[first.unitId],
				first.halfSize,
				_nextPositions[second.unitId],
				second.halfSize
			):
				continue

			result.append(Vector2i(first.unitId, second.unitId))

	return result


func _buildGroups(pairs: Array) -> Array:
	var adjacency: Dictionary = {}

	for pair: Vector2i in pairs:
		if not adjacency.has(pair.x):
			adjacency[pair.x] = []

		if not adjacency.has(pair.y):
			adjacency[pair.y] = []

		adjacency[pair.x].append(pair.y)
		adjacency[pair.y].append(pair.x)

	var result: Array = []
	var visited: Dictionary = {}

	for agent: MovementAgent in _agents:
		if visited.has(agent.unitId):
			continue

		if not adjacency.has(agent.unitId):
			continue

		var queue: Array = [agent.unitId]
		var members: Array = []
		visited[agent.unitId] = true

		while not queue.is_empty():
			var currentId: int = int(queue.pop_front())
			members.append(currentId)

			for linkedValue in adjacency[currentId]:
				var linkedId: int = int(linkedValue)

				if visited.has(linkedId):
					continue

				visited[linkedId] = true
				queue.append(linkedId)

		var group: CollisionGroup = CollisionGroup.new()

		for memberId in members:
			var memberAgent: MovementAgent = _getAgent(memberId)

			if memberAgent == null:
				continue

			var slideDirection: Vector2 = _slideDirections.get(memberId, Vector2.ZERO)
			var slideIdleIds: Array = _slideIdleIds.get(memberId, [])

			group.AddAgent(
				memberAgent,
				_getUnit(memberId),
				memberAgent.position,
				_desiredPositions[memberId],
				_nextPositions[memberId],
				slideDirection,
				slideIdleIds
			)

		for pair: Vector2i in pairs:
			if not _groupContains(group, pair.x):
				continue

			if not _groupContains(group, pair.y):
				continue

			group.AddCollision(pair.x, pair.y)

		result.append(group)

	return result


func _updateSlideState(data: CollisionGroup.AgentData) -> void:
	if data.slideDirection.length_squared() <= EPSILON:
		return

	if data.currentIdleIds.is_empty():
		return

	var oldIdleIds: Array = _slideIdleIds.get(data.agent.unitId, [])

	if oldIdleIds.is_empty():
		_slideDirections[data.agent.unitId] = data.slideDirection
		_slideIdleIds[data.agent.unitId] = data.currentIdleIds.duplicate()
		return

	if _sameIdleIds(oldIdleIds, data.currentIdleIds):
		_slideDirections[data.agent.unitId] = data.slideDirection
		return

	_slideDirections[data.agent.unitId] = data.slideDirection
	_slideIdleIds[data.agent.unitId] = data.currentIdleIds.duplicate()


func _sameIdleIds(first: Array, second: Array) -> bool:
	if first.size() != second.size():
		return false

	for value in first:
		if not second.has(value):
			return false

	for value in second:
		if not first.has(value):
			return false

	return true


func _clearFinishedSlides() -> void:
	var removeIds: Array = []

	for idValue in _slideDirections.keys():
		var unitId: int = int(idValue)
		var idleIds: Array = _slideIdleIds.get(unitId, [])

		if idleIds.is_empty():
			removeIds.append(unitId)
			continue

		var keepSlide: bool = false

		for idleIdValue in idleIds:
			var idleId: int = int(idleIdValue)

			if not _desiredPositions.has(unitId) or not _desiredPositions.has(idleId):
				continue

			var movingAgent: MovementAgent = _getAgent(unitId)
			var idleAgent: MovementAgent = _getAgent(idleId)

			if movingAgent == null or idleAgent == null:
				continue

			if _overlap(
				_desiredPositions[unitId],
				movingAgent.halfSize,
				_desiredPositions[idleId],
				idleAgent.halfSize
			):
				keepSlide = true
				break

		if not keepSlide:
			removeIds.append(unitId)

	for unitId in removeIds:
		_clearAvoidance(unitId)


func _clearAvoidance(unitId: int) -> void:
	_slideDirections.erase(unitId)
	_slideIdleIds.erase(unitId)


func _commit(snapshot: StageSnapshot, fixedDelta: float) -> bool:
	if not _findResultCollisions().is_empty():
		return false

	for agent: MovementAgent in _agents:
		var position: Vector2 = _nextPositions[agent.unitId]

		agent.CommitMovement(position, fixedDelta)
		snapshot.UpdatePosition(agent.unitId, position)

	return true


func _groupContains(group: CollisionGroup, unitId: int) -> bool:
	for data: CollisionGroup.AgentData in group.agents:
		if data.agent.unitId == unitId:
			return true

	return false


func _getAgent(unitId: int) -> MovementAgent:
	var index: int = _agentIndexByUnitId.get(unitId, INVALID_INDEX)

	if index == INVALID_INDEX:
		return null

	return _agents[index]


func _getUnit(unitId: int) -> Unit:
	if _units.has(unitId):
		var cachedUnit: Unit = _units[unitId]

		if is_instance_valid(cachedUnit):
			return cachedUnit

	var unit: Unit = _findUnit(unitId)

	if unit != null:
		_units[unitId] = unit

	return unit


func _findUnit(unitId: int) -> Unit:
	var loop: MainLoop = Engine.get_main_loop()

	if not loop is SceneTree:
		return null

	for node: Node in (loop as SceneTree).get_nodes_in_group("unit"):
		var unit: Unit = node as Unit

		if unit != null and unit.unitId == unitId:
			return unit

	return null


func _overlapsRegistered(position: Vector2, halfSize: int, ignoredUnitId: int) -> bool:
	for other: MovementAgent in _agents:
		if other.unitId == ignoredUnitId:
			continue

		if _overlap(
			position,
			halfSize,
			other.position,
			other.halfSize
		):
			return true

	return false


func _overlap(firstPosition: Vector2, firstHalfSize: int, secondPosition: Vector2, secondHalfSize: int) -> bool:
	var size: float = float(firstHalfSize + secondHalfSize)

	return (
		absf(firstPosition.x - secondPosition.x) < size
		and absf(firstPosition.y - secondPosition.y) < size
	)
