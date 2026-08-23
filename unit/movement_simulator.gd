class_name MovementSimulator
extends Node


const EPSILON: float = 0.00001
const COLLISION_EPSILON: float = 0.0001
const PLAN_MIN_TICKS: int = 3
const PLAN_CLEAR_TICKS: int = 2
const PLAN_MAX_TICKS: int = 180
const PAIR_MEMORY_TICKS: int = 90
const AVOID_PRIMARY_ANGLE: float = 0.78539816339
const AVOID_SMALL_ANGLE: float = 0.3490658504
const AVOID_MEDIUM_ANGLE: float = 0.5235987756
const AVOID_LARGE_ANGLE: float = 1.0471975512
const AVOID_WIDE_ANGLE: float = 1.308996939
const AVOID_SIDE_ANGLE: float = 1.57079632679
const AVOID_REAR_SOFT_ANGLE: float = 2.09439510239
const AVOID_REAR_MEDIUM_ANGLE: float = 2.35619449019
const AVOID_REAR_WIDE_ANGLE: float = 2.61799387799
const AVOID_REVERSE_ANGLE: float = 3.14159265359
const ARRIVAL_MAX_AVOID_ANGLE: float = 1.0471975512
const PLAN_SEPARATION_MARGIN: float = 4.0
const STATIC_BYPASS_MARGIN: float = 4.0
const STATIC_BYPASS_MIN_FORWARD: float = 8.0
const STATIC_BYPASS_REACH_DISTANCE: float = 3.0
const STATIC_BYPASS_MAX_LATERAL_SCALE: float = 2.5
const STATIC_BYPASS_SIDE_STEP_SCALE: float = 1.15
const STATIC_BLOCKER_STEP_THRESHOLD: float = 0.25
const CORRIDOR_DIRECTION_DOT: float = 0.75
const CORRIDOR_PASS_MARGIN: float = 1.0
const CORRIDOR_MIN_FORWARD_GAP: float = 0.5
const CORRIDOR_MERGE_FORWARD_TOLERANCE: float = 4.0
const CORRIDOR_QUEUE_GAP: float = 1.0
const CORRIDOR_RELEASE_STEPS: float = 3.0
const CORRIDOR_GATE_PROBE_MARGIN: float = 2.0
const CORRIDOR_MERGE_RELEASE_STEPS: float = 1.5
const NEIGHBOR_MARGIN: float = 8.0
const REPATH_RETRY_TICKS: int = 4
const REPATH_GOAL_TOLERANCE: float = 2.0
const FINAL_REPAIR_PASSES: int = 2
const JOINT_OPTION_LIMIT: int = 24
const JOINT_RESOLVE_PASSES: int = 2
const JOINT_CONSTRAINED_WEIGHT: float = 1.5
const MOTION_BLOCKED: int = 0
const MOTION_RESOLVED: int = 1
const MOTION_MAP_BLOCKED: int = 2


@export var navigation_service: NavigationService

@export_range(30, 240, 1)
var fixed_tick_rate: int = 60

@export var simulation_quantum: float = 1.0 / 1024.0
@export var candidate_spatial_cell_size: float = 64.0
@export_range(0.9, 1.0, 0.1) var min_avoid_speed_ratio: float = 0.9
@export_range(0.1, 0.1, 0.1) var avoid_speed_step: float = 0.1
@export_range(0.0, 1.0, 0.05) var avoid_previous_velocity_weight: float = 0.45
@export_range(0.0, 1.0, 0.05) var avoid_side_change_penalty: float = 0.2


var simulation_tick: int = 0

var _units: Dictionary[int, Unit] = {}
var _sorted_unit_ids: Array[int] = []
var _orders: Dictionary[int, MoveOrder] = {}
var _avoidance_by_unit: Dictionary[int, AvoidancePlan] = {}
var _pair_memory: Dictionary[String, PairMemory] = {}
var _next_repath_tick_by_unit: Dictionary[int, int] = {}


class Snapshot:
	var unit_id: int = -1
	var position: Vector2 = Vector2.ZERO
	var half_size: Vector2 = Vector2.ZERO


class AvoidancePlan:
	var other_id: int = -1
	var side: int = 1
	var selected_angle: float = 0.78539816339
	var age_ticks: int = 0
	var clear_ticks: int = 0
	var static_blocker: bool = false
	var fixed_waypoint_active: bool = false
	var fixed_waypoint: Vector2 = Vector2.ZERO
	var pass_direction: Vector2 = Vector2.ZERO
	var release_distance: float = 0.0
	var bypass_phase: int = 0
	var bypass_lateral_direction: Vector2 = Vector2.ZERO
	var bypass_lateral_target: Vector2 = Vector2.ZERO
	var bypass_forward_target: Vector2 = Vector2.ZERO
	var corridor_follow: bool = false
	var corridor_yield: bool = false
	var corridor_merge_yield: bool = false


class PairMemory:
	var low_id: int = -1
	var high_id: int = -1
	var low_side: int = 1
	var high_side: int = 1
	var last_tick: int = 0


class PairConflict:
	var a_id: int = -1
	var b_id: int = -1


class VelocityOption:
	var position: Vector2 = Vector2.ZERO
	var velocity: Vector2 = Vector2.ZERO
	var angle: float = 0.0
	var speed_ratio: float = 1.0
	var score: float = 0.0


func _ready() -> void:
	Engine.physics_ticks_per_second = fixed_tick_rate

	if navigation_service == null:
		var parent: Node = get_parent()

		if parent != null:
			var node: Node = parent.get_node_or_null("NavigationService")

			if node is NavigationService:
				navigation_service = node as NavigationService

	call_deferred("_register_scene_units")


func _physics_process(_delta: float) -> void:
	if navigation_service == null:
		return

	if not navigation_service.is_ready():
		return

	var dt: float = 1.0 / float(fixed_tick_rate)
	simulation_tick += 1
	_cleanup_pair_memory()

	var order_ids: Array[int] = []

	for order_id: int in _orders:
		order_ids.append(order_id)

	order_ids.sort()

	var candidates: Array[MovementCandidate] = []

	for order_id: int in order_ids:
		if not _orders.has(order_id):
			continue

		var order: MoveOrder = _orders[order_id]

		if simulation_tick < order.issued_tick:
			continue

		var order_candidates: Array[MovementCandidate] = order.simulate(dt, _units)

		for candidate: MovementCandidate in order_candidates:
			candidates.append(candidate)

	_resolve_candidates(candidates, dt)
	_commit_candidates(candidates)
	_cleanup_finished_orders()


func add_move_order(order: MoveOrder) -> void:
	if order == null:
		return

	if _orders.has(order.order_id):
		push_error("중복 MoveOrder ID: %d" % order.order_id)
		return

	for unit_id: int in order.member_ids:
		if not _units.has(unit_id):
			continue

		_avoidance_by_unit.erase(unit_id)
		_next_repath_tick_by_unit.erase(unit_id)
		var unit: Unit = _units[unit_id]

		if unit.movement.active_move_order != null:
			unit.movement.stop()

	_orders[order.order_id] = order
	order.start(_units)


func stop_units(unit_ids: Array[int]) -> void:
	for unit_id: int in unit_ids:
		if not _units.has(unit_id):
			continue

		_avoidance_by_unit.erase(unit_id)
		_next_repath_tick_by_unit.erase(unit_id)
		_units[unit_id].movement.stop()

	_cleanup_finished_orders()


func register_unit(unit: Unit) -> void:
	if unit == null:
		return

	if _units.has(unit.unit_id):
		var existing: Unit = _units[unit.unit_id]

		if existing == unit:
			return

		push_error("중복 unit_id: %d" % unit.unit_id)
		return

	if unit.movement == null:
		push_error("Unit %d에 MovementComponent가 없습니다." % unit.unit_id)
		return

	_units[unit.unit_id] = unit
	unit.movement.bind_unit(unit)
	_rebuild_sorted_unit_ids()


func unregister_unit(unit: Unit) -> void:
	if unit == null:
		return

	if not _units.has(unit.unit_id):
		return

	if _units[unit.unit_id] != unit:
		return

	_units.erase(unit.unit_id)
	_avoidance_by_unit.erase(unit.unit_id)
	_next_repath_tick_by_unit.erase(unit.unit_id)
	_rebuild_sorted_unit_ids()


func get_unit(unit_id: int) -> Unit:
	if not _units.has(unit_id):
		return null

	return _units[unit_id]


func _register_scene_units() -> void:
	var nodes: Array[Node] = get_tree().get_nodes_in_group("unit")

	for node: Node in nodes:
		if node is Unit:
			register_unit(node as Unit)


func _rebuild_sorted_unit_ids() -> void:
	_sorted_unit_ids.clear()

	for unit_id: int in _units:
		_sorted_unit_ids.append(unit_id)

	_sorted_unit_ids.sort()


func _cleanup_finished_orders() -> void:
	var remove_ids: Array[int] = []

	for order_id: int in _orders:
		var order: MoveOrder = _orders[order_id]

		if order.is_finished(_units):
			remove_ids.append(order_id)

	for order_id: int in remove_ids:
		_orders.erase(order_id)


func _resolve_candidates(
	candidates: Array[MovementCandidate],
	dt: float
) -> void:
	if candidates.is_empty():
		return

	var candidate_by_id: Dictionary[int, MovementCandidate] = {}

	for candidate: MovementCandidate in candidates:
		candidate_by_id[candidate.unit_id] = candidate
		candidate.desired_position = _quantize_vec(candidate.desired_position)
		candidate.position = candidate.desired_position
		candidate.velocity = (candidate.position - candidate.start_position) / maxf(dt, EPSILON)

	var max_move_distance: float = 0.0
	var max_half: Vector2 = Vector2.ZERO

	for unit_id: int in _sorted_unit_ids:
		var unit: Unit = _units[unit_id]
		max_move_distance = maxf(max_move_distance, unit.movement.move_speed * dt)
		var half_size: Vector2 = unit.get_half_size()
		max_half.x = maxf(max_half.x, half_size.x)
		max_half.y = maxf(max_half.y, half_size.y)

	var spatial: Dictionary = _build_start_spatial_hash()
	var neighbors_by_id: Dictionary[int, Array] = {}

	for candidate: MovementCandidate in candidates:
		var own_move: float = maxf(candidate.max_step_distance, candidate.desired_step_distance)
		var extent: Vector2 = Vector2(
			candidate.half_size.x + max_half.x + own_move + max_move_distance + NEIGHBOR_MARGIN,
			candidate.half_size.y + max_half.y + own_move + max_move_distance + NEIGHBOR_MARGIN
		)
		neighbors_by_id[candidate.unit_id] = _query_start_spatial(
			spatial,
			candidate.start_position,
			extent,
			candidate.unit_id
		)

	var freedom_by_id: Dictionary[int, int] = {}
	var target_distance_by_id: Dictionary[int, float] = {}

	for candidate: MovementCandidate in candidates:
		freedom_by_id[candidate.unit_id] = _reservation_map_freedom(candidate, dt)
		target_distance_by_id[candidate.unit_id] = _reservation_target_distance(candidate)

	var sorted_candidates: Array[MovementCandidate] = candidates.duplicate()
	sorted_candidates.sort_custom(
		func(a: MovementCandidate, b: MovementCandidate) -> bool:
			var a_freedom: int = freedom_by_id[a.unit_id]
			var b_freedom: int = freedom_by_id[b.unit_id]

			if a_freedom != b_freedom:
				return a_freedom < b_freedom

			var a_distance: float = target_distance_by_id[a.unit_id]
			var b_distance: float = target_distance_by_id[b.unit_id]

			if absf(a_distance - b_distance) > EPSILON:
				return a_distance < b_distance

			if a.priority != b.priority:
				return a.priority < b.priority

			return a.unit_id < b.unit_id
	)

	var working_snapshots: Dictionary[int, Snapshot] = _build_current_snapshots()

	for candidate: MovementCandidate in sorted_candidates:
		var neighbors: Array = neighbors_by_id[candidate.unit_id]
		var direct_map_clear: bool = _map_segment_clear(
			candidate,
			candidate.desired_position
		)
		var blocker_id: int = _first_unit_blocker(
			candidate,
			candidate.desired_position,
			working_snapshots,
			neighbors
		)

		if direct_map_clear and blocker_id < 0:
			_avoidance_by_unit.erase(candidate.unit_id)
			_apply_position(
				candidate,
				candidate.desired_position,
				dt,
				candidate.finish_order
			)
			_update_snapshot(working_snapshots, candidate)
			continue

		_prepare_reservation_plan(
			candidate,
			blocker_id,
			candidate_by_id,
			dt
		)

		var near_arrival: bool = _candidate_near_arrival(candidate)
		var restrict_arrival_avoidance: bool = near_arrival and direct_map_clear
		var resolution: int = _resolve_unit_motion(
			candidate,
			working_snapshots,
			neighbors,
			dt,
			restrict_arrival_avoidance
		)

		if resolution == MOTION_MAP_BLOCKED:
			_avoidance_by_unit.erase(candidate.unit_id)
			_handle_map_blocked_candidate(candidate, dt)
			_stop_candidate(candidate, dt)
		elif resolution != MOTION_RESOLVED:
			_stop_candidate(candidate, dt)

		_update_snapshot(working_snapshots, candidate)


