class_name CollisionGroup
extends RefCounted

class AgentData:
	var agent: MovementAgent
	var unitId: int
	var startPosition: Vector2
	var desiredPosition: Vector2
	var nextPosition: Vector2
	var halfSize: int
	var maxStepDistance: float
	var canMove: bool = true


var agents: Array[AgentData] = []
var _agentsById: Dictionary[int, AgentData] = {}


func AddAgent(
	agent: MovementAgent,
	desiredPosition: Vector2,
	maxStepDistance: float,
	canMove: bool = true,
) -> void:
	var data: AgentData = AgentData.new()
	data.agent = agent
	data.unitId = agent.unitId
	data.startPosition = agent.position
	data.desiredPosition = desiredPosition
	data.nextPosition = agent.position
	data.halfSize = agent.halfSize
	data.maxStepDistance = maxStepDistance
	data.canMove = canMove
	agents.append(data)
	_agentsById[data.unitId] = data


func GetAgent(unitId: int) -> AgentData:
	return _agentsById.get(unitId)
