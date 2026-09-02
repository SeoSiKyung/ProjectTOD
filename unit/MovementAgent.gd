extends RefCounted
class_name MovementAgent

var unitId: int = -1
var position: Vector2 = Vector2.ZERO
var moveSpeed: int = 0
var halfSize: int = 0
var lastVelocity: Vector2 = Vector2.ZERO
var _pathFollower: PathFollower = PathFollower.new()

func _init(pUnitId: int, pPosition: Vector2, pMoveSpeed: int, pHalfSize: int) -> void:
	unitId = pUnitId
	position = pPosition
	moveSpeed = pMoveSpeed
	halfSize = pHalfSize
	
func Move(newPosition: Vector2, fixedDt: float) -> void:
	var prevPosition: Vector2 = position
	position = newPosition
	
	if fixedDt <= Math.EPSILON:
		lastVelocity = Vector2.ZERO
	else:
		lastVelocity = (position - prevPosition) / fixedDt
	
func Teleport(newPosition: Vector2) -> void:
	position = newPosition
	lastVelocity = Vector2.ZERO
	
func Stop() -> void:
	lastVelocity = Vector2.ZERO
	
func SetPath(path: PackedVector2Array) -> void:
	_pathFollower.Set(path)
	
func GetDesiredPosition() -> Vector2:
	return _pathFollower.GetDesirePosition(position, moveSpeed)
