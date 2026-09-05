class_name CollisionGroup
extends RefCounted


class AgentData:
	var agent: MovementAgent
	var unit: Unit
	var startPosition: Vector2
	var desiredPosition: Vector2
	var desiredDelta: Vector2
	var nextPosition: Vector2
	var speed: float
	var halfSize: int
	var idle: bool
	var commandId: int
	var slideDirection: Vector2
	var slideIdleIds: Array
	var currentIdleIds: Array


var agents: Array = []
var collisions: Array = []


func AddAgent(agent: MovementAgent, unit: Unit, startPosition: Vector2, desiredPosition: Vector2, nextPosition: Vector2, slideDirection: Vector2, slideIdleIds: Array) -> void:
	var data: AgentData = AgentData.new()

	data.agent = agent
	data.unit = unit
	data.startPosition = startPosition
	data.desiredPosition = desiredPosition
	data.desiredDelta = desiredPosition - startPosition
	data.nextPosition = nextPosition
	data.speed = agent.moveSpeed
	data.halfSize = agent.halfSize
	data.idle = unit != null and unit.fsm != null and unit.fsm.currentState == UnitFSM.State.IDLE
	data.commandId = agent.moveCommandId
	data.slideDirection = slideDirection
	data.slideIdleIds = slideIdleIds.duplicate()
	data.currentIdleIds = []

	if data.idle:
		data.desiredPosition = startPosition
		data.desiredDelta = Vector2.ZERO
		data.nextPosition = startPosition

	agents.append(data)


func AddCollision(firstUnitId: int, secondUnitId: int) -> void:
	collisions.append(Vector2i(firstUnitId, secondUnitId))
