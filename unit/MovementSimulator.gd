class_name MovementSimulator
extends RefCounted

const INVALID_INDEX: int = -1
const EPSILON: float = 0.00001

var lastError: String = ""
var _navigationService: NavigationService
var _unitManager: UnitManager
var _collisionResolver: CollisionResolver
var _arrivalResolver: MovementArrivalResolver
var _profileMetrics: MovementProfileMetrics
var _agents: Array[MovementAgent] = []
var _agentIndexByUnitId: Dictionary[int, int] = {}


func _init(navigationService: NavigationService, unitManager: UnitManager = null) -> void:
	_unitManager = unitManager
	SetNavigationService(navigationService)


func SetNavigationService(navigationService: NavigationService) -> void:
	_navigationService = navigationService
	_collisionResolver = CollisionResolver.new(navigationService)
	_arrivalResolver = MovementArrivalResolver.new(navigationService)
	_collisionResolver.SetProfileMetrics(_profileMetrics)
	_arrivalResolver.SetProfileMetrics(_profileMetrics)
	PathFollower.SetNavigationService(navigationService)


func SetProfileMetrics(metrics: MovementProfileMetrics) -> void:
	_profileMetrics = metrics
	_collisionResolver.SetProfileMetrics(metrics)
	_arrivalResolver.SetProfileMetrics(metrics)


func ClearProfileMetrics() -> void:
	SetProfileMetrics(null)


func RegisterAgent(agent: MovementAgent) -> bool:
	if not is_instance_valid(agent):
		return false
	if agent.unitId < 0 or _agentIndexByUnitId.has(agent.unitId):
		return false
	if _agents.has(agent):
		return false
	if agent.halfSize < 0 or not agent.position.is_finite():
		return false
	if not is_finite(agent.moveSpeed) or agent.moveSpeed < 0.0:
		return false
	if not _CanPlaceAgent(agent, agent.position):
		return false
	_agentIndexByUnitId[agent.unitId] = _agents.size()
	_agents.append(agent)
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
	return removedAgent


func SetPath(unitId: int, path: PackedVector2Array) -> bool:
	var agent: MovementAgent = _GetAgent(unitId)
	if agent == null:
		return false
	agent.SetPath(path)
	return true


func SetMoveCommand(
	unitId: int,
	path: PackedVector2Array,
	commandId: int,
	target: Vector2,
	arrivalRadius: float,
) -> bool:
	var agent: MovementAgent = _GetAgent(unitId)
	if agent == null:
		return false
	agent.BeginMove(path, commandId, target, arrivalRadius)
	return true


func StopUnit(unitId: int) -> bool:
	var agent: MovementAgent = _GetAgent(unitId)
	if agent == null:
		return false
	agent.Stop()
	return true


func PauseUnit(unitId: int) -> bool:
	var agent: MovementAgent = _GetAgent(unitId)
	if agent == null:
		return false
	agent.Pause()
	return true


func ResumeUnit(unitId: int) -> bool:
	var agent: MovementAgent = _GetAgent(unitId)
	if agent == null:
		return false
	agent.Resume()
	return true


func IsUnitMoving(unitId: int) -> bool:
	var agent: MovementAgent = _GetAgent(unitId)
	return agent != null and agent.HasPath()


func TeleportUnit(unitId: int, position: Vector2, snapshot: StageSnapshot) -> bool:
	if snapshot == null or not snapshot.HasUnit(unitId) or not position.is_finite():
		return false
	var agent: MovementAgent = _GetAgent(unitId)
	if agent == null or not _CanPlaceAgent(agent, position):
		return false
	agent.Teleport(position)
	snapshot.UpdatePosition(unitId, position)
	return true