func _reservation_map_freedom(
	candidate: MovementCandidate,
	dt: float
) -> int:
	var base_direction: Vector2 = _candidate_base_direction(candidate)

	if base_direction == Vector2.ZERO:
		return 0

	var step_distance: float = candidate.max_step_distance

	if candidate.final_tick:
		step_distance = candidate.desired_step_distance

	if step_distance <= EPSILON:
		return 0

	var angles: Array[float] = [
		0.0,
		AVOID_MEDIUM_ANGLE,
		-AVOID_MEDIUM_ANGLE,
		AVOID_PRIMARY_ANGLE,
		-AVOID_PRIMARY_ANGLE,
		AVOID_SIDE_ANGLE,
		-AVOID_SIDE_ANGLE,
	]
	var count: int = 0

	for angle: float in angles:
		var position: Vector2 = _quantize_vec(
			candidate.start_position
			+ base_direction.rotated(angle) * step_distance
		)

		if _map_segment_clear(candidate, position):
			count += 1

	return count


func _reservation_target_distance(candidate: MovementCandidate) -> float:
	var target: Vector2 = candidate.target_position

	if target == Vector2.ZERO:
		target = candidate.desired_position

	return candidate.start_position.distance_squared_to(target)


func _first_unit_blocker(
	candidate: MovementCandidate,
	position: Vector2,
	snapshots: Dictionary[int, Snapshot],
	neighbors: Array
) -> int:
	var blocker_id: int = -1
	var best_distance: float = 1.0e30

	for value: Variant in neighbors:
		var other_id: int = int(value)

		if not snapshots.has(other_id):
			continue

		var other: Snapshot = snapshots[other_id]

		if not _rectangles_overlap_strict(
			position,
			candidate.half_size,
			other.position,
			other.half_size
		):
			continue

		var distance: float = position.distance_squared_to(other.position)

		if distance >= best_distance:
			continue

		best_distance = distance
		blocker_id = other_id

	return blocker_id


func _prepare_reservation_plan(
	candidate: MovementCandidate,
	blocker_id: int,
	candidate_by_id: Dictionary[int, MovementCandidate],
	dt: float
) -> void:
	if blocker_id < 0:
		_avoidance_by_unit.erase(candidate.unit_id)
		return

	var side: int = _reservation_preferred_side(
		candidate,
		blocker_id,
		candidate_by_id,
		dt
	)

	if _avoidance_by_unit.has(candidate.unit_id):
		var existing: AvoidancePlan = _avoidance_by_unit[candidate.unit_id]

		if existing.other_id == blocker_id and not existing.corridor_yield and not existing.corridor_follow:
			existing.side = side

			if absf(existing.selected_angle) <= EPSILON or existing.selected_angle * float(side) < 0.0:
				existing.selected_angle = AVOID_PRIMARY_ANGLE * float(side)

			existing.age_ticks += 1
			existing.clear_ticks = 0
			return

	var plan: AvoidancePlan = AvoidancePlan.new()
	plan.other_id = blocker_id
	plan.side = side
	plan.selected_angle = AVOID_PRIMARY_ANGLE * float(side)
	plan.age_ticks = 0
	plan.clear_ticks = 0
	_avoidance_by_unit[candidate.unit_id] = plan


func _reservation_preferred_side(
	candidate: MovementCandidate,
	blocker_id: int,
	candidate_by_id: Dictionary[int, MovementCandidate],
	dt: float
) -> int:
	var base_direction: Vector2 = _candidate_base_direction(candidate)

	if base_direction == Vector2.ZERO:
		return 1 if candidate.unit_id % 2 == 0 else -1

	var right: Vector2 = Vector2(-base_direction.y, base_direction.x)

	if _units.has(candidate.unit_id):
		var movement: MovementComponent = _units[candidate.unit_id].movement
		var previous_velocity: Vector2 = movement.sim_velocity
		var lateral_speed: float = previous_velocity.dot(right)
		var lateral_threshold: float = maxf(1.0, movement.move_speed * 0.08)

		if absf(lateral_speed) >= lateral_threshold:
			var previous_side: int = 1 if lateral_speed > 0.0 else -1

			if _reservation_side_has_map_motion(
				candidate,
				base_direction,
				previous_side,
				dt
			):
				return previous_side

	if _avoidance_by_unit.has(candidate.unit_id):
		var existing: AvoidancePlan = _avoidance_by_unit[candidate.unit_id]

		if existing.other_id == blocker_id:
			var existing_side: int = 1 if existing.side >= 0 else -1

			if _reservation_side_has_map_motion(
				candidate,
				base_direction,
				existing_side,
				dt
			):
				return existing_side

	var memory: PairMemory = _get_pair_memory(
		candidate.unit_id,
		blocker_id,
		candidate_by_id
	)
	var memory_side: int = memory.low_side if candidate.unit_id == memory.low_id else memory.high_side

	if _reservation_side_has_map_motion(
		candidate,
		base_direction,
		memory_side,
		dt
	):
		return memory_side

	var opposite_side: int = -memory_side

	if _reservation_side_has_map_motion(
		candidate,
		base_direction,
		opposite_side,
		dt
	):
		return opposite_side

	return memory_side


func _reservation_side_has_map_motion(
	candidate: MovementCandidate,
	base_direction: Vector2,
	side: int,
	dt: float
) -> bool:
	var step_distance: float = candidate.max_step_distance

	if candidate.final_tick:
		step_distance = candidate.desired_step_distance

	if step_distance <= EPSILON:
		return false

	var side_value: float = 1.0 if side >= 0 else -1.0
	var angles: Array[float] = [
		AVOID_SMALL_ANGLE,
		AVOID_MEDIUM_ANGLE,
		AVOID_PRIMARY_ANGLE,
		AVOID_LARGE_ANGLE,
		AVOID_WIDE_ANGLE,
		AVOID_SIDE_ANGLE,
		AVOID_REAR_SOFT_ANGLE,
	]

	for angle: float in angles:
		for speed_ratio: float in _avoid_speed_ratios():
			var position: Vector2 = _quantize_vec(
				candidate.start_position
				+ base_direction.rotated(angle * side_value)
				* step_distance
				* speed_ratio
			)

			if _map_segment_clear(candidate, position):
				return true

	return false

func _build_current_snapshots() -> Dictionary[int, Snapshot]:
	var result: Dictionary[int, Snapshot] = {}

	for unit_id: int in _sorted_unit_ids:
		var unit: Unit = _units[unit_id]
		var snapshot: Snapshot = Snapshot.new()
		snapshot.unit_id = unit_id
		snapshot.position = unit.position
		snapshot.half_size = unit.get_half_size()
		result[unit_id] = snapshot

	return result


func _resolve_joint_conflicts(
	conflicts: Array[PairConflict],
	candidate_by_id: Dictionary[int, MovementCandidate],
	working_snapshots: Dictionary[int, Snapshot],
	neighbors_by_id: Dictionary[int, Array],
	dt: float
) -> Dictionary[int, bool]:
	var resolved: Dictionary[int, bool] = {}

	for _pass: int in range(JOINT_RESOLVE_PASSES):
		var changed: bool = false

		for conflict: PairConflict in conflicts:
			if resolved.has(conflict.a_id) or resolved.has(conflict.b_id):
				continue

			if not candidate_by_id.has(conflict.a_id) or not candidate_by_id.has(conflict.b_id):
				continue

			if not _candidate_actively_moving(conflict.a_id, candidate_by_id):
				continue

			if not _candidate_actively_moving(conflict.b_id, candidate_by_id):
				continue

			if _joint_pair_uses_corridor_yield(conflict):
				continue

			var a: MovementCandidate = candidate_by_id[conflict.a_id]
			var b: MovementCandidate = candidate_by_id[conflict.b_id]
			var a_options: Array[VelocityOption] = _joint_velocity_options(a, dt)
			var b_options: Array[VelocityOption] = _joint_velocity_options(b, dt)

			if a_options.is_empty() or b_options.is_empty():
				continue

			var a_freedom: float = float(_joint_map_freedom(a, dt))
			var b_freedom: float = float(_joint_map_freedom(b, dt))
			var freedom_total: float = maxf(a_freedom + b_freedom, 1.0)
			var a_weight: float = 1.0 + JOINT_CONSTRAINED_WEIGHT * (b_freedom / freedom_total)
			var b_weight: float = 1.0 + JOINT_CONSTRAINED_WEIGHT * (a_freedom / freedom_total)
			var best_a: VelocityOption = null
			var best_b: VelocityOption = null
			var best_score: float = 1.0e30

			for a_option: VelocityOption in a_options:
				if not _joint_option_clear_of_others(
					a,
					a_option.position,
					working_snapshots,
					neighbors_by_id[conflict.a_id],
					conflict.b_id
				):
					continue

				for b_option: VelocityOption in b_options:
					if not _joint_option_clear_of_others(
						b,
						b_option.position,
						working_snapshots,
						neighbors_by_id[conflict.b_id],
						conflict.a_id
					):
						continue

					if _rectangles_overlap_strict(
						a_option.position,
						a.half_size,
						b_option.position,
						b.half_size
					):
						continue

					var score: float = a_option.score * a_weight + b_option.score * b_weight
					var relative: Vector2 = a_option.position - b_option.position
					var normalized_dx: float = absf(relative.x) / maxf(a.half_size.x + b.half_size.x, EPSILON)
					var normalized_dy: float = absf(relative.y) / maxf(a.half_size.y + b.half_size.y, EPSILON)
					var clearance: float = maxf(normalized_dx, normalized_dy)
					score -= minf(clearance, 2.0) * 0.03

					if score < best_score - EPSILON:
						best_score = score
						best_a = a_option
						best_b = b_option

			if best_a == null or best_b == null:
				continue

			_apply_position(
				a,
				best_a.position,
				dt,
				_joint_option_finishes(a, best_a)
			)
			_apply_position(
				b,
				best_b.position,
				dt,
				_joint_option_finishes(b, best_b)
			)
			_update_joint_plan(a.unit_id, b.unit_id, best_a.angle)
			_update_joint_plan(b.unit_id, a.unit_id, best_b.angle)
			_update_snapshot(working_snapshots, a)
			_update_snapshot(working_snapshots, b)
			resolved[a.unit_id] = true
			resolved[b.unit_id] = true
			changed = true

		if not changed:
			break

	return resolved


