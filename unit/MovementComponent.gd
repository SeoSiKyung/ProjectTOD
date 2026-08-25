class_name MovementComponent
extends Node

enum MovementState {
	IDLE,
	MOVING,
}

const EPSILON: float = 0.000001

var moveSpeed: float:
	get:
		if unit == null:
			return 0.0

		return unit.move_speed
	set(value):
		if unit != null:
			unit.move_speed = value

var state: MovementState = MovementState.IDLE
var simVelocity: Vector2 = Vector2.ZERO
var activeMoveOrder: MoveOrder = null
var settledOrderId: int = -1
var unit: Unit = null
var _paused: bool = false

var _path: PackedVector2Array = PackedVector2Array()
var _pathIndex: int = 0
var _effectiveGoal: Vector2 = Vector2.ZERO


func BindUnit(p_unit: Unit) -> void:
	unit = p_unit


func IsMoving() -> bool:
	return state == MovementState.MOVING


func IsIdle() -> bool:
	return state == MovementState.IDLE


func IsPaused() -> bool:
	return _paused


func Pause() -> void:
	_paused = true
	simVelocity = Vector2.ZERO


func Resume() -> void:
	_paused = false


func HasPath() -> bool:
	return not _path.is_empty()


func BeginMoveOrder(order: MoveOrder, path: PackedVector2Array) -> void:
	if unit == null:
		push_error("MovementComponent에 unit이 없습니다.")
		return

	activeMoveOrder = order
	settledOrderId = -1
	_paused = false
	state = MovementState.MOVING
	simVelocity = Vector2.ZERO
	_SetPath(path)

	if _path.is_empty():
		_effectiveGoal = unit.position
		CompleteMoveOrder()
		return

	_effectiveGoal = _path[_path.size() - 1]


func ReplacePath(path: PackedVector2Array, effective_goal: Vector2) -> bool:
	if not IsMoving():
		return false

	if path.is_empty():
		return false

	_SetPath(path)
	_effectiveGoal = effective_goal
	return true


func ResetSimVelocity() -> void:
	simVelocity = Vector2.ZERO


func Stop() -> void:
	_paused = false
	activeMoveOrder = null
	settledOrderId = -1
	_path.clear()
	_pathIndex = 0
	simVelocity = Vector2.ZERO
	state = MovementState.IDLE


func CompleteMoveOrder() -> void:
	_paused = false
	var completed_order_id: int = -1

	if activeMoveOrder != null:
		completed_order_id = activeMoveOrder.orderId

	activeMoveOrder = null
	_path.clear()
	_pathIndex = 0
	simVelocity = Vector2.ZERO
	state = MovementState.IDLE
	settledOrderId = completed_order_id


func SyncPathProgress(max_tick_distance: float, navigation_service: NavigationService) -> void:
	if _paused:
		return

	if not IsMoving():
		return

	if _path.is_empty():
		return

	if unit == null:
		return

	var reach_distance: float = maxf(max_tick_distance * 1.5, 1.0)
	var corridor_distance: float = maxf(
		reach_distance * 3.0,
		maxf(unit.footprint_size.x, unit.footprint_size.y),
	)

	while _pathIndex < _path.size() - 1:
		var waypoint: Vector2 = _path[_pathIndex]
		var nextWaypoint: Vector2 = _path[_pathIndex + 1]
		var nextClear: bool = true

		if navigation_service != null:
			nextClear = navigation_service.SegmentClear(
				unit.position,
				nextWaypoint,
				unit.GetHalfSize(),
			)

		if unit.position.distance_to(waypoint) <= reach_distance:
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

		var t: float = ((unit.position - waypoint).dot(segment) / segmentLengthSquared)

		var clampedT: float = clampf(t, 0.0, 1.0)
		var closest: Vector2 = waypoint + segment * clampedT
		var lateralDistance: float = unit.position.distance_to(closest)

		var closerToNext: bool = (
			unit.position.distance_squared_to(nextWaypoint) < unit.position.distance_squared_to(
				waypoint
			)
		)

		if (t > 0.0 and closerToNext and lateralDistance <= corridor_distance and nextClear):
			_pathIndex += 1
			continue

		break


func GetCurrentWaypoint() -> Vector2:
	if _path.is_empty():
		return _effectiveGoal

	var index: int = clampi(_pathIndex, 0, _path.size() - 1)

	return _path[index]


func GetDesiredDirection() -> Vector2:
	if _paused:
		return Vector2.ZERO

	if not IsMoving():
		return Vector2.ZERO

	if _path.is_empty():
		return Vector2.ZERO

	var target: Vector2 = _path[_pathIndex]
	var delta: Vector2 = target - unit.position

	if (delta.length_squared() <= EPSILON and _pathIndex < _path.size() - 1):
		target = _path[_pathIndex + 1]
		delta = target - unit.position

	if delta.length_squared() <= EPSILON:
		return Vector2.ZERO

	return delta.normalized()


func GetEffectiveGoal() -> Vector2:
	return _effectiveGoal


func IsFinalLeg() -> bool:
	if _path.is_empty():
		return true

	return _pathIndex >= _path.size() - 1


func GetRemainingFinalDistance() -> float:
	if unit == null:
		return 0.0

	return unit.position.distance_to(_effectiveGoal)


func IsAtEffectiveGoal(tolerance: float) -> bool:
	if unit == null:
		return true

	return (unit.position.distance_to(_effectiveGoal) <= maxf(tolerance, EPSILON))


func WantsFinalTick(fixed_dt: float) -> bool:
	if _paused:
		return false

	if not IsMoving():
		return false

	if not IsFinalLeg():
		return false

	var normal_distance: float = moveSpeed * fixed_dt

	return (GetRemainingFinalDistance() <= normal_distance + EPSILON)


func GetDesiredVelocity(fixedDt: float) -> Vector2:
	if _paused:
		return Vector2.ZERO

	if not IsMoving():
		return Vector2.ZERO

	if unit == null:
		return Vector2.ZERO

	if fixedDt <= EPSILON:
		return Vector2.ZERO

	var direction: Vector2 = GetDesiredDirection()

	if direction == Vector2.ZERO:
		return Vector2.ZERO

	var waypoint: Vector2 = GetCurrentWaypoint()
	var remainingToWaypoint: float = unit.position.distance_to(waypoint)
	var normalDistance: float = moveSpeed * fixedDt

	if remainingToWaypoint <= normalDistance + EPSILON:
		if remainingToWaypoint <= EPSILON:
			return Vector2.ZERO

		return direction * (remainingToWaypoint / fixedDt)

	return direction * moveSpeed


func CommitSimulation(new_position: Vector2, new_velocity: Vector2, finish_order: bool) -> void:
	if _paused:
		simVelocity = Vector2.ZERO
		return

	unit.position = new_position

	if finish_order:
		CompleteMoveOrder()
		return

	simVelocity = new_velocity


func _SetPath(path: PackedVector2Array) -> void:
	_path = path
	_pathIndex = 0

	if unit == null:
		return

	while _pathIndex < _path.size() - 1:
		if (unit.position.distance_squared_to(_path[_pathIndex]) > EPSILON):
			break

		_pathIndex += 1
