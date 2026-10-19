class_name MovementSimulator
extends RefCounted

const INVALID_INDEX: int = -1
const EPSILON: float = 0.00001

var lastError: String = ""
var enablePathRebuildRecovery: bool = true
var _navigationService: NavigationService
var _unitManager: UnitManager
var _collisionResolver: CollisionResolver
var _arrivalResolver: MovementArrivalResolver
var _profileMetrics: MovementProfileMetrics

var capturePathRebuildTiming: bool = false
var lastPathRebuildMetrics: NavigationProfileMetrics
var lastPathRebuildUsec: int = 0
var lastPathRebuildUnitId: int = -1
var lastPathRebuildCommandId: int = -1
var lastPathRebuildRevision: int = -1
var lastPathRebuildStart: Vector2
var lastPathRebuildTarget: Vector2
var lastPathRebuildHalfSize: int = 0
var lastPathRebuildSucceeded: bool = false
var lastPathRebuildWaypointCount: int = 0

# Benchmark에서만 마지막 틱을 보관한다. 유닛별 매 틱 로그를 만들지 않는다.
var captureDiagnostics: bool = false
var _lastDiagnosticTick: CollisionGroup
var _lastDiagnosticTickCommitted: bool = false
var _agents: Array[MovementAgent] = []
var _agentIndexByUnitId: Dictionary[int, int] = { }


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
	if agent.moveSpeed < 0:
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


func SetMoveSpeed(unitId: int, moveSpeed: int) -> bool:
	if moveSpeed < 0:
		return false

	var agent: MovementAgent = _GetAgent(unitId)
	if agent == null:
		return false

	agent.moveSpeed = moveSpeed
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
	if capturePathRebuildTiming:
		lastPathRebuildMetrics = null
	if captureDiagnostics:
		_lastDiagnosticTick = null
		_lastDiagnosticTickCommitted = false
	lastError = ""
	if snapshot == null or not is_finite(fixedDelta) or fixedDelta <= EPSILON:
		lastError = "유효한 snapshot과 양수 fixedDelta가 필요합니다."
		return false
	if not _ValidateSnapshot(snapshot):
		return false

	if _profileMetrics != null:
		_profileMetrics.simulationTickCount += 1

	if enablePathRebuildRecovery:
		var rebuildStart: int = Time.get_ticks_usec() if _profileMetrics != null else 0
		_RecoverInvalidPath()
		if _profileMetrics != null:
			_profileMetrics.pathRebuildUsec += Time.get_ticks_usec() - rebuildStart

	var phaseStart: int = Time.get_ticks_usec() if _profileMetrics != null else 0
	var tick: CollisionGroup = _CaptureTick()
	if captureDiagnostics:
		_lastDiagnosticTick = tick
		_lastDiagnosticTickCommitted = false
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
	if captureDiagnostics:
		_lastDiagnosticTickCommitted = true
	if _profileMetrics != null:
		_profileMetrics.commitTickUsec += Time.get_ticks_usec() - phaseStart

	phaseStart = Time.get_ticks_usec() if _profileMetrics != null else 0
	_arrivalResolver.Resolve(tick, snapshot)
	if _profileMetrics != null:
		_profileMetrics.arrivalResolveUsec += Time.get_ticks_usec() - phaseStart

	return true


func Clear() -> void:
	_lastDiagnosticTick = null
	_lastDiagnosticTickCommitted = false
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
		var canMove: bool = (
			_CanAgentMove(agent) and not agent.isPaused and agent.moveSpeed > 0 and agent.HasPath()
		)
		if canMove:
			desiredPosition = agent.GetDesiredPosition()
		tick.AddAgent(agent, desiredPosition, agent.moveSpeed, canMove)
	return tick


func _CanAgentMove(agent: MovementAgent) -> bool:
	if _unitManager == null:
		return true
	var unit: Unit = _unitManager.GetUnit(agent.unitId)
	return (unit != null and (unit.fsm == null or unit.fsm.currentState != UnitFSM.State.IDLE))


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
	if (
		_navigationService != null
		and not _navigationService.CanPlaceStatic(position, agent.halfSize)
	):
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


func GetDiagnosticState(unitId: int) -> Dictionary:
	var agent: MovementAgent = _GetAgent(unitId)
	if agent == null:
		return { }
	var state: Dictionary = agent.GetDiagnosticState()
	state["tick_available"] = false
	if _lastDiagnosticTick == null:
		return state
	var data: CollisionGroup.AgentData = _lastDiagnosticTick.GetAgent(unitId)
	if data == null:
		return state
	var desiredDelta: Vector2 = data.desiredPosition - data.startPosition
	var committedDelta: Vector2 = data.nextPosition - data.startPosition if _lastDiagnosticTickCommitted else Vector2.ZERO
	state.merge(
		{
			"tick_available": true,
			"tick_committed": _lastDiagnosticTickCommitted,
			"tick_start_position": [data.startPosition.x, data.startPosition.y],
			"desired_delta": [desiredDelta.x, desiredDelta.y],
			"actual_delta": [committedDelta.x, committedDelta.y],
			"can_move_this_tick": data.canMove,
		},
		true,
	)
	return state


func _RecoverInvalidPath() -> void:
	if _navigationService == null or not _navigationService.IsReady():
		return
	for agent: MovementAgent in _agents:
		if not _CanAgentMove(agent) or not agent.NeedsPathRebuild():
			continue
		if agent.pathRebuildAttempted:
			agent.ApplyRebuiltPath(PackedVector2Array())
			if _profileMetrics != null:
				_profileMetrics.pathRebuildFailures += 1
			continue
		if _profileMetrics != null:
			_profileMetrics.pathRebuildRequests += 1
		var previousMetrics: NavigationProfileMetrics
		if capturePathRebuildTiming:
			previousMetrics = _navigationService.GetProfileMetrics()
			lastPathRebuildMetrics = NavigationProfileMetrics.new()
			lastPathRebuildMetrics.capturePortalBatchDetails = true
			lastPathRebuildMetrics.portalBatchTick = Engine.get_physics_frames()
			lastPathRebuildUnitId = agent.unitId
			lastPathRebuildCommandId = agent.moveCommandId
			lastPathRebuildRevision = agent.movementRevision
			lastPathRebuildStart = agent.position
			lastPathRebuildTarget = agent.moveTarget
			lastPathRebuildHalfSize = agent.halfSize
			_navigationService.SetProfileMetrics(lastPathRebuildMetrics)
		var rebuildStart: int = Time.get_ticks_usec() if capturePathRebuildTiming else 0
		var path: PackedVector2Array = _navigationService.RebuildPath(
			agent.position,
			agent.moveTarget,
			agent.halfSize,
		)
		if capturePathRebuildTiming:
			lastPathRebuildUsec = Time.get_ticks_usec() - rebuildStart
			_navigationService.SetProfileMetrics(previousMetrics)
		if (
			not path.is_empty()
			and path[path.size() - 1].distance_squared_to(agent.moveTarget) > Math.EPSILON
		):
			path = PackedVector2Array()
		agent.ApplyRebuiltPath(path)
		if capturePathRebuildTiming:
			lastPathRebuildWaypointCount = path.size()
			lastPathRebuildSucceeded = true
		if path.is_empty() or agent.NeedsPathRebuild():
			if capturePathRebuildTiming:
				lastPathRebuildSucceeded = false
			if not path.is_empty():
				agent.ApplyRebuiltPath(PackedVector2Array())
			if _profileMetrics != null:
				_profileMetrics.pathRebuildFailures += 1

		break
