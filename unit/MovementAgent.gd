extends RefCounted
class_name MovementAgent

var unit: Unit = null
var position: Vector2 = Vector2.ZERO
var lastVelocity: Vector2 = Vector2.ZERO
var pathFollower: PathFollower = null

func _init(pUnit: Unit, pPosition: Vector2) -> void:
	unit = pUnit
	position = pPosition
	pathFollower = PathFollower.new(unit)
	
func Move(newPosition: Vector2, fixedDt: float) -> void:
	var prevPosition: Vector2 = position
	position = newPosition
	
	if fixedDt <= Math.EPSILON:
		lastVelocity = Vector2.ZERO
	else:
		lastVelocity = (position - prevPosition) / fixedDt
	unit.position = position
	
func Teleport(newPosition: Vector2) -> void:
	position = newPosition
	lastVelocity = Vector2.ZERO
	unit.position = position
	
func Stop() -> void:
	lastVelocity = Vector2.ZERO
