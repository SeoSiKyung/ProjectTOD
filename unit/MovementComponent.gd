class_name MovementComponent
extends Node

enum MovementState {
	IDLE,
	MOVING,
}
const EPSILON: float = 0.000001

var moveSpeed: float:
	get:
		if _unit == null:
			return 0.0

		return _unit.moveSpeed
	set(value):
		if _unit != null:
			_unit.moveSpeed = value

var simVelocity: Vector2 = Vector2.ZERO
var curOrder: MoveOrder = null

var _unit: Unit = null
var _state: MovementState = MovementState.IDLE
var _paused: bool = false
var _path: PackedVector2Array = PackedVector2Array()
var _pathIndex: int = 0
var _goal: Vector2 = Vector2.ZERO

func Init(unit: Unit) -> void:
	_BindUnit(unit)

func _BindUnit(unit: Unit) -> void:
	_unit = unit

func Pause() -> void:
	_paused = true
	simVelocity = Vector2.ZERO

func Resume() -> void:
	_paused = false
	
func IsMoving() -> bool:
	return _state == MovementState.MOVING

func IsIdle() -> bool:
	return _state == MovementState.IDLE

func IsPaused() -> bool:
	return _paused

func HasPath() -> bool:
	return not _path.is_empty()

func StartOrder(order: MoveOrder, path: PackedVector2Array) -> void:
	if _unit == null:
		push_error("MovementComponent에 unit이 없습니다.")
		return
	
	_EnterMoving(order, path)
	_SetGoal()

func _EnterMoving(order: MoveOrder, path: PackedVector2Array) -> void:
	curOrder = order
	_paused = false
	_state = MovementState.MOVING
	simVelocity = Vector2.ZERO
	_SetPath(path)

func _SetPath(path: PackedVector2Array) -> void:
	_path = path
	_pathIndex = 0

	if _unit == null:
		return

	while _pathIndex < _path.size() - 1:
		if _unit.position.distance_squared_to(_path[_pathIndex]) > EPSILON:
			break

		_pathIndex += 1

func _SetGoal() -> void:
	if _path.is_empty():
		_goal = _unit.position

	_goal = _path[_path.size() - 1]

func ReplacePath(path: PackedVector2Array) -> bool:
	if not IsMoving():
		return false
	if path.is_empty():
		return false

	_SetPath(path)
	return true
	
func ResetSimVelocity() -> void:
	simVelocity = Vector2.ZERO

func Stop() -> void:
	_enterIdle()

func _enterIdle() -> void:
	_paused = false
	curOrder = null
	_path.clear()
	_pathIndex = 0
	simVelocity = Vector2.ZERO
	_state = MovementState.IDLE

func SyncPathProgress(maxTickDistance: float, navigationService: NavigationService) -> void:
	if not _CanSync():
		return

	var reachDistance: float = maxf(maxTickDistance * 1.5, 1.0)
	var corridorDistance: float = maxf(
		reachDistance * 3.0,
		maxf(_unit.footprintSize.x, _unit.footprintSize.y),
	)

	while _pathIndex < _path.size() - 1:
		var waypoint: Vector2 = _path[_pathIndex]
		var nextWaypoint: Vector2 = _path[_pathIndex + 1]
		var nextClear: bool = true

		if navigationService != null:
			nextClear = navigationService.SegmentClear(
				_unit.position,
				nextWaypoint,
				_unit.GetHalfSize(),
			)

		if _unit.position.distance_to(waypoint) <= reachDistance:
			if nextClear:
				_pathIndex += 1
				continue

			break

		var segment: Vector2 = nextWaypoint - waypoint
		var segmentLengthSquared: float = segment.length_squared()

		if segmentLengthSquared <= EPSILON:
			if nextClear:
				_pathIndex += 1
				continue

			break

		var t: float = ((_unit.position - waypoint).dot(segment) / segmentLengthSquared)

		var clampedT: float = clampf(t, 0.0, 1.0)
		var closest: Vector2 = waypoint + segment * clampedT
		var lateralDistance: float = _unit.position.distance_to(closest)

		var closerToNext: bool = (
			_unit.position.distance_squared_to(nextWaypoint) < _unit.position.distance_squared_to(
				waypoint
			)
		)

		if (t > 0.0 and closerToNext and lateralDistance <= corridorDistance and nextClear):
			_pathIndex += 1
			continue

		break
		
func _CanSync() -> bool:
	if _paused:
		return false
	if not IsMoving():
		return false
	if _path.is_empty():
		return false
		
	return true

func GetCurrentWaypoint() -> Vector2:
	if _path.is_empty():
		return _goal

	return _path[_pathIndex]

func GetDesiredDirection() -> Vector2:
	if not _CanSync():
		return Vector2.ZERO

	var target: Vector2 = _path[_pathIndex]
	var delta: Vector2 = target - _unit.position

	if delta.length_squared() <= EPSILON and _pathIndex < _path.size() - 1:
		target = _path[_pathIndex + 1]
		delta = target - _unit.position

	if delta.length_squared() <= EPSILON:
		return Vector2.ZERO

	return delta.normalized()

func GetEffectiveGoal() -> Vector2:
	return _goal

func IsFinalLeg() -> bool:
	if _path.is_empty():
		return true

	return _pathIndex >= _path.size() - 1

func GetRemainingFinalDistance() -> float:
	if _unit == null:
		return 0.0

	return _unit.position.distance_to(_goal)

func IsAtEffectiveGoal(tolerance: float) -> bool:
	if _unit == null:
		return true

	return _unit.position.distance_to(_goal) <= maxf(tolerance, EPSILON)

func WantsFinalTick(fixedDt: float) -> bool:
	if _paused:
		return false

	if not IsMoving():
		return false

	if not IsFinalLeg():
		return false

	var normalDistance: float = moveSpeed * fixedDt

	return GetRemainingFinalDistance() <= normalDistance + EPSILON

func GetDesiredVelocity(fixedDt: float) -> Vector2:
	if _paused:
		return Vector2.ZERO

	if not IsMoving():
		return Vector2.ZERO

	if _unit == null:
		return Vector2.ZERO

	if fixedDt <= EPSILON:
		return Vector2.ZERO

	var direction: Vector2 = GetDesiredDirection()

	if direction == Vector2.ZERO:
		return Vector2.ZERO

	var waypoint: Vector2 = GetCurrentWaypoint()
	var remainingToWaypoint: float = _unit.position.distance_to(waypoint)
	var normalDistance: float = moveSpeed * fixedDt

	if remainingToWaypoint <= normalDistance + EPSILON:
		if remainingToWaypoint <= EPSILON:
			return Vector2.ZERO

		return direction * (remainingToWaypoint / fixedDt)

	return direction * moveSpeed

func CommitSimulation(newPosition: Vector2, newVelocity: Vector2, finishOrder: bool) -> void:
	if _paused:
		simVelocity = Vector2.ZERO
		return

	_unit.position = newPosition

	if finishOrder:
		Stop()
		return

	simVelocity = newVelocity

func _VelocityToAngle(velocity: Vector2) -> int:
	if velocity == Vector2.ZERO:
		return -1
	return posmod(roundi(velocity.angle() * 16.0 / TAU), 16)
