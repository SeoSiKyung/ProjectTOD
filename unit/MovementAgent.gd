extends RefCounted
class_name MovementAgent

var unitId: int = -1
var position: Vector2 = Vector2.ZERO
var moveSpeed: float = 0.0
var halfSize: int = 0
var lastVelocity: Vector2 = Vector2.ZERO
var _pathFollower: PathFollower = PathFollower.new()

func _init(pUnitId: int, pPosition: Vector2, pMoveSpeed: float, pHalfSize: int) -> void:
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
	_ClearPath()
	
func Stop() -> void:
	_ClearPath()
	
func SetPath(path: PackedVector2Array) -> void:
	_pathFollower.Set(path)
	_pathFollower.OnMovementCommitted(position, halfSize)
	
func _ClearPath() -> void:
	_pathFollower.ClearPath()
	lastVelocity = Vector2.ZERO
	
func HasPath() -> bool:
	return not _pathFollower.IsEmpty()
	
func GetDesiredPosition(fixedDt: float) -> Vector2:
	if fixedDt <= Math.EPSILON or moveSpeed <= 0:
		return position

	var maxStepDistance: float = moveSpeed * fixedDt
	return _pathFollower.GetDesiredPosition(position, maxStepDistance)

func CommitMovement(newPosition: Vector2, fixedDelta: float) -> void:
	var prevPosition: Vector2 = position
	position = newPosition

	if fixedDelta <= Math.EPSILON:
		lastVelocity = Vector2.ZERO
	else:
		lastVelocity = (position - prevPosition) / fixedDelta

	_pathFollower.OnMovementCommitted(position, halfSize)