func _joint_pair_uses_corridor_yield(conflict: PairConflict) -> bool:
	if _avoidance_by_unit.has(conflict.a_id):
		var a_plan: AvoidancePlan = _avoidance_by_unit[conflict.a_id]

		if a_plan.corridor_yield and a_plan.other_id == conflict.b_id:
			return true

	if _avoidance_by_unit.has(conflict.b_id):
		var b_plan: AvoidancePlan = _avoidance_by_unit[conflict.b_id]

		if b_plan.corridor_yield and b_plan.other_id == conflict.a_id:
			return true

	return false


func _joint_angles(
	candidate: MovementCandidate,
	plan: AvoidancePlan,
	restrict_arrival: bool
) -> Array[float]:
	if plan == null:
		return _angles_without_plan(candidate.unit_id, restrict_arrival)

	var result: Array[float] = []
	var used: Dictionary[int, bool] = {}
	var primary: Array[float] = _angles_for_plan(plan, restrict_arrival)
	var secondary: Array[float] = _angles_for_side(-plan.side, restrict_arrival)

	for angle: float in primary:
		var key: int = roundi(angle * 1000000.0)

		if used.has(key):
			continue

		used[key] = true
		result.append(angle)

	for angle: float in secondary:
		var key: int = roundi(angle * 1000000.0)

		if used.has(key):
			continue

		used[key] = true
		result.append(angle)

	return result


func _joint_map_freedom(
	candidate: MovementCandidate,
	dt: float
) -> int:
	var base_direction: Vector2 = _candidate_base_direction(candidate)

	if base_direction == Vector2.ZERO:
		return 0

	var plan: AvoidancePlan = null

	if _avoidance_by_unit.has(candidate.unit_id):
		plan = _avoidance_by_unit[candidate.unit_id]

	var near_arrival: bool = _candidate_near_arrival(candidate)
	var direct_map_clear: bool = _map_segment_clear(candidate, candidate.desired_position)
	var restrict_arrival: bool = near_arrival and direct_map_clear
	var angles: Array[float] = _joint_angles(candidate, plan, restrict_arrival)

	var ratios: Array[float] = _avoid_speed_ratios()
	var step_distance: float = candidate.max_step_distance

	if candidate.final_tick and near_arrival:
		step_distance = candidate.desired_step_distance

	if step_distance <= EPSILON:
		return 0

	var count: int = 0

	for angle: float in angles:
		var direction: Vector2 = base_direction.rotated(angle)

		for ratio: float in ratios:
			var position: Vector2 = _quantize_vec(
				candidate.start_position
				+ direction * step_distance * ratio
			)

			if restrict_arrival and not _makes_arrival_progress(candidate, position):
				continue

			if _map_segment_clear(candidate, position):
				count += 1

	return count


func _joint_velocity_options(
	candidate: MovementCandidate,
	dt: float
) -> Array[VelocityOption]:
	var result: Array[VelocityOption] = []
	var base_direction: Vector2 = _candidate_base_direction(candidate)

	if base_direction == Vector2.ZERO:
		return result

	var plan: AvoidancePlan = null

	if _avoidance_by_unit.has(candidate.unit_id):
		plan = _avoidance_by_unit[candidate.unit_id]

	var near_arrival: bool = _candidate_near_arrival(candidate)
	var direct_map_clear: bool = _map_segment_clear(candidate, candidate.desired_position)
	var restrict_arrival: bool = near_arrival and direct_map_clear
	var angles: Array[float] = _joint_angles(candidate, plan, restrict_arrival)

	var ratios: Array[float] = _avoid_speed_ratios()
	var step_distance: float = candidate.max_step_distance

	if candidate.final_tick and near_arrival:
		step_distance = candidate.desired_step_distance

	if step_distance <= EPSILON:
		return result

	var preferred_speed: float = step_distance / maxf(dt, EPSILON)
	var preferred_velocity: Vector2 = base_direction * preferred_speed
	var previous_velocity: Vector2 = Vector2.ZERO

	if _units.has(candidate.unit_id):
		previous_velocity = _units[candidate.unit_id].movement.sim_velocity

	for angle: float in angles:
		var direction: Vector2 = base_direction.rotated(angle)

		for ratio: float in ratios:
			var position: Vector2 = _quantize_vec(
				candidate.start_position
				+ direction * step_distance * ratio
			)

			if restrict_arrival and not _makes_arrival_progress(candidate, position):
				continue

			if not _map_segment_clear(candidate, position):
				continue

			var option: VelocityOption = VelocityOption.new()
			option.position = position
			option.velocity = (position - candidate.start_position) / maxf(dt, EPSILON)
			option.angle = angle
			option.speed_ratio = ratio
			option.score = _velocity_candidate_score(
				candidate,
				option.velocity,
				preferred_velocity,
				previous_velocity,
				angle,
				ratio,
				plan
			)
			result.append(option)

	result.sort_custom(
		func(a: VelocityOption, b: VelocityOption) -> bool:
			if absf(a.score - b.score) > EPSILON:
				return a.score < b.score

			if absf(a.angle - b.angle) > EPSILON:
				return absf(a.angle) < absf(b.angle)

			return a.speed_ratio > b.speed_ratio
	)

	if result.size() > JOINT_OPTION_LIMIT:
		result.resize(JOINT_OPTION_LIMIT)

	return result


func _joint_option_clear_of_others(
	candidate: MovementCandidate,
	position: Vector2,
	snapshots: Dictionary[int, Snapshot],
	neighbors: Array,
	exclude_id: int
) -> bool:
	for value: Variant in neighbors:
		var other_id: int = int(value)

		if other_id == exclude_id:
			continue

		if not snapshots.has(other_id):
			continue

		var other: Snapshot = snapshots[other_id]

		if _rectangles_overlap_strict(
			position,
			candidate.half_size,
			other.position,
			other.half_size
		):
			return false

	return true


func _joint_option_finishes(
	candidate: MovementCandidate,
	option: VelocityOption
) -> bool:
	return (
		candidate.finish_order
		and absf(option.angle) <= EPSILON
		and option.speed_ratio >= 1.0 - EPSILON
		and option.position.distance_squared_to(candidate.desired_position) <= EPSILON
	)


func _update_joint_plan(
	unit_id: int,
	other_id: int,
	angle: float
) -> void:
	if not _avoidance_by_unit.has(unit_id):
		return

	var plan: AvoidancePlan = _avoidance_by_unit[unit_id]

	if plan.other_id != other_id:
		return

	if absf(angle) > EPSILON:
		plan.side = 1 if angle > 0.0 else -1
		plan.selected_angle = angle
		_set_pair_memory_side(unit_id, other_id, plan.side)


func _resolution_order_rank(unit_id: int) -> int:
	if not _avoidance_by_unit.has(unit_id):
		return 1

	var plan: AvoidancePlan = _avoidance_by_unit[unit_id]

	if plan.corridor_follow or plan.corridor_yield:
		return 0

	return 1


func _handle_map_blocked_candidate(
	candidate: MovementCandidate,
	dt: float
) -> void:
	if _avoidance_by_unit.has(candidate.unit_id):
		var plan: AvoidancePlan = _avoidance_by_unit[candidate.unit_id]

		if plan.static_blocker:
			_configure_static_bypass(plan, candidate, plan.side)
			return

	_repath_candidate(candidate, dt)


func _validate_navigation_candidates(
	candidates: Array[MovementCandidate],
	dt: float
) -> void:
	for candidate: MovementCandidate in candidates:
		if _map_segment_clear(candidate, candidate.desired_position):
			continue

		_repath_candidate(candidate, dt)


func _repath_candidate(
	candidate: MovementCandidate,
	dt: float
) -> bool:
	if not _units.has(candidate.unit_id):
		return false

	if _next_repath_tick_by_unit.has(candidate.unit_id):
		if simulation_tick < _next_repath_tick_by_unit[candidate.unit_id]:
			return false

	var unit: Unit = _units[candidate.unit_id]
	var movement: MovementComponent = unit.movement

	if movement == null or movement.active_move_order == null:
		return false

	if movement.active_move_order.order_id != candidate.order_id:
		return false

	var goal: Vector2 = movement.get_effective_goal()

	if candidate.arrival_active:
		goal = candidate.arrival_slot

	var path: PackedVector2Array = navigation_service.find_path(
		candidate.start_position,
		goal,
		candidate.half_size
	)

	if path.is_empty():
		_next_repath_tick_by_unit[candidate.unit_id] = simulation_tick + REPATH_RETRY_TICKS
		return false

	var path_goal: Vector2 = path[path.size() - 1]

	if path_goal.distance_to(goal) > REPATH_GOAL_TOLERANCE:
		_next_repath_tick_by_unit[candidate.unit_id] = simulation_tick + REPATH_RETRY_TICKS
		return false

	if not movement.replace_path(path, goal):
		_next_repath_tick_by_unit[candidate.unit_id] = simulation_tick + REPATH_RETRY_TICKS
		return false

	movement.reset_sim_velocity()
	movement.sync_path_progress(movement.move_speed * dt, navigation_service)
	_avoidance_by_unit.erase(candidate.unit_id)
	_next_repath_tick_by_unit.erase(candidate.unit_id)
	_refresh_candidate_from_movement(candidate, movement, dt)
	return _map_segment_clear(candidate, candidate.desired_position)


func _refresh_candidate_from_movement(
	candidate: MovementCandidate,
	movement: MovementComponent,
	dt: float
) -> void:
	var desired_velocity: Vector2 = movement.get_desired_velocity(dt)
	var desired_position: Vector2 = candidate.start_position + desired_velocity * dt
	var final_tick: bool = movement.wants_final_tick(dt)

	if final_tick:
		desired_position = movement.get_effective_goal()

		if dt > EPSILON:
			desired_velocity = (desired_position - candidate.start_position) / dt

	candidate.desired_velocity = desired_velocity
	candidate.desired_position = _quantize_vec(desired_position)
	candidate.position = candidate.desired_position
	candidate.velocity = (candidate.position - candidate.start_position) / dt
	candidate.target_position = movement.get_current_waypoint()
	candidate.desired_step_distance = candidate.start_position.distance_to(candidate.desired_position)
	candidate.final_tick = final_tick
	candidate.finish_order = final_tick
	candidate.arrival_distance = candidate.start_position.distance_to(candidate.arrival_slot)


func _stop_candidate_desire(
	candidate: MovementCandidate,
	dt: float
) -> void:
	candidate.desired_position = candidate.start_position
	candidate.desired_velocity = Vector2.ZERO
	candidate.desired_step_distance = 0.0
	candidate.final_tick = false
	candidate.finish_order = false
	_avoidance_by_unit.erase(candidate.unit_id)
	_stop_candidate(candidate, dt)


func _stop_candidate(
	candidate: MovementCandidate,
	dt: float
) -> void:
	_apply_position(candidate, candidate.start_position, dt, false)


