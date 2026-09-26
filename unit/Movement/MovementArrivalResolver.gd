class_name MovementArrivalResolver
extends RefCounted

const SETTLE_DELAY_TICKS: int = 10
const PROGRESS_DISTANCE_RATIO: float = 0.10
const CONTACT_SLOP: float = 0.05
const EPSILON: float = 0.001

class CommandArea:
	var radius: float = 0.0

var _navigationService: NavigationService
var _commandAreas: Dictionary[int, CommandArea] = {}
var _profileMetrics: MovementProfileMetrics
var _nearbyUnitIdBuffer: PackedInt32Array = []


func _init(navigationService: NavigationService) -> void:
	_navigationService = navigationService


func SetProfileMetrics(metrics: MovementProfileMetrics) -> void:
	_profileMetrics = metrics


func Resolve(tick: CollisionGroup, snapshot: StageSnapshot) -> void:
	_BuildCommandAreas(tick)
	var pendingAgents: Array[MovementAgent] = []
	for data: CollisionGroup.AgentData in tick.agents:
		if _ShouldSettle(data, tick, snapshot):
			pendingAgents.append(data.agent)
	for agent: MovementAgent in pendingAgents:
		agent.Settle()
		if _profileMetrics != null:
			_profileMetrics.settledAgentCount += 1


func _BuildCommandAreas(tick: CollisionGroup) -> void:
	_commandAreas.clear()
	for data: CollisionGroup.AgentData in tick.agents:
		var agent: MovementAgent = data.agent
		if agent.moveCommandId < 0:
			continue
		if not _commandAreas.has(agent.moveCommandId):
			_commandAreas[agent.moveCommandId] = CommandArea.new()
		var area: CommandArea = _commandAreas[agent.moveCommandId]
		var contactDistance: float = _GetContactDistance(agent)
		area.radius += (float(agent.halfSize) * 2.0 + contactDistance) * sqrt(2.0)
	for area: CommandArea in _commandAreas.values():
		area.radius = maxf(area.radius, EPSILON)


func _ShouldSettle(
	data: CollisionGroup.AgentData,
	tick: CollisionGroup,
	snapshot: StageSnapshot,
) -> bool:
	var agent: MovementAgent = data.agent
	if agent.isSettled:
		return false
	if not _CanEvaluate(data) or not _IsInsideArrivalArea(agent):
		agent.ResetSettleProgress()
		return false
	if _FootprintContainsGoal(agent):
		return _HasClearStaticRoute(agent.position, agent.moveTarget, agent.halfSize)
	agent.TrackGoalProgress(maxf(EPSILON, agent.moveSpeed * PROGRESS_DISTANCE_RATIO))
	if agent.settleTickCount < SETTLE_DELAY_TICKS:
		return false
	if not _HasSettledBlocker(agent, tick, snapshot):
		return false
	if not _HasClearStaticRoute(agent.position, agent.moveTarget, agent.halfSize):
		agent.ResetSettleProgress()
		return false
	return true


func _CanEvaluate(data: CollisionGroup.AgentData) -> bool:
	var agent: MovementAgent = data.agent
	return (
		agent.moveCommandId >= 0
		and not agent.isPaused
		and agent.moveSpeed > 0.0
		and agent.moveTarget.is_finite()
		and (data.desiredPosition != data.startPosition or not agent.HasPath())
	)


func _IsInsideArrivalArea(agent: MovementAgent) -> bool:
	var area: CommandArea = _commandAreas[agent.moveCommandId]
	var radius: float = maxf(agent.arrivalRadius, area.radius)
	return agent.position.distance_squared_to(agent.moveTarget) <= radius * radius


func _FootprintContainsGoal(agent: MovementAgent) -> bool:
	var extent: float = float(agent.halfSize) + EPSILON
	return (
		absf(agent.position.x - agent.moveTarget.x) <= extent
		and absf(agent.position.y - agent.moveTarget.y) <= extent
	)


func _HasSettledBlocker(
	agent: MovementAgent,
	tick: CollisionGroup,
	snapshot: StageSnapshot,
) -> bool:
	var contactDistance: float = _GetContactDistance(agent)
	var searchExtent: Vector2 = Vector2.ONE * (float(agent.halfSize) + contactDistance)
	var direction: Vector2 = agent.position.direction_to(agent.moveTarget)
	var nearbyUnitCount: int = snapshot.FindUnitIdsInRect(
		agent.position,
		searchExtent,
		_nearbyUnitIdBuffer,
	)
	for index: int in nearbyUnitCount:
		var otherId: int = _nearbyUnitIdBuffer[index]
		var otherData: CollisionGroup.AgentData = tick.GetAgent(otherId)
		if otherData == null or otherId == agent.unitId:
			continue
		var other: MovementAgent = otherData.agent
		if not _IsCompatibleAnchor(agent, other):
			continue
		var distance: float = MovementCollisionQuery.FirstContactDistance(
			agent.position, direction, other.position, float(agent.halfSize + other.halfSize),
		)
		if distance > contactDistance:
			continue
		if _HasClearStaticRoute(agent.position, other.position, agent.halfSize):
			return true
	return false


func _IsCompatibleAnchor(agent: MovementAgent, other: MovementAgent) -> bool:
	return (
		other.isSettled
		and other.moveCommandId == agent.moveCommandId
		and other.moveTarget.distance_squared_to(agent.moveTarget) <= EPSILON * EPSILON
		and _IsInsideArrivalArea(other)
	)


func _GetContactDistance(agent: MovementAgent) -> float:
	return agent.moveSpeed * CollisionResolver.MIN_SPEED_RATIO + CONTACT_SLOP


func _HasClearStaticRoute(start: Vector2, end: Vector2, halfSize: int) -> bool:
	return _navigationService == null or _navigationService.SegmentClear(start, end, halfSize)