func SimulateTick(snapshot: StageSnapshot, fixedDelta: float) -> bool:
	lastError = ""
	if snapshot == null or not is_finite(fixedDelta) or fixedDelta <= EPSILON:
		lastError = "유효한 snapshot과 양수 fixedDelta가 필요합니다."
		return false
	if not _ValidateSnapshot(snapshot):
		return false

	if _profileMetrics != null:
		_profileMetrics.simulationTickCount += 1

	var phaseStart: int = Time.get_ticks_usec() if _profileMetrics != null else 0
	var tick: CollisionGroup = _CaptureTick()
	if _profileMetrics != null:
		_profileMetrics.captureTickUsec += Time.get_ticks_usec() - phaseStart

	phaseStart = Time.get_ticks_usec() if _profileMetrics != null else 0
	if not _collisionResolver.Resolve(tick):
		if _profileMetrics != null:
			_profileMetrics.collisionResolveUsec += Time.get_ticks_usec() - phaseStart
		lastError = _collisionResolver.lastError
		return false
	if _profileMetrics != null:
		_profileMetrics.collisionResolveUsec += Time.get_ticks_usec() - phaseStart

	phaseStart = Time.get_ticks_usec() if _profileMetrics != null else 0
	_CommitTick(tick, snapshot, fixedDelta)
	if _profileMetrics != null:
		_profileMetrics.commitTickUsec += Time.get_ticks_usec() - phaseStart

	phaseStart = Time.get_ticks_usec() if _profileMetrics != null else 0
	_arrivalResolver.Resolve(tick, snapshot)
	if _profileMetrics != null:
		_profileMetrics.arrivalResolveUsec += Time.get_ticks_usec() - phaseStart

	return true


func Clear() -> void:
	_agents.clear()
	_agentIndexByUnitId.clear()
	_collisionResolver = CollisionResolver.new(_navigationService)
	_arrivalResolver = MovementArrivalResolver.new(_navigationService)
	_collisionResolver.SetProfileMetrics(_profileMetrics)
	_arrivalResolver.SetProfileMetrics(_profileMetrics)
	lastError = ""


func _CaptureTick() -> CollisionGroup:
	var tick: CollisionGroup = CollisionGroup.new()
	for agent: MovementAgent in _agents:
		var desiredPosition: Vector2 = agent.position
		if _CanAgentMove(agent):
			desiredPosition = agent.GetDesiredPosition()
		tick.AddAgent(agent, desiredPosition, agent.moveSpeed)
	return tick


func _CanAgentMove(agent: MovementAgent) -> bool:
	if _unitManager == null:
		return true
	var unit: Unit = _unitManager.GetUnit(agent.unitId)
	return (
		unit != null
		and (unit.fsm == null or unit.fsm.currentState != UnitFSM.State.IDLE)
	)


func _CommitTick(tick: CollisionGroup, snapshot: StageSnapshot, fixedDelta: float) -> void:
	for data: CollisionGroup.AgentData in tick.agents:
		data.agent.CommitMovement(data.nextPosition, fixedDelta)
		snapshot.UpdatePosition(data.unitId, data.nextPosition)


func _ValidateSnapshot(snapshot: StageSnapshot) -> bool:
	if snapshot.GetUnitCount() != _agents.size():
		lastError = "snapshot과 simulator의 유닛 수가 다릅니다."
		return false
	for agent: MovementAgent in _agents:
		if not snapshot.HasUnit(agent.unitId):
			lastError = "snapshot에 unitId %d가 없습니다." % agent.unitId
			return false
	return true


func _CanPlaceAgent(agent: MovementAgent, position: Vector2) -> bool:
	if _navigationService != null and not _navigationService.CanPlaceStatic(position, agent.halfSize):
		return false
	for other: MovementAgent in _agents:
		if other.unitId == agent.unitId:
			continue
		if MovementCollisionQuery.Overlaps(position, agent.halfSize, other.position, other.halfSize):
			return false
	return true


func _GetAgent(unitId: int) -> MovementAgent:
	var index: int = _agentIndexByUnitId.get(unitId, INVALID_INDEX)
	if index == INVALID_INDEX:
		return null
	return _agents[index]
