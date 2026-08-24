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
var unit: Unit = null
var _paused: bool = false

var _path: PackedVector2Array = PackedVector2Array()
var _path_index: int = 0
var _effective_goal: Vector2 = Vector2.ZERO


func bind_unit(p_unit: Unit) -> void:
	unit = p_unit


func is_moving() -> bool:
	return state == MovementState.MOVING


func is_idle() -> bool:
	return state == MovementState.IDLE


func is_paused() -> bool:
	return _paused


func pause() -> void:
	_paused = true
	sim_velocity = Vector2.ZERO


func resume() -> void:
	_paused = false


func begin_move_order(
	order: MoveOrder,
	path: PackedVector2Array
) -> void:
	if unit == null:
		push_error("MovementComponent에 unit이 없습니다.")
		return

	active_move_order = order
	_paused = false
	state = MovementState.MOVING
	sim_velocity = Vector2.ZERO
	_set_path(path)

	if _path.is_empty():
		_effective_goal = unit.position
		complete_move_order()
		return

	_effective_goal = _path[_path.size() - 1]


func replace_path(
	path: PackedVector2Array,
	effective_goal: Vector2
) -> bool:
	if not is_moving():
		return false

	if path.is_empty():
		return false

	_set_path(path)
	_effective_goal = effective_goal
	return true


func reset_sim_velocity() -> void:
	sim_velocity = Vector2.ZERO


func stop() -> void:
	_paused = false
	active_move_order = null
	_path.clear()
	_path_index = 0
	sim_velocity = Vector2.ZERO
	state = MovementState.IDLE


func complete_move_order() -> void:
	_paused = false
	active_move_order = null
	_path.clear()
	_path_index = 0
	sim_velocity = Vector2.ZERO
	state = MovementState.IDLE


func sync_path_progress(
	max_tick_distance: float,
	navigation_service: NavigationService
) -> void:
	if _paused:
		return

	if not is_moving():
		return

	if _path.is_empty():
		return

	if unit == null:
		return

	var reach_distance: float = maxf(max_tick_distance * 1.5, 1.0)
	var corridor_distance: float = maxf(
		reach_distance * 3.0,
		maxf(unit.footprint_size.x, unit.footprint_size.y)
	)

	while _path_index < _path.size() - 1:
		var waypoint: Vector2 = _path[_path_index]
		var next_waypoint: Vector2 = _path[_path_index + 1]
		var next_clear: bool = true

		if navigation_service != null:
			next_clear = navigation_service.segment_clear(
				unit.position,
				next_waypoint,
				unit.get_half_size()
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

		var t: float = (
			(unit.position - waypoint).dot(segment)
			/ segment_length_squared
		)

		var clamped_t: float = clampf(t, 0.0, 1.0)
		var closest: Vector2 = waypoint + segment * clamped_t
		var lateral_distance: float = unit.position.distance_to(closest)

		var closer_to_next: bool = (
			unit.position.distance_squared_to(next_waypoint)
			< unit.position.distance_squared_to(waypoint)
		)

		if (
			t > 0.0
			and closer_to_next
			and lateral_distance <= corridor_distance
			and next_clear
		):
			_path_index += 1
			continue

		break


func get_current_waypoint() -> Vector2:
	if _path.is_empty():
		return _effective_goal

	var index: int = clampi(
		_path_index,
		0,
		_path.size() - 1
	)

	return _path[index]


func get_desired_direction() -> Vector2:
	if _paused:
		return Vector2.ZERO

	if not is_moving():
		return Vector2.ZERO

	if _path.is_empty():
		return Vector2.ZERO

	var target: Vector2 = _path[_path_index]
	var delta: Vector2 = target - unit.position

	if (
		delta.length_squared() <= EPSILON
		and _path_index < _path.size() - 1
	):
		target = _path[_path_index + 1]
		delta = target - unit.position

	if delta.length_squared() <= EPSILON:
		return Vector2.ZERO

	return delta.normalized()


func get_effective_goal() -> Vector2:
	return _effective_goal


func is_final_leg() -> bool:
	if _path.is_empty():
		return true

	return _path_index >= _path.size() - 1


func get_remaining_final_distance() -> float:
	if unit == null:
		return 0.0

	return unit.position.distance_to(_effective_goal)


func wants_final_tick(
	fixed_dt: float
) -> bool:
	if _paused:
		return false

	if not is_moving():
		return false

	if not is_final_leg():
		return false

	var normal_distance: float = move_speed * fixed_dt

	return (
		get_remaining_final_distance()
		<= normal_distance + EPSILON
	)


func get_desired_velocity(
	fixed_dt: float
) -> Vector2:
	if _paused:
		return Vector2.ZERO

	if not is_moving():
		return Vector2.ZERO

	var direction: Vector2 = get_desired_direction()

	if direction == Vector2.ZERO:
		return Vector2.ZERO

	if wants_final_tick(fixed_dt):
		var remaining: float = get_remaining_final_distance()

		if remaining <= EPSILON:
			return Vector2.ZERO

		return direction * (remaining / fixed_dt)

	return direction * move_speed


func commit_simulation(
	new_position: Vector2,
	new_velocity: Vector2,
	finish_order: bool
) -> void:
	if _paused:
		sim_velocity = Vector2.ZERO
		return

	unit.position = new_position

	if finish_order:
		complete_move_order()
		return

	sim_velocity = new_velocity


func _set_path(path: PackedVector2Array) -> void:
	_path = path
	_path_index = 0

	if unit == null:
		return

	while _path_index < _path.size() - 1:
		if (
			unit.position.distance_squared_to(
				_path[_path_index]
			) > EPSILON
		):
			break

		_path_index += 1