func _update_existing_plans(
	candidate_by_id: Dictionary[int, MovementCandidate],
	desired_snapshots: Dictionary[int, Snapshot],
	neighbors_by_id: Dictionary[int, Array]
) -> void:
	var remove_ids: Array[int] = []

	for unit_id: int in _avoidance_by_unit:
		var plan: AvoidancePlan = _avoidance_by_unit[unit_id]
		plan.age_ticks += 1

		if not _units.has(unit_id) or not _units.has(plan.other_id):
			remove_ids.append(unit_id)
			continue

		if not candidate_by_id.has(unit_id):
			remove_ids.append(unit_id)
			continue

		if plan.corridor_yield:
			if plan.corridor_merge_yield:
				remove_ids.append(unit_id)
				continue

			if not _corridor_yield_plan_valid(unit_id, plan, candidate_by_id):
				remove_ids.append(unit_id)

			continue

		if plan.corridor_follow:
			remove_ids.append(unit_id)
			continue

		if plan.static_blocker and _candidate_actively_moving(plan.other_id, candidate_by_id):
			plan.static_blocker = false
			plan.fixed_waypoint_active = false
			plan.bypass_phase = 0

		var own: Snapshot = desired_snapshots[unit_id]
		var other: Snapshot = desired_snapshots[plan.other_id]
		var direct_pair_safe: bool = not _rectangles_overlap_strict(
			own.position,
			own.half_size,
			other.position,
			other.half_size
		)

		if plan.fixed_waypoint_active:
			var own_position: Vector2 = _units[unit_id].position
			var other_position: Vector2 = _units[plan.other_id].position
			var passed: bool = (
				(own_position - other_position).dot(plan.pass_direction)
				>= plan.release_distance
			)
			var reached_waypoint: bool = (
				own_position.distance_to(plan.fixed_waypoint)
				<= STATIC_BYPASS_REACH_DISTANCE
			)

			if direct_pair_safe and (passed or reached_waypoint):
				plan.clear_ticks += 1
			else:
				plan.clear_ticks = 0
		else:
			var separated: bool = _snapshots_separated_with_margin(
				own,
				other,
				PLAN_SEPARATION_MARGIN
			)

			if separated and direct_pair_safe:
				plan.clear_ticks += 1
			else:
				plan.clear_ticks = 0

		if plan.age_ticks >= PLAN_MIN_TICKS and plan.clear_ticks >= PLAN_CLEAR_TICKS:
			remove_ids.append(unit_id)
		elif plan.age_ticks >= PLAN_MAX_TICKS and direct_pair_safe:
			remove_ids.append(unit_id)

	for unit_id: int in remove_ids:
		_avoidance_by_unit.erase(unit_id)

func _corridor_yield_plan_valid(
	unit_id: int,
	plan: AvoidancePlan,
	candidate_by_id: Dictionary[int, MovementCandidate]
) -> bool:
	if not candidate_by_id.has(unit_id) or not candidate_by_id.has(plan.other_id):
		return false

	var yielder: MovementCandidate = candidate_by_id[unit_id]
	var other: MovementCandidate = candidate_by_id[plan.other_id]
	var forward: Vector2 = plan.pass_direction.normalized()

	if forward == Vector2.ZERO:
		return false

	if _lateral_passing_space_available(yielder, other, forward):
		return false

	var other_direction: Vector2 = _candidate_base_direction(other)

	if other_direction != Vector2.ZERO and forward.dot(other_direction) > -0.25:
		return false

	var relative: Vector2 = other.start_position - yielder.start_position
	var forward_gap: float = relative.dot(forward)
	var release_gap: float = (
		_aabb_support(yielder.half_size, forward)
		+ _aabb_support(other.half_size, forward)
		+ PLAN_SEPARATION_MARGIN
	)

	if forward_gap < -release_gap:
		return false

	return true


func _corridor_follow_plan_valid(
	unit_id: int,
	plan: AvoidancePlan,
	candidate_by_id: Dictionary[int, MovementCandidate]
) -> bool:
	if not candidate_by_id.has(unit_id) or not candidate_by_id.has(plan.other_id):
		return false

	var follower: MovementCandidate = candidate_by_id[unit_id]
	var leader: MovementCandidate = candidate_by_id[plan.other_id]
	var direction: Vector2 = plan.pass_direction.normalized()

	if direction == Vector2.ZERO:
		direction = _candidate_base_direction(follower)

	if direction == Vector2.ZERO:
		return false

	var follower_direction: Vector2 = _candidate_base_direction(follower)
	var leader_direction: Vector2 = _candidate_base_direction(leader)

	if (
		follower_direction != Vector2.ZERO
		and leader_direction != Vector2.ZERO
		and follower_direction.dot(leader_direction) < CORRIDOR_DIRECTION_DOT
	):
		return false

	if _lateral_passing_space_available(follower, leader, direction):
		return false

	if _lateral_passing_space_available(leader, follower, direction):
		return false

	var forward_gap: float = (leader.start_position - follower.start_position).dot(direction)
	var follower_forward: float = _aabb_support(follower.half_size, direction)
	var leader_forward: float = _aabb_support(leader.half_size, direction)
	var queue_gap: float = follower_forward + leader_forward + CORRIDOR_QUEUE_GAP
	var release_gap: float = (
		queue_gap
		+ follower.max_step_distance * CORRIDOR_RELEASE_STEPS
		+ PLAN_SEPARATION_MARGIN
	)

	if forward_gap < -queue_gap:
		return false

	if forward_gap > release_gap:
		return false

	return true

func _corridor_merge_yield_plan_valid(
	unit_id: int,
	plan: AvoidancePlan,
	candidate_by_id: Dictionary[int, MovementCandidate]
) -> bool:
	if not candidate_by_id.has(unit_id) or not candidate_by_id.has(plan.other_id):
		return false

	var yielder: MovementCandidate = candidate_by_id[unit_id]
	var leader: MovementCandidate = candidate_by_id[plan.other_id]
	var forward: Vector2 = plan.pass_direction.normalized()

	if forward == Vector2.ZERO:
		forward = _candidate_base_direction(yielder)

	if forward == Vector2.ZERO:
		return false

	var forward_gap: float = (leader.start_position - yielder.start_position).dot(forward)
	var required_gap: float = (
		_aabb_support(yielder.half_size, forward)
		+ _aabb_support(leader.half_size, forward)
		+ CORRIDOR_QUEUE_GAP
		+ yielder.max_step_distance * CORRIDOR_MERGE_RELEASE_STEPS
	)

	if forward_gap >= required_gap:
		return false

	return true


func _collect_conflicts(
	candidates: Array[MovementCandidate],
	snapshots: Dictionary[int, Snapshot],
	neighbors_by_id: Dictionary[int, Array]
) -> Array[PairConflict]:
	var result: Array[PairConflict] = []
	var seen: Dictionary[String, bool] = {}

	for candidate: MovementCandidate in candidates:
		var own: Snapshot = snapshots[candidate.unit_id]
		var neighbors: Array = neighbors_by_id[candidate.unit_id]

		for value: Variant in neighbors:
			var other_id: int = int(value)

			if not snapshots.has(other_id):
				continue

			var other: Snapshot = snapshots[other_id]

			if not _rectangles_overlap_strict(
				own.position,
				own.half_size,
				other.position,
				other.half_size
			):
				continue

			var key: String = _pair_key(candidate.unit_id, other_id)

			if seen.has(key):
				continue

			seen[key] = true
			var pair: PairConflict = PairConflict.new()
			pair.a_id = mini(candidate.unit_id, other_id)
			pair.b_id = maxi(candidate.unit_id, other_id)
			result.append(pair)

	result.sort_custom(
		func(a: PairConflict, b: PairConflict) -> bool:
			if a.a_id != b.a_id:
				return a.a_id < b.a_id
			return a.b_id < b.b_id
	)
	return result


func _establish_new_plans(
	conflicts: Array[PairConflict],
	candidate_by_id: Dictionary[int, MovementCandidate]
) -> void:
	for conflict: PairConflict in conflicts:
		var a_moving: bool = _candidate_actively_moving(conflict.a_id, candidate_by_id)
		var b_moving: bool = _candidate_actively_moving(conflict.b_id, candidate_by_id)

		if not a_moving and not b_moving:
			continue

		var corridor_yielder: int = _corridor_opposing_yielder(
			conflict.a_id,
			conflict.b_id,
			candidate_by_id
		)

		if corridor_yielder >= 0:
			var corridor_winner: int = conflict.b_id if corridor_yielder == conflict.a_id else conflict.a_id

			if _avoidance_by_unit.has(corridor_winner):
				var winner_plan: AvoidancePlan = _avoidance_by_unit[corridor_winner]

				if winner_plan.other_id == corridor_yielder:
					_avoidance_by_unit.erase(corridor_winner)

			if candidate_by_id.has(corridor_yielder):
				var yield_plan: AvoidancePlan = AvoidancePlan.new()
				yield_plan.other_id = corridor_winner
				yield_plan.corridor_yield = true
				yield_plan.pass_direction = _candidate_base_direction(candidate_by_id[corridor_yielder])
				yield_plan.selected_angle = PI
				_avoidance_by_unit[corridor_yielder] = yield_plan

			continue

		var memory: PairMemory = _get_pair_memory(
			conflict.a_id,
			conflict.b_id,
			candidate_by_id
		)

		if a_moving and not _avoidance_by_unit.has(conflict.a_id):
			var side_a: int = memory.low_side if conflict.a_id == memory.low_id else memory.high_side
			var plan_a: AvoidancePlan = _create_avoidance_plan(
				candidate_by_id[conflict.a_id],
				conflict.b_id,
				side_a,
				b_moving
			)
			_avoidance_by_unit[conflict.a_id] = plan_a

		if b_moving and not _avoidance_by_unit.has(conflict.b_id):
			var side_b: int = memory.low_side if conflict.b_id == memory.low_id else memory.high_side
			var plan_b: AvoidancePlan = _create_avoidance_plan(
				candidate_by_id[conflict.b_id],
				conflict.a_id,
				side_b,
				a_moving
			)
			_avoidance_by_unit[conflict.b_id] = plan_b

func _corridor_opposing_yielder(
	a_id: int,
	b_id: int,
	candidate_by_id: Dictionary[int, MovementCandidate]
) -> int:
	if not candidate_by_id.has(a_id) or not candidate_by_id.has(b_id):
		return -1

	if not _candidate_actively_moving(a_id, candidate_by_id):
		return -1

	if not _candidate_actively_moving(b_id, candidate_by_id):
		return -1

	var a: MovementCandidate = candidate_by_id[a_id]
	var b: MovementCandidate = candidate_by_id[b_id]
	var a_direction: Vector2 = _candidate_base_direction(a)
	var b_direction: Vector2 = _candidate_base_direction(b)

	if a_direction == Vector2.ZERO or b_direction == Vector2.ZERO:
		return -1

	if a_direction.dot(b_direction) > -0.25:
		return -1

	if _lateral_passing_space_available(a, b, a_direction):
		return -1

	if _lateral_passing_space_available(b, a, b_direction):
		return -1

	var a_can_back: bool = _candidate_can_back_up(a, a_direction)
	var b_can_back: bool = _candidate_can_back_up(b, b_direction)

	if a_can_back and not b_can_back:
		return a_id

	if b_can_back and not a_can_back:
		return b_id

	if not a_can_back and not b_can_back:
		return -1

	if a.priority != b.priority:
		return a_id if a.priority > b.priority else b_id

	return maxi(a_id, b_id)


func _candidate_can_back_up(
	candidate: MovementCandidate,
	forward: Vector2
) -> bool:
	var direction: Vector2 = forward.normalized()

	if direction == Vector2.ZERO:
		return false

	var distance: float = maxf(candidate.max_step_distance, 1.0)
	var target: Vector2 = candidate.start_position - direction * distance

	return navigation_service.segment_clear(
		candidate.start_position,
		target,
		candidate.half_size
	)


