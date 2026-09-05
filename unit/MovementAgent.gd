extends RefCounted
class_name MovementAgent

var unitId: int = -1
var position: Vector2 = Vector2.ZERO
var moveSpeed: float = 0.0
var halfSize: int = 0
var lastVelocity: Vector2 = Vector2.ZERO
var moveCommandId: int = UnitCommand.INVALID_COMMAND_ID
var moveTarget: Vector2 = Vector2.ZERO
var arrivalRadius: float = 0.0
var settleTickCount: int = 0
var isSettled: bool = false
var isPaused: bool = false
var _pathFollower: PathFollower

func _init(pUnitId: int, pPosition: Vector2, pMoveSpeed: float, pHalfSize: int) -> void:
	unitId = pUnitId
	position = pPosition
	moveSpeed = pMoveSpeed
	halfSize = pHalfSize
	_pathFollower = PathFollower.new(halfSize)
	
func Move(newPosition: Vector2, fixedDt: float) -> void:
	var prevPosition: Vector2 = position
	position = newPosition
	
	if fixedDt <= Math.EPSILON:
		lastVelocity = Vector2.ZERO
	else:
		lastVelocity = (position - prevPosition) / fixedDt
	
func Teleport(newPosition: Vector2) -> void:
	position = newPosition
	_ResetMoveCommand()
	_ClearPath()
		
func Stop() -> void:
	_ResetMoveCommand()
	_ClearPath()


func Pause() -> void:
	isPaused = true
	lastVelocity = Vector2.ZERO


func Resume() -> void:
	isPaused = false
		
func SetPath(path: PackedVector2Array) -> void:
	_ResetMoveCommand()
	_SetPath(path)


func BeginMove(
	path: PackedVector2Array,
	commandId: int,
	target: Vector2,
	pArrivalRadius: float,
) -> void:
	moveCommandId = commandId
	moveTarget = target
	arrivalRadius = maxf(pArrivalRadius, 0.0)
	settleTickCount = 0
	isSettled = false
	isPaused = false
	_SetPath(path)


func Settle() -> void:
	if moveCommandId < 0:
		return

	isSettled = true
	settleTickCount = 0
	_ClearPath()


func ResetSettleProgress() -> void:
	settleTickCount = 0


func AdvanceSettleProgress() -> void:
	settleTickCount += 1


func _SetPath(path: PackedVector2Array) -> void:
	_pathFollower.SetPath(path, position)
	_pathFollower.OnMovementCommitted(position)


func _ResetMoveCommand() -> void:
	moveCommandId = UnitCommand.INVALID_COMMAND_ID
	moveTarget = Vector2.ZERO
	arrivalRadius = 0.0
	settleTickCount = 0
	isSettled = false
	isPaused = false
	
func _ClearPath() -> void:
	_pathFollower.ClearPath()
	lastVelocity = Vector2.ZERO
	
func HasPath() -> bool:
	return not _pathFollower.IsEmpty()
	
func GetDesiredPosition(fixedDt: float) -> Vector2:
	if isPaused or fixedDt <= Math.EPSILON or moveSpeed <= 0:
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

	_pathFollower.OnMovementCommitted(position)
