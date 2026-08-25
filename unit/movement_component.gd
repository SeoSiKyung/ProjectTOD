class_name MovementComponent
extends Node

enum MovementState {
	IDLE,
	MOVING,
}

const EPSILON: float = 0.000001

var move_speed: float:
	get:
		if unit == null:
			return 0.0

		return unit.move_speed
	set(value):
		if unit != null:
			unit.move_speed = value

var state: MovementState = MovementState.IDLE
var sim_velocity: Vector2 = Vector2.ZERO
var active_move_order: MoveOrder = null
var settled_order_id: int = -1
var unit: Unit = null
var _paused: bool = false

var _path: PackedVector2Array = PackedVector2Array()
var _path_index: int = 0
var _effective_goal: Vector2 = Vector2.ZERO


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
	sim_velocity = Vector2.ZERO


func Resume() -> void:
	_paused = false


func HasPath() -> bool:
	return not _path.is_empty()


func BeginMoveOrder(order: MoveOrder, path: PackedVector2Array) -> void:
	if unit == null:
		push_error("MovementComponent에 unit이 없습니다.")
		return

	active_move_order = order
	settled_order_id = -1
	_paused = false
	state = MovementState.MOVING
	sim_velocity = Vector2.ZERO
	_setPath(path)

	if _path.is_empty():
		_effective_goal = unit.position
		CompleteMoveOrder()
		return

	_effective_goal = _path[_path.size() - 1]


func ReplacePath(path: PackedVector2Array, effective_goal: Vector2) -> bool:
	if not IsMoving():
		return false

	if path.is_empty():
		return false

	_setPath(path)
	_effective_goal = effective_goal
	return true


func ResetSimVelocity() -> void:
	sim_velocity = Vector2.ZERO


func Stop() -> void:
	_paused = false
	active_move_order = null
	settled_order_id = -1
	_path.clear()
	_path_index = 0
	sim_velocity = Vector2.ZERO
	state = MovementState.IDLE


func CompleteMoveOrder() -> void:
	_paused = false
	var completed_order_id: int = -1

	if active_move_order != null:
		completed_order_id = active_move_order.order_id

	active_move_order = null
	_path.clear()
	_path_index = 0
	sim_velocity = Vector2.ZERO
	state = MovementState.IDLE
	settled_order_id = completed_order_id


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

	while _path_index < _path.size() - 1:
		var waypoint: Vector2 = _path[_path_index]
		var next_waypoint: Vector2 = _path[_path_index + 1]
		var next_clear: bool = true

		if navigation_service != null:
			next_clear = navigation_service.SegmentClear(
				unit.position,
				next_waypoint,
				unit.getHalfSize(),
			)

		if unit.position.distance_to(waypoint) <= reach_distance:
			if next_clear:
				_path_index += 1
				continue

			break

		var segment: Vector2 = next_waypoint - waypoint
		var segment_length_squared: float = segment.length_squared()

		if segment_length_squared <= EPSILON:
			if next_clear:
				_path_index += 1
				continue

			break

		var t: float = ((unit.position - waypoint).dot(segment) / segment_length_squared)

		var clamped_t: float = clampf(t, 0.0, 1.0)
		var closest: Vector2 = waypoint + segment * clamped_t
		var lateral_distance: float = unit.position.distance_to(closest)

		var closer_to_next: bool = (
			unit.position.distance_squared_to(next_waypoint) < unit.position.distance_squared_to(
				waypoint
			)
		)

		if (t > 0.0 and closer_to_next and lateral_distance <= corridor_distance and next_clear):
			_path_index += 1
			continue

		break


func GetCurrentWaypoint() -> Vector2:
	if _path.is_empty():
		return _effective_goal

	var index: int = clampi(_path_index, 0, _path.size() - 1)

	return _path[index]


func GetDesiredDirection() -> Vector2:
	if _paused:
		return Vector2.ZERO

	if not IsMoving():
		return Vector2.ZERO

	if _path.is_empty():
		return Vector2.ZERO

	var target: Vector2 = _path[_path_index]
	var delta: Vector2 = target - unit.position

	if (delta.length_squared() <= EPSILON and _path_index < _path.size() - 1):
		target = _path[_path_index + 1]
		delta = target - unit.position

	if delta.length_squared() <= EPSILON:
		return Vector2.ZERO

	return delta.normalized()


func GetEffectiveGoal() -> Vector2:
	return _effective_goal


func IsFinalLeg() -> bool:
	if _path.is_empty():
		return true

	return _path_index >= _path.size() - 1


func GetRemainingFinalDistance() -> float:
	if unit == null:
		return 0.0

	return unit.position.distance_to(_effective_goal)


func IsAtEffectiveGoal(tolerance: float) -> bool:
	if unit == null:
		return true

	return (unit.position.distance_to(_effective_goal) <= maxf(tolerance, EPSILON))


func WantsFinalTick(fixed_dt: float) -> bool:
	if _paused:
		return false

	if not IsMoving():
		return false

	if not IsFinalLeg():
		return false

	var normal_distance: float = move_speed * fixed_dt

	return (GetRemainingFinalDistance() <= normal_distance + EPSILON)


func GetDesiredVelocity(fixed_dt: float) -> Vector2:
	if _paused:
		return Vector2.ZERO

	if not IsMoving():
		return Vector2.ZERO

	if unit == null:
		return Vector2.ZERO

	if fixed_dt <= EPSILON:
		return Vector2.ZERO

	var direction: Vector2 = GetDesiredDirection()

	if direction == Vector2.ZERO:
		return Vector2.ZERO

	var waypoint: Vector2 = GetCurrentWaypoint()
	var remaining_to_waypoint: float = unit.position.distance_to(waypoint)
	var normal_distance: float = move_speed * fixed_dt

	if remaining_to_waypoint <= normal_distance + EPSILON:
		if remaining_to_waypoint <= EPSILON:
			return Vector2.ZERO

		return direction * (remaining_to_waypoint / fixed_dt)

	return direction * move_speed


func CommitSimulation(new_position: Vector2, new_velocity: Vector2, finish_order: bool) -> void:
	if _paused:
		sim_velocity = Vector2.ZERO
		return

	unit.position = new_position

	if finish_order:
		CompleteMoveOrder()
		return

	sim_velocity = new_velocity


func _setPath(path: PackedVector2Array) -> void:
	_path = path
	_path_index = 0

	if unit == null:
		return

	while _path_index < _path.size() - 1:
		if (unit.position.distance_squared_to(_path[_path_index]) > EPSILON):
			break

		_path_index += 1