func _corridor_merge_yielder(
	a_id: int,
	b_id: int,
	candidate_by_id: Dictionary[int, MovementCandidate]
) -> int:
	if not candidate_by_id.has(a_id) or not candidate_by_id.has(b_id):
		return -1

	if not _candidate_actively_moving(a_id, candidate_by_id):
		return -1

	if not _candidate_actively_moving(b_id, candidate_by_id):
		return -1

	var a: MovementCandidate = candidate_by_id[a_id]
	var b: MovementCandidate = candidate_by_id[b_id]
	var a_direction: Vector2 = _candidate_base_direction(a)
	var b_direction: Vector2 = _candidate_base_direction(b)

	if a_direction == Vector2.ZERO or b_direction == Vector2.ZERO:
		return -1

	if a_direction.dot(b_direction) < CORRIDOR_DIRECTION_DOT:
		return -1

	var forward: Vector2 = (a_direction + b_direction).normalized()

	if forward == Vector2.ZERO:
		forward = a_direction

	var separation: float = (b.start_position - a.start_position).dot(forward)

	if absf(separation) > CORRIDOR_MERGE_FORWARD_TOLERANCE:
		return -1

	if _lateral_passing_space_available(a, b, forward):
		return -1

	if _lateral_passing_space_available(b, a, forward):
		return -1

	var preferred_yielder: int = maxi(a_id, b_id)

	if a.priority != b.priority:
		preferred_yielder = a_id if a.priority > b.priority else b_id

	if _candidate_can_back_up(candidate_by_id[preferred_yielder], forward):
		return preferred_yielder

	var other_yielder: int = b_id if preferred_yielder == a_id else a_id

	if _candidate_can_back_up(candidate_by_id[other_yielder], forward):
		return other_yielder

	return -1


func _corridor_follow_follower(
	a_id: int,
	b_id: int,
	candidate_by_id: Dictionary[int, MovementCandidate]
) -> int:
	if not candidate_by_id.has(a_id) or not candidate_by_id.has(b_id):
		return -1

	var a: MovementCandidate = candidate_by_id[a_id]
	var b: MovementCandidate = candidate_by_id[b_id]
	var a_moving: bool = _candidate_actively_moving(a_id, candidate_by_id)
	var b_moving: bool = _candidate_actively_moving(b_id, candidate_by_id)

	if not a_moving and not b_moving:
		return -1

	if a_moving and b_moving:
		var a_direction: Vector2 = _candidate_base_direction(a)
		var b_direction: Vector2 = _candidate_base_direction(b)

		if a_direction == Vector2.ZERO or b_direction == Vector2.ZERO:
			return -1

		if a_direction.dot(b_direction) < CORRIDOR_DIRECTION_DOT:
			return -1

		var forward: Vector2 = (a_direction + b_direction).normalized()

		if forward == Vector2.ZERO:
			forward = a_direction

		var separation: float = (b.start_position - a.start_position).dot(forward)

		if absf(separation) <= CORRIDOR_MERGE_FORWARD_TOLERANCE:
			return -1

		if _lateral_passing_space_available(a, b, forward):
			return -1

		if _lateral_passing_space_available(b, a, forward):
			return -1

		var follower: MovementCandidate = a if separation > 0.0 else b
		return follower.unit_id

	var moving: MovementCandidate = a if a_moving else b
	var stationary: MovementCandidate = b if a_moving else a
	var direction: Vector2 = _candidate_base_direction(moving)

	if direction == Vector2.ZERO:
		return -1

	var forward_gap: float = (stationary.start_position - moving.start_position).dot(direction)

	if forward_gap <= CORRIDOR_MIN_FORWARD_GAP:
		return -1

	if _lateral_passing_space_available(moving, stationary, direction):
		return -1

	return moving.unit_id

func _corridor_pair_forward(
	follower: MovementCandidate,
	leader: MovementCandidate
) -> Vector2:
	var follower_direction: Vector2 = _candidate_base_direction(follower)
	var leader_direction: Vector2 = _candidate_base_direction(leader)

	if follower_direction != Vector2.ZERO and leader_direction != Vector2.ZERO:
		var combined: Vector2 = follower_direction + leader_direction

		if combined.length_squared() > EPSILON:
			return combined.normalized()

	if leader_direction != Vector2.ZERO:
		return leader_direction

	if follower_direction != Vector2.ZERO:
		return follower_direction

	return Vector2.ZERO


func _lateral_passing_space_available(
	follower: MovementCandidate,
	leader: MovementCandidate,
	forward: Vector2
) -> bool:
	var direction: Vector2 = forward.normalized()

	if direction == Vector2.ZERO:
		return true

	var right: Vector2 = Vector2(-direction.y, direction.x)
	var follower_lateral: float = _aabb_support(follower.half_size, right)
	var leader_lateral: float = _aabb_support(leader.half_size, right)
	var follower_forward: float = _aabb_support(follower.half_size, direction)
	var leader_forward: float = _aabb_support(leader.half_size, direction)
	var lateral_shift: float = follower_lateral + leader_lateral + CORRIDOR_PASS_MARGIN
	var current_forward_gap: float = maxf(
		0.0,
		(leader.start_position - follower.start_position).dot(direction)
	)
	var gate_probe_distance: float = (
		follower_forward
		+ leader_forward
		+ CORRIDOR_GATE_PROBE_MARGIN
	)
	var forward_probe: float = maxf(current_forward_gap, gate_probe_distance)

	for side: float in [-1.0, 1.0]:
		var target: Vector2 = (
			follower.start_position
			+ direction * forward_probe
			+ right * lateral_shift * side
		)

		if not navigation_service.can_place_static(target, follower.half_size):
			continue

		if navigation_service.segment_clear(
			follower.start_position,
			target,
			follower.half_size
		):
			return true

	return false

func _candidate_actively_moving(
	unit_id: int,
	candidate_by_id: Dictionary[int, MovementCandidate]
) -> bool:
	if not candidate_by_id.has(unit_id):
		return false

	var candidate: MovementCandidate = candidate_by_id[unit_id]

	if candidate.desired_step_distance > STATIC_BLOCKER_STEP_THRESHOLD:
		return true

	return candidate.desired_velocity.length() > STATIC_BLOCKER_STEP_THRESHOLD


func _create_avoidance_plan(
	_candidate: MovementCandidate,
	other_id: int,
	side: int,
	_other_moving: bool
) -> AvoidancePlan:
	var plan: AvoidancePlan = AvoidancePlan.new()
	plan.other_id = other_id
	plan.side = side
	plan.selected_angle = AVOID_PRIMARY_ANGLE * float(side)
	return plan


func _configure_static_bypass(
	plan: AvoidancePlan,
	candidate: MovementCandidate,
	preferred_side: int
) -> bool:
	if not _units.has(plan.other_id):
		return false

	var direction: Vector2 = _candidate_base_direction(candidate)

	if direction.length_squared() <= EPSILON:
		return false

	direction = direction.normalized()
	var right: Vector2 = Vector2(-direction.y, direction.x)
	var other: Unit = _units[plan.other_id]
	var other_half: Vector2 = other.get_half_size()
	var lateral_clearance: float = (
		_aabb_support(candidate.half_size, right)
		+ _aabb_support(other_half, right)
		+ STATIC_BYPASS_MARGIN
	)
	var forward_clearance: float = maxf(
		STATIC_BYPASS_MIN_FORWARD,
		_aabb_support(candidate.half_size, direction)
		+ _aabb_support(other_half, direction)
		+ STATIC_BYPASS_MARGIN
	)
	var side_order: Array[int] = [preferred_side, -preferred_side]
	var lateral_scales: Array[float] = [
		STATIC_BYPASS_SIDE_STEP_SCALE,
		1.35,
		1.7,
		2.1,
		STATIC_BYPASS_MAX_LATERAL_SCALE,
	]
	var best_side: int = preferred_side
	var best_lateral_direction: Vector2 = Vector2.ZERO
	var best_lateral_target: Vector2 = Vector2.ZERO
	var best_forward_target: Vector2 = Vector2.ZERO
	var best_score: float = 1.0e30
	var found: bool = false

	for side: int in side_order:
		var lateral_direction: Vector2 = right * float(side)
		var current_lateral: float = (candidate.start_position - other.position).dot(lateral_direction)

		if current_lateral < -EPSILON:
			continue

		for lateral_scale: float in lateral_scales:
			var wanted_lateral: float = lateral_clearance * lateral_scale
			var lateral_distance: float = maxf(
				0.0,
				wanted_lateral - current_lateral
			)
			var lateral_target: Vector2 = (
				candidate.start_position
				+ lateral_direction * lateral_distance
			)

			if not navigation_service.can_place_static(lateral_target, candidate.half_size):
				continue

			if not navigation_service.segment_clear(
				candidate.start_position,
				lateral_target,
				candidate.half_size
			):
				continue

			if _rectangles_overlap_strict(
				lateral_target,
				candidate.half_size,
				other.position,
				other_half
			):
				continue

			var current_forward: float = (lateral_target - other.position).dot(direction)
			var forward_distance: float = maxf(
				0.0,
				forward_clearance - current_forward
			)
			var forward_target: Vector2 = lateral_target + direction * forward_distance

			if not navigation_service.can_place_static(forward_target, candidate.half_size):
				continue

			if not navigation_service.segment_clear(
				lateral_target,
				forward_target,
				candidate.half_size
			):
				continue

			var side_penalty: float = 0.0 if side == preferred_side else lateral_clearance
			var score: float = lateral_distance + forward_distance + side_penalty

			if score < best_score - EPSILON:
				best_score = score
				best_side = side
				best_lateral_direction = lateral_direction
				best_lateral_target = lateral_target
				best_forward_target = forward_target
				found = true

	if not found:
		plan.fixed_waypoint_active = false
		plan.bypass_phase = 0
		return false

	plan.side = best_side
	plan.selected_angle = AVOID_PRIMARY_ANGLE * float(best_side)
	plan.fixed_waypoint_active = true
	plan.fixed_waypoint = best_lateral_target
	plan.pass_direction = direction
	plan.release_distance = forward_clearance
	plan.bypass_phase = 0
	plan.bypass_lateral_direction = best_lateral_direction
	plan.bypass_lateral_target = best_lateral_target
	plan.bypass_forward_target = best_forward_target
	return true


func _aabb_support(half_size: Vector2, direction: Vector2) -> float:
	return absf(direction.x) * half_size.x + absf(direction.y) * half_size.y


func _get_pair_memory(
	a_id: int,
	b_id: int,
	candidate_by_id: Dictionary[int, MovementCandidate]
) -> PairMemory:
	var low_id: int = mini(a_id, b_id)
	var high_id: int = maxi(a_id, b_id)
	var key: String = _pair_key(low_id, high_id)

	if _pair_memory.has(key):
		var existing: PairMemory = _pair_memory[key]
		existing.last_tick = simulation_tick
		return existing

	var memory: PairMemory = PairMemory.new()
	memory.low_id = low_id
	memory.high_id = high_id
	memory.last_tick = simulation_tick
	var sides: Vector2i = _choose_pair_sides(low_id, high_id, candidate_by_id)
	memory.low_side = sides.x
	memory.high_side = sides.y
	_pair_memory[key] = memory
	return memory


func _choose_pair_sides(
	low_id: int,
	high_id: int,
	candidate_by_id: Dictionary[int, MovementCandidate]
) -> Vector2i:
	var low_moving: bool = _candidate_actively_moving(low_id, candidate_by_id)
	var high_moving: bool = _candidate_actively_moving(high_id, candidate_by_id)

	if low_moving and not high_moving:
		return Vector2i(_side_away_from_unit(candidate_by_id[low_id], high_id), 1)

	if high_moving and not low_moving:
		return Vector2i(1, _side_away_from_unit(candidate_by_id[high_id], low_id))

	if not low_moving or not high_moving:
		return Vector2i(1, 1)

	var a: MovementCandidate = candidate_by_id[low_id]
	var b: MovementCandidate = candidate_by_id[high_id]
	var a_dir: Vector2 = _candidate_base_direction(a)
	var b_dir: Vector2 = _candidate_base_direction(b)

	if a_dir == Vector2.ZERO or b_dir == Vector2.ZERO:
		return Vector2i(1, -1)

	var combinations: Array[Vector2i] = [
		Vector2i(1, 1),
		Vector2i(1, -1),
		Vector2i(-1, 1),
		Vector2i(-1, -1),
	]
	var best: Vector2i = combinations[0]
	var best_score: float = -1.0e30
	var a_step: float = maxf(a.max_step_distance, a.desired_step_distance)
	var b_step: float = maxf(b.max_step_distance, b.desired_step_distance)
	var a_map_clear: Dictionary[int, bool] = {}
	var b_map_clear: Dictionary[int, bool] = {}

	for side: int in [-1, 1]:
		var a_test: Vector2 = a.start_position + a_dir.rotated(AVOID_PRIMARY_ANGLE * float(side)) * a_step
		var b_test: Vector2 = b.start_position + b_dir.rotated(AVOID_PRIMARY_ANGLE * float(side)) * b_step
		a_map_clear[side] = navigation_service.segment_clear(a.start_position, a_test, a.half_size)
		b_map_clear[side] = navigation_service.segment_clear(b.start_position, b_test, b.half_size)

	for combination: Vector2i in combinations:
		var a_end: Vector2 = a.start_position + a_dir.rotated(AVOID_PRIMARY_ANGLE * float(combination.x)) * a_step
		var b_end: Vector2 = b.start_position + b_dir.rotated(AVOID_PRIMARY_ANGLE * float(combination.y)) * b_step
		var dx: float = absf(a_end.x - b_end.x) / maxf(a.half_size.x + b.half_size.x, EPSILON)
		var dy: float = absf(a_end.y - b_end.y) / maxf(a.half_size.y + b.half_size.y, EPSILON)
		var score: float = maxf(dx, dy) * 10.0 + minf(dx, dy)

		if not a_map_clear[combination.x]:
			score -= 1000000.0

		if not b_map_clear[combination.y]:
			score -= 1000000.0

		if combination.x == combination.y:
			score += 0.01

		if score > best_score + EPSILON:
			best_score = score
			best = combination

	return best


func _side_away_from_unit(candidate: MovementCandidate, other_id: int) -> int:
	if not _units.has(other_id):
		return 1

	var direction: Vector2 = _candidate_base_direction(candidate)

	if direction == Vector2.ZERO:
		return 1 if candidate.unit_id < other_id else -1

	var right: Vector2 = Vector2(-direction.y, direction.x)
	var lateral: float = (_units[other_id].position - candidate.start_position).dot(right)
	var preferred: int = 1

	if absf(lateral) <= 0.25:
		preferred = 1 if candidate.unit_id < other_id else -1
	else:
		preferred = -1 if lateral > 0.0 else 1

	var step_distance: float = maxf(candidate.max_step_distance, candidate.desired_step_distance)
	var preferred_end: Vector2 = candidate.start_position + direction.rotated(
		AVOID_PRIMARY_ANGLE * float(preferred)
	) * step_distance

	if navigation_service.segment_clear(
		candidate.start_position,
		preferred_end,
		candidate.half_size
	):
		return preferred

	var opposite: int = -preferred
	var opposite_end: Vector2 = candidate.start_position + direction.rotated(
		AVOID_PRIMARY_ANGLE * float(opposite)
	) * step_distance

	if navigation_service.segment_clear(
		candidate.start_position,
		opposite_end,
		candidate.half_size
	):
		return opposite

	return preferred


func _resolve_unit_motion(
	candidate: MovementCandidate,
	working_snapshots: Dictionary[int, Snapshot],
	neighbors: Array,
	dt: float,
	near_arrival: bool
) -> int:
	var plan: AvoidancePlan = null

	if _avoidance_by_unit.has(candidate.unit_id):
		plan = _avoidance_by_unit[candidate.unit_id]

	var base_direction: Vector2 = _candidate_base_direction(candidate)

	if base_direction == Vector2.ZERO:
		return MOTION_BLOCKED

	var primary_angles: Array[float] = []
	var secondary_angles: Array[float] = []

	if plan != null:
		primary_angles = _angles_for_plan(plan, near_arrival)
		secondary_angles = _angles_for_side(-plan.side, near_arrival)
	else:
		primary_angles = _angles_without_plan(candidate.unit_id, near_arrival)

	var step_distance: float = candidate.max_step_distance

	if candidate.final_tick and near_arrival:
		step_distance = candidate.desired_step_distance

	if step_distance <= EPSILON:
		return MOTION_BLOCKED

	if plan != null and plan.corridor_yield:
		return _resolve_corridor_yield_motion(
			candidate,
			plan,
			step_distance,
			working_snapshots,
			neighbors,
			dt
		)

	if plan != null and plan.corridor_follow:
		return _resolve_corridor_follow_motion(
			candidate,
			plan,
			base_direction,
			step_distance,
			working_snapshots,
			neighbors,
			dt,
			near_arrival
		)

	var all_angle_sets: Array = [primary_angles]

	if not secondary_angles.is_empty():
		all_angle_sets.append(secondary_angles)

	var speed_ratios: Array[float] = _avoid_speed_ratios()
	var preferred_speed: float = step_distance / maxf(dt, EPSILON)
	var preferred_velocity: Vector2 = base_direction * preferred_speed
	var previous_velocity: Vector2 = Vector2.ZERO

	if _units.has(candidate.unit_id):
		previous_velocity = _units[candidate.unit_id].movement.sim_velocity

	var best_score: float = 1.0e30
	var best_position: Vector2 = candidate.start_position
	var best_angle: float = 0.0
	var best_ratio: float = 0.0
	var best_finish: bool = false
	var map_blocked_candidate_found: bool = false
	var map_clear_candidate_found: bool = false

	for set_index: int in range(all_angle_sets.size()):
		var angles: Array[float] = all_angle_sets[set_index]

		for angle: float in angles:
			var direction: Vector2 = base_direction.rotated(angle)

			for speed_ratio: float in speed_ratios:
				var position: Vector2 = _quantize_vec(
					candidate.start_position
					+ direction * step_distance * speed_ratio
				)

				if near_arrival and not _makes_arrival_progress(candidate, position):
					continue

				if not _map_segment_clear(candidate, position):
					map_blocked_candidate_found = true
					continue

				map_clear_candidate_found = true

				if not _position_clear_of_units(
					candidate,
					position,
					working_snapshots,
					neighbors
				):
					continue

				var velocity: Vector2 = (position - candidate.start_position) / maxf(dt, EPSILON)
				var score: float = _velocity_candidate_score(
					candidate,
					velocity,
					preferred_velocity,
					previous_velocity,
					angle,
					speed_ratio,
					plan
				)

				if set_index > 0:
					score += avoid_side_change_penalty

				if score >= best_score - EPSILON:
					continue

				best_score = score
				best_position = position
				best_angle = angle
				best_ratio = speed_ratio
				best_finish = (
					candidate.finish_order
					and absf(angle) <= EPSILON
					and speed_ratio >= 1.0 - EPSILON
					and position.distance_squared_to(candidate.desired_position) <= EPSILON
				)

	if best_ratio <= EPSILON:
		if map_clear_candidate_found:
			return MOTION_BLOCKED

		if map_blocked_candidate_found:
			return MOTION_MAP_BLOCKED

		return MOTION_BLOCKED

	_apply_position(candidate, best_position, dt, best_finish)

	if plan != null:
		if absf(best_angle) > EPSILON:
			var chosen_side: int = 1 if best_angle > 0.0 else -1

			if chosen_side != plan.side:
				plan.side = chosen_side
				_set_pair_memory_side(candidate.unit_id, plan.other_id, plan.side)

		plan.selected_angle = best_angle

	return MOTION_RESOLVED


func _resolve_corridor_yield_motion(
	candidate: MovementCandidate,
	plan: AvoidancePlan,
	step_distance: float,
	working_snapshots: Dictionary[int, Snapshot],
	neighbors: Array,
	dt: float
) -> int:
	var forward: Vector2 = plan.pass_direction.normalized()

	if forward == Vector2.ZERO:
		forward = _candidate_base_direction(candidate)

	if forward == Vector2.ZERO:
		return MOTION_BLOCKED

	var reverse_direction: Vector2 = -forward

	for speed_ratio: float in _avoid_speed_ratios():
		var position: Vector2 = _quantize_vec(
			candidate.start_position
			+ reverse_direction * step_distance * speed_ratio
		)

		if not _position_clear_of_units(
			candidate,
			position,
			working_snapshots,
			neighbors
		):
			continue

		if not _map_segment_clear(candidate, position):
			continue

		_apply_position(candidate, position, dt, false)
		plan.selected_angle = PI
		return MOTION_RESOLVED

	return MOTION_BLOCKED


func _resolve_corridor_follow_motion(
	candidate: MovementCandidate,
	plan: AvoidancePlan,
	base_direction: Vector2,
	step_distance: float,
	working_snapshots: Dictionary[int, Snapshot],
	neighbors: Array,
	dt: float,
	near_arrival: bool
) -> int:
	if not working_snapshots.has(plan.other_id):
		return MOTION_BLOCKED

	var forward: Vector2 = plan.pass_direction.normalized()

	if forward == Vector2.ZERO:
		forward = base_direction.normalized()

	if forward == Vector2.ZERO:
		return MOTION_BLOCKED

	var leader: Snapshot = working_snapshots[plan.other_id]
	var follower_forward: float = _aabb_support(candidate.half_size, forward)
	var leader_forward: float = _aabb_support(leader.half_size, forward)
	var required_gap: float = follower_forward + leader_forward + CORRIDOR_QUEUE_GAP
	var forward_gap: float = (leader.position - candidate.start_position).dot(forward)

	if forward_gap < required_gap - EPSILON:
		var needed_back: float = required_gap - forward_gap
		var reverse_distance: float = minf(step_distance, needed_back)

		for speed_ratio: float in _avoid_speed_ratios():
			var move_distance: float = reverse_distance * speed_ratio

			if move_distance <= EPSILON:
				continue

			var position: Vector2 = _quantize_vec(
				candidate.start_position - forward * move_distance
			)

			if not _position_clear_of_units(
				candidate,
				position,
				working_snapshots,
				neighbors
			):
				continue

			if not _map_segment_clear(candidate, position):
				continue

			_apply_position(candidate, position, dt, false)
			plan.selected_angle = PI
			return MOTION_RESOLVED

		return MOTION_BLOCKED

	var available_forward: float = maxf(0.0, forward_gap - required_gap)
	var map_blocked: bool = false

	for speed_ratio: float in _avoid_speed_ratios():
		var delta: Vector2 = base_direction * step_distance * speed_ratio
		var projected_advance: float = delta.dot(forward)

		if projected_advance > available_forward + EPSILON:
			continue

		var position: Vector2 = _quantize_vec(
			candidate.start_position + delta
		)

		if near_arrival and not _makes_arrival_progress(candidate, position):
			continue

		if not _position_clear_of_units(
			candidate,
			position,
			working_snapshots,
			neighbors
		):
			continue

		if not _map_segment_clear(candidate, position):
			map_blocked = true
			continue

		var finish_order: bool = (
			candidate.finish_order
			and speed_ratio >= 1.0 - EPSILON
			and position.distance_squared_to(candidate.desired_position) <= EPSILON
		)

		_apply_position(candidate, position, dt, finish_order)
		plan.selected_angle = 0.0
		return MOTION_RESOLVED

	if map_blocked:
		return MOTION_MAP_BLOCKED

	return MOTION_BLOCKED


func _resolve_fixed_waypoint_motion(
	candidate: MovementCandidate,
	plan: AvoidancePlan,
	working_snapshots: Dictionary[int, Snapshot],
	neighbors: Array,
	dt: float
) -> int:
	if not _units.has(plan.other_id):
		plan.fixed_waypoint_active = false
		plan.bypass_phase = 0
		return MOTION_BLOCKED

	var step_distance: float = candidate.max_step_distance

	if step_distance <= EPSILON:
		return MOTION_BLOCKED

	var target: Vector2 = plan.bypass_lateral_target

	if plan.bypass_phase == 0:
		if candidate.start_position.distance_to(plan.bypass_lateral_target) <= maxf(
			step_distance,
			STATIC_BYPASS_REACH_DISTANCE
		):
			plan.bypass_phase = 1
			target = plan.bypass_forward_target
	else:
		target = plan.bypass_forward_target

	var to_target: Vector2 = target - candidate.start_position

	if to_target.length_squared() <= EPSILON:
		if plan.bypass_phase == 0:
			plan.bypass_phase = 1
			target = plan.bypass_forward_target
			to_target = target - candidate.start_position
		else:
			return MOTION_RESOLVED

	if to_target.length_squared() <= EPSILON:
		return MOTION_RESOLVED

	var move_distance: float = minf(step_distance, to_target.length())
	var direction: Vector2 = to_target.normalized()
	var full_position: Vector2 = _quantize_vec(
		candidate.start_position + direction * move_distance
	)

	if not _map_segment_clear(candidate, full_position):
		return MOTION_MAP_BLOCKED

	if not _position_clear_of_units(
		candidate,
		full_position,
		working_snapshots,
		neighbors
	):
		return MOTION_BLOCKED

	_apply_position(candidate, full_position, dt, false)

	if plan.bypass_phase == 0:
		if full_position.distance_to(plan.bypass_lateral_target) <= STATIC_BYPASS_REACH_DISTANCE:
			plan.bypass_phase = 1
			plan.fixed_waypoint = plan.bypass_forward_target
	else:
		if full_position.distance_to(plan.bypass_forward_target) <= STATIC_BYPASS_REACH_DISTANCE:
			plan.clear_ticks = PLAN_CLEAR_TICKS

	return MOTION_RESOLVED


func _angles_for_plan(plan: AvoidancePlan, near_arrival: bool) -> Array[float]:
	var result: Array[float] = []
	var used: Dictionary[int, bool] = {}
	var side: float = 1.0 if plan.side >= 0 else -1.0
	var selected: float = plan.selected_angle

	_append_angle(result, used, 0.0, near_arrival)
	_append_angle(result, used, selected, near_arrival)
	_append_angle(result, used, AVOID_SMALL_ANGLE * side, near_arrival)
	_append_angle(result, used, AVOID_MEDIUM_ANGLE * side, near_arrival)
	_append_angle(result, used, AVOID_PRIMARY_ANGLE * side, near_arrival)
	_append_angle(result, used, AVOID_LARGE_ANGLE * side, near_arrival)
	_append_angle(result, used, AVOID_WIDE_ANGLE * side, near_arrival)
	_append_angle(result, used, AVOID_SIDE_ANGLE * side, near_arrival)
	_append_angle(result, used, AVOID_REAR_SOFT_ANGLE * side, near_arrival)
	_append_angle(result, used, AVOID_REAR_MEDIUM_ANGLE * side, near_arrival)
	_append_angle(result, used, AVOID_REAR_WIDE_ANGLE * side, near_arrival)
	_append_angle(result, used, AVOID_REVERSE_ANGLE, near_arrival)
	return result


func _angles_for_side(side_value: int, near_arrival: bool) -> Array[float]:
	var result: Array[float] = []
	var used: Dictionary[int, bool] = {}
	var side: float = 1.0 if side_value >= 0 else -1.0
	_append_angle(result, used, AVOID_PRIMARY_ANGLE * side, near_arrival)
	_append_angle(result, used, AVOID_LARGE_ANGLE * side, near_arrival)
	_append_angle(result, used, AVOID_MEDIUM_ANGLE * side, near_arrival)
	_append_angle(result, used, AVOID_WIDE_ANGLE * side, near_arrival)
	_append_angle(result, used, AVOID_SMALL_ANGLE * side, near_arrival)
	_append_angle(result, used, AVOID_SIDE_ANGLE * side, near_arrival)
	_append_angle(result, used, AVOID_REAR_SOFT_ANGLE * side, near_arrival)
	_append_angle(result, used, AVOID_REAR_MEDIUM_ANGLE * side, near_arrival)
	_append_angle(result, used, AVOID_REAR_WIDE_ANGLE * side, near_arrival)
	_append_angle(result, used, AVOID_REVERSE_ANGLE, near_arrival)
	return result


func _angles_without_plan(unit_id: int, near_arrival: bool) -> Array[float]:
	var result: Array[float] = []
	var used: Dictionary[int, bool] = {}
	var side: float = 1.0 if unit_id % 2 == 0 else -1.0
	_append_angle(result, used, 0.0, near_arrival)
	_append_angle(result, used, AVOID_MEDIUM_ANGLE * side, near_arrival)
	_append_angle(result, used, -AVOID_MEDIUM_ANGLE * side, near_arrival)
	_append_angle(result, used, AVOID_PRIMARY_ANGLE * side, near_arrival)
	_append_angle(result, used, -AVOID_PRIMARY_ANGLE * side, near_arrival)
	_append_angle(result, used, AVOID_LARGE_ANGLE * side, near_arrival)
	_append_angle(result, used, -AVOID_LARGE_ANGLE * side, near_arrival)
	_append_angle(result, used, AVOID_SIDE_ANGLE * side, near_arrival)
	_append_angle(result, used, -AVOID_SIDE_ANGLE * side, near_arrival)
	_append_angle(result, used, AVOID_REAR_SOFT_ANGLE * side, near_arrival)
	_append_angle(result, used, -AVOID_REAR_SOFT_ANGLE * side, near_arrival)
	_append_angle(result, used, AVOID_REAR_MEDIUM_ANGLE * side, near_arrival)
	_append_angle(result, used, -AVOID_REAR_MEDIUM_ANGLE * side, near_arrival)
	_append_angle(result, used, AVOID_REAR_WIDE_ANGLE * side, near_arrival)
	_append_angle(result, used, -AVOID_REAR_WIDE_ANGLE * side, near_arrival)
	_append_angle(result, used, AVOID_REVERSE_ANGLE, near_arrival)
	return result


func _append_angle(
	result: Array[float],
	used: Dictionary[int, bool],
	angle: float,
	near_arrival: bool
) -> void:
	if near_arrival and absf(angle) > ARRIVAL_MAX_AVOID_ANGLE + EPSILON:
		return

	var key: int = roundi(angle * 1000000.0)

	if used.has(key):
		return

	used[key] = true
	result.append(angle)


func _avoid_speed_ratios() -> Array[float]:
	var result: Array[float] = []
	var minimum: float = clampf(min_avoid_speed_ratio, 0.9, 1.0)
	var step: float = 0.1
	var ratio: float = 1.0

	while ratio > minimum + EPSILON:
		result.append(ratio)
		ratio -= step

	if result.is_empty() or absf(result[result.size() - 1] - minimum) > EPSILON:
		result.append(minimum)

	return result


func _velocity_candidate_score(
	candidate: MovementCandidate,
	velocity: Vector2,
	preferred_velocity: Vector2,
	previous_velocity: Vector2,
	angle: float,
	speed_ratio: float,
	plan: AvoidancePlan
) -> float:
	var speed_scale: float = maxf(
		_units[candidate.unit_id].movement.move_speed if _units.has(candidate.unit_id) else preferred_velocity.length(),
		1.0
	)
	var score: float = (velocity - preferred_velocity).length() / speed_scale

	if previous_velocity.length_squared() > EPSILON:
		score += (velocity - previous_velocity).length() / speed_scale * avoid_previous_velocity_weight

	score += absf(angle) / PI * 0.08
	score += (1.0 - speed_ratio) * 0.03

	if plan != null and absf(angle) > EPSILON:
		var side: int = 1 if angle > 0.0 else -1

		if side != plan.side:
			score += avoid_side_change_penalty

	return score


func _candidate_base_direction(candidate: MovementCandidate) -> Vector2:
	if candidate.desired_velocity.length_squared() > EPSILON:
		return candidate.desired_velocity.normalized()

	var delta: Vector2 = candidate.target_position - candidate.start_position

	if delta.length_squared() > EPSILON:
		return delta.normalized()

	return Vector2.ZERO


func _candidate_near_arrival(candidate: MovementCandidate) -> bool:
	var full_size: float = maxf(candidate.half_size.x * 2.0, candidate.half_size.y * 2.0)
	return candidate.arrival_distance <= maxf(full_size * 1.75, 16.0)


func _makes_arrival_progress(candidate: MovementCandidate, position: Vector2) -> bool:
	return position.distance_to(candidate.arrival_slot) < candidate.start_position.distance_to(candidate.arrival_slot) - EPSILON


func _position_clear_of_units(
	candidate: MovementCandidate,
	position: Vector2,
	snapshots: Dictionary[int, Snapshot],
	neighbors: Array
) -> bool:
	for value: Variant in neighbors:
		var other_id: int = int(value)

		if not snapshots.has(other_id):
			continue

		var other: Snapshot = snapshots[other_id]

		if _rectangles_overlap_strict(
			position,
			candidate.half_size,
			other.position,
			other.half_size
		):
			return false

	return true


func _map_segment_clear(
	candidate: MovementCandidate,
	position: Vector2
) -> bool:
	return navigation_service.segment_clear(
		candidate.start_position,
		position,
		candidate.half_size
	)


func _max_unit_safe_fraction(
	candidate: MovementCandidate,
	direction: Vector2,
	step_distance: float,
	snapshots: Dictionary[int, Snapshot],
	neighbors: Array
) -> float:
	var delta: Vector2 = direction * step_distance
	var upper: float = 1.0

	for value: Variant in neighbors:
		var other_id: int = int(value)

		if not snapshots.has(other_id):
			continue

		var other: Snapshot = snapshots[other_id]
		var expanded_half: Vector2 = Vector2(
			maxf(EPSILON, candidate.half_size.x + other.half_size.x - COLLISION_EPSILON),
			maxf(EPSILON, candidate.half_size.y + other.half_size.y - COLLISION_EPSILON)
		)
		var relative_start: Vector2 = candidate.start_position - other.position
		var entry: float = _segment_aabb_entry_fraction(relative_start, delta, expanded_half)

		if entry >= 0.0:
			upper = minf(upper, maxf(0.0, entry - 0.001))

	return upper


func _segment_aabb_entry_fraction(
	start: Vector2,
	delta: Vector2,
	half: Vector2
) -> float:
	var t_enter: float = 0.0
	var t_exit: float = 1.0

	if absf(delta.x) <= EPSILON:
		if start.x <= -half.x or start.x >= half.x:
			return -1.0
	else:
		var tx1: float = (-half.x - start.x) / delta.x
		var tx2: float = (half.x - start.x) / delta.x

		if tx1 > tx2:
			var temp_x: float = tx1
			tx1 = tx2
			tx2 = temp_x

		t_enter = maxf(t_enter, tx1)
		t_exit = minf(t_exit, tx2)

		if t_enter >= t_exit - EPSILON:
			return -1.0

	if absf(delta.y) <= EPSILON:
		if start.y <= -half.y or start.y >= half.y:
			return -1.0
	else:
		var ty1: float = (-half.y - start.y) / delta.y
		var ty2: float = (half.y - start.y) / delta.y

		if ty1 > ty2:
			var temp_y: float = ty1
			ty1 = ty2
			ty2 = temp_y

		t_enter = maxf(t_enter, ty1)
		t_exit = minf(t_exit, ty2)

		if t_enter >= t_exit - EPSILON:
			return -1.0

	if t_exit <= EPSILON:
		return -1.0

	if t_enter > 1.0:
		return -1.0

	return maxf(0.0, t_enter)


func _repair_final_conflicts(
	candidates: Array[MovementCandidate],
	candidate_by_id: Dictionary[int, MovementCandidate],
	neighbors_by_id: Dictionary[int, Array],
	dt: float
) -> void:
	for _pass: int in range(FINAL_REPAIR_PASSES):
		var snapshots: Dictionary[int, Snapshot] = _build_snapshots(candidate_by_id, false)
		var conflicts: Array[PairConflict] = _collect_conflicts(candidates, snapshots, neighbors_by_id)
		var map_blocked_ids: Array[int] = []

		for candidate: MovementCandidate in candidates:
			if not _map_segment_clear(candidate, candidate.position):
				map_blocked_ids.append(candidate.unit_id)

		if conflicts.is_empty() and map_blocked_ids.is_empty():
			return

		var stop_ids: Dictionary[int, bool] = {}

		for conflict: PairConflict in conflicts:
			var loser: int = _choose_conflict_loser(conflict, candidate_by_id)

			if loser < 0 or not candidate_by_id.has(loser):
				continue

			var loser_candidate: MovementCandidate = candidate_by_id[loser]
			var loser_neighbors: Array = neighbors_by_id.get(loser, [])

			if _try_slow_candidate(
				loser_candidate,
				snapshots,
				loser_neighbors,
				dt
			):
				_update_snapshot(snapshots, loser_candidate)
			else:
				stop_ids[loser] = true

		for unit_id: int in map_blocked_ids:
			if candidate_by_id.has(unit_id):
				_handle_map_blocked_candidate(candidate_by_id[unit_id], dt)
				stop_ids[unit_id] = true

		for unit_id: int in stop_ids:
			if candidate_by_id.has(unit_id):
				_stop_candidate(candidate_by_id[unit_id], dt)

	var final_snapshots: Dictionary[int, Snapshot] = _build_snapshots(candidate_by_id, false)
	var final_conflicts: Array[PairConflict] = _collect_conflicts(candidates, final_snapshots, neighbors_by_id)
	var final_stop_ids: Dictionary[int, bool] = {}

	for conflict: PairConflict in final_conflicts:
		var loser: int = _choose_conflict_loser(conflict, candidate_by_id)

		if loser >= 0 and candidate_by_id.has(loser):
			var loser_candidate: MovementCandidate = candidate_by_id[loser]
			var loser_neighbors: Array = neighbors_by_id.get(loser, [])

			if _try_slow_candidate(
				loser_candidate,
				final_snapshots,
				loser_neighbors,
				dt
			):
				_update_snapshot(final_snapshots, loser_candidate)
			else:
				final_stop_ids[loser] = true

	for candidate: MovementCandidate in candidates:
		if not _map_segment_clear(candidate, candidate.position):
			_handle_map_blocked_candidate(candidate, dt)
			final_stop_ids[candidate.unit_id] = true

	for unit_id: int in final_stop_ids:
		if candidate_by_id.has(unit_id):
			_stop_candidate(candidate_by_id[unit_id], dt)


func _try_slow_candidate(
	candidate: MovementCandidate,
	snapshots: Dictionary[int, Snapshot],
	neighbors: Array,
	dt: float
) -> bool:
	var delta: Vector2 = candidate.position - candidate.start_position
	var distance: float = delta.length()

	if distance <= EPSILON:
		return false

	var direction: Vector2 = delta / distance
	var ratios: Array[float] = _avoid_speed_ratios()

	for ratio: float in ratios:
		if ratio >= 1.0 - EPSILON:
			continue

		var position: Vector2 = _quantize_vec(
			candidate.start_position + direction * distance * ratio
		)

		if not _position_clear_of_units(candidate, position, snapshots, neighbors):
			continue

		if not _map_segment_clear(candidate, position):
			continue

		_apply_position(candidate, position, dt, false)
		return true

	return false


func _choose_conflict_loser(
	conflict: PairConflict,
	candidate_by_id: Dictionary[int, MovementCandidate]
) -> int:
	if _avoidance_by_unit.has(conflict.a_id):
		var a_plan: AvoidancePlan = _avoidance_by_unit[conflict.a_id]

		if (a_plan.corridor_follow or a_plan.corridor_yield) and a_plan.other_id == conflict.b_id:
			return conflict.a_id

	if _avoidance_by_unit.has(conflict.b_id):
		var b_plan: AvoidancePlan = _avoidance_by_unit[conflict.b_id]

		if (b_plan.corridor_follow or b_plan.corridor_yield) and b_plan.other_id == conflict.a_id:
			return conflict.b_id

	var a_moving: bool = candidate_by_id.has(conflict.a_id)
	var b_moving: bool = candidate_by_id.has(conflict.b_id)

	if a_moving and not b_moving:
		return conflict.a_id

	if b_moving and not a_moving:
		return conflict.b_id

	if not a_moving and not b_moving:
		return -1

	var a: MovementCandidate = candidate_by_id[conflict.a_id]
	var b: MovementCandidate = candidate_by_id[conflict.b_id]

	if a.priority != b.priority:
		return conflict.a_id if a.priority > b.priority else conflict.b_id

	return maxi(conflict.a_id, conflict.b_id)


func _apply_position(
	candidate: MovementCandidate,
	position: Vector2,
	dt: float,
	finish_order: bool
) -> void:
	candidate.position = _quantize_vec(position)
	candidate.velocity = (candidate.position - candidate.start_position) / dt
	candidate.finish_order = finish_order


func _build_snapshots(
	candidate_by_id: Dictionary[int, MovementCandidate],
	use_desired: bool
) -> Dictionary[int, Snapshot]:
	var result: Dictionary[int, Snapshot] = {}

	for unit_id: int in _sorted_unit_ids:
		var unit: Unit = _units[unit_id]
		var snapshot: Snapshot = Snapshot.new()
		snapshot.unit_id = unit_id
		snapshot.position = unit.position
		snapshot.half_size = unit.get_half_size()

		if candidate_by_id.has(unit_id):
			var candidate: MovementCandidate = candidate_by_id[unit_id]
			snapshot.position = candidate.desired_position if use_desired else candidate.position
			snapshot.half_size = candidate.half_size

		result[unit_id] = snapshot

	return result


func _update_snapshot(
	snapshots: Dictionary[int, Snapshot],
	candidate: MovementCandidate
) -> void:
	if not snapshots.has(candidate.unit_id):
		var snapshot: Snapshot = Snapshot.new()
		snapshot.unit_id = candidate.unit_id
		snapshot.half_size = candidate.half_size
		snapshots[candidate.unit_id] = snapshot

	snapshots[candidate.unit_id].position = candidate.position
	snapshots[candidate.unit_id].half_size = candidate.half_size


func _snapshots_separated_with_margin(
	a: Snapshot,
	b: Snapshot,
	margin: float
) -> bool:
	return (
		absf(a.position.x - b.position.x) >= a.half_size.x + b.half_size.x + margin
		or absf(a.position.y - b.position.y) >= a.half_size.y + b.half_size.y + margin
	)


func _rectangles_overlap_strict(
	a_position: Vector2,
	a_half: Vector2,
	b_position: Vector2,
	b_half: Vector2
) -> bool:
	return (
		absf(a_position.x - b_position.x) < a_half.x + b_half.x - COLLISION_EPSILON
		and absf(a_position.y - b_position.y) < a_half.y + b_half.y - COLLISION_EPSILON
	)


func _pair_key(a_id: int, b_id: int) -> String:
	var low_id: int = mini(a_id, b_id)
	var high_id: int = maxi(a_id, b_id)
	return "%d:%d" % [low_id, high_id]


func _set_pair_memory_side(unit_id: int, other_id: int, side: int) -> void:
	var key: String = _pair_key(unit_id, other_id)

	if not _pair_memory.has(key):
		return

	var memory: PairMemory = _pair_memory[key]

	if unit_id == memory.low_id:
		memory.low_side = side
	elif unit_id == memory.high_id:
		memory.high_side = side

	memory.last_tick = simulation_tick


func _cleanup_pair_memory() -> void:
	var remove_keys: Array[String] = []

	for key: String in _pair_memory:
		if simulation_tick - _pair_memory[key].last_tick > PAIR_MEMORY_TICKS:
			remove_keys.append(key)

	for key: String in remove_keys:
		_pair_memory.erase(key)


func _build_start_spatial_hash() -> Dictionary:
	var spatial: Dictionary = {}

	for unit_id: int in _sorted_unit_ids:
		var unit: Unit = _units[unit_id]
		var cell: Vector2i = _spatial_cell(unit.position)

		if not spatial.has(cell):
			spatial[cell] = []

		var bucket: Array = spatial[cell]
		bucket.append(unit_id)

	return spatial


func _query_start_spatial(
	spatial: Dictionary,
	position: Vector2,
	extent: Vector2,
	exclude_id: int
) -> Array:
	var result: Array = []
	var seen: Dictionary[int, bool] = {}
	var min_cell: Vector2i = _spatial_cell(position - extent)
	var max_cell: Vector2i = _spatial_cell(position + extent)

	for y: int in range(min_cell.y, max_cell.y + 1):
		for x: int in range(min_cell.x, max_cell.x + 1):
			var key: Vector2i = Vector2i(x, y)

			if not spatial.has(key):
				continue

			var bucket: Array = spatial[key]

			for value: Variant in bucket:
				var unit_id: int = int(value)

				if unit_id == exclude_id or seen.has(unit_id):
					continue

				seen[unit_id] = true
				result.append(unit_id)

	result.sort()
	return result


func _spatial_cell(position: Vector2) -> Vector2i:
	return Vector2i(
		floori(position.x / candidate_spatial_cell_size),
		floori(position.y / candidate_spatial_cell_size)
	)


func _commit_candidates(candidates: Array[MovementCandidate]) -> void:
	candidates.sort_custom(
		func(a: MovementCandidate, b: MovementCandidate) -> bool:
			return a.unit_id < b.unit_id
	)

	for candidate: MovementCandidate in candidates:
		if not _units.has(candidate.unit_id):
			continue

		var unit: Unit = _units[candidate.unit_id]
		var movement: MovementComponent = unit.movement

		if movement.active_move_order == null:
			continue

		if movement.active_move_order.order_id != candidate.order_id:
			continue

		movement.commit_simulation(
			candidate.position,
			candidate.velocity,
			candidate.finish_order
		)

		if candidate.finish_order:
			_avoidance_by_unit.erase(candidate.unit_id)


func _quantize_vec(value: Vector2) -> Vector2:
	if simulation_quantum <= 0.0:
		return value

	return Vector2(
		round(value.x / simulation_quantum) * simulation_quantum,
		round(value.y / simulation_quantum) * simulation_quantum
	)
