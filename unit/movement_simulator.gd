class_name MovementSimulator
extends Node


const EPSILON: float = 0.00001
const COLLISION_EPSILON: float = 0.0001
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
const STATIC_BLOCKER_STEP_THRESHOLD: float = 0.25
const NEIGHBOR_MARGIN: float = 8.0
const REPATH_RETRY_TICKS: int = 4
const REPATH_GOAL_TOLERANCE: float = 2.0
const MOTION_BLOCKED: int = 0
const MOTION_RESOLVED: int = 1
const MOTION_MAP_BLOCKED: int = 2


@export var navigation_service: NavigationService

@export_range(30, 240, 1)
var fixed_tick_rate: int = 60

@export var simulation_quantum: float = 1.0 / 1024.0
@export var candidate_spatial_cell_size: float = 64.0
@export_range(0.8, 1.0, 0.1) var min_avoid_speed_ratio: float = 0.5
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


class PairMemory:
   var low_id: int = -1
   var high_id: int = -1
   var low_side: int = 1
   var high_side: int = 1
   var last_tick: int = 0


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

	  if direct_map_clear and _try_apply_straight_slowdown(
		 candidate,
		 working_snapshots,
		 neighbors,
		 dt
	  ):
		 _avoidance_by_unit.erase(candidate.unit_id)
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

	  if existing.other_id == blocker_id:
		 existing.side = side

		 if absf(existing.selected_angle) <= EPSILON or existing.selected_angle * float(side) < 0.0:
			existing.selected_angle = AVOID_PRIMARY_ANGLE * float(side)

		 return

   var plan: AvoidancePlan = AvoidancePlan.new()
   plan.other_id = blocker_id
   plan.side = side
   plan.selected_angle = AVOID_PRIMARY_ANGLE * float(side)
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


func _build_current_snapshots() -> Dictionary:
   var result: Dictionary[int, Snapshot] = {}

   for unit_id: int in _sorted_unit_ids:
	  var unit: Unit = _units[unit_id]
	  var snapshot: Snapshot = Snapshot.new()
	  snapshot.unit_id = unit_id
	  snapshot.position = unit.position
	  snapshot.half_size = unit.get_half_size()
	  result[unit_id] = snapshot

   return result


func _handle_map_blocked_candidate(
   candidate: MovementCandidate,
   dt: float
) -> void:
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


func _stop_candidate(
   candidate: MovementCandidate,
   dt: float
) -> void:
   _apply_position(candidate, candidate.start_position, dt, false)


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

   var step_distance: float = candidate.max_step_distance

   if candidate.final_tick and near_arrival:
	  step_distance = candidate.desired_step_distance

   if step_distance <= EPSILON:
	  return MOTION_BLOCKED

   var angle_sets: Array = []

   if plan != null:
	  angle_sets.append(_angles_for_plan(plan, near_arrival))
	  angle_sets.append(_angles_for_side(-plan.side, near_arrival))
   else:
	  angle_sets.append(_angles_without_plan(candidate.unit_id, near_arrival))

   var speed_ratios: Array[float] = _avoid_speed_ratios()
   var preferred_speed: float = step_distance / maxf(dt, EPSILON)
   var preferred_velocity: Vector2 = base_direction * preferred_speed
   var previous_velocity: Vector2 = Vector2.ZERO

   if _units.has(candidate.unit_id):
	  previous_velocity = _units[candidate.unit_id].movement.sim_velocity

   var map_blocked_candidate_found: bool = false
   var map_clear_candidate_found: bool = false
   var best_position: Vector2 = candidate.start_position
   var best_angle: float = 0.0
   var best_ratio: float = 0.0
   var best_finish: bool = false

   for set_index: int in range(angle_sets.size()):
	  var angles: Array = angle_sets[set_index]
	  var set_best_score: float = 1.0e30
	  var set_best_position: Vector2 = candidate.start_position
	  var set_best_angle: float = 0.0
	  var set_best_ratio: float = 0.0
	  var set_best_finish: bool = false

	  for angle_value: Variant in angles:
		 var angle: float = float(angle_value)
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

			if score >= set_best_score - EPSILON:
			   continue

			set_best_score = score
			set_best_position = position
			set_best_angle = angle
			set_best_ratio = speed_ratio
			set_best_finish = (
			   candidate.finish_order
			   and absf(angle) <= EPSILON
			   and speed_ratio >= 1.0 - EPSILON
			   and position.distance_squared_to(candidate.desired_position) <= EPSILON
			)

	  if set_best_ratio > EPSILON:
		 best_position = set_best_position
		 best_angle = set_best_angle
		 best_ratio = set_best_ratio
		 best_finish = set_best_finish
		 break

   if best_ratio <= EPSILON:
	  if map_clear_candidate_found:
		 return MOTION_BLOCKED

	  if map_blocked_candidate_found:
		 return MOTION_MAP_BLOCKED

	  return MOTION_BLOCKED

   _apply_position(candidate, best_position, dt, best_finish)

   if plan != null and absf(best_angle) > EPSILON:
	  var chosen_side: int = 1 if best_angle > 0.0 else -1

	  if chosen_side != plan.side:
		 plan.side = chosen_side
		 _set_pair_memory_side(candidate.unit_id, plan.other_id, plan.side)

	  plan.selected_angle = best_angle

   return MOTION_RESOLVED


func _try_apply_straight_slowdown(
   candidate: MovementCandidate,
   working_snapshots: Dictionary[int, Snapshot],
   neighbors: Array,
   dt: float
) -> bool:
   var base_direction: Vector2 = _candidate_base_direction(candidate)

   if base_direction == Vector2.ZERO:
	  return false

   var step_distance: float = candidate.max_step_distance

   if candidate.final_tick:
	  step_distance = candidate.desired_step_distance

   if step_distance <= EPSILON:
	  return false

   for speed_ratio: float in _avoid_speed_ratios():
	  if speed_ratio >= 1.0 - EPSILON:
		 continue

	  var position: Vector2 = _quantize_vec(
		 candidate.start_position + base_direction * step_distance * speed_ratio
	  )

	  if not _position_clear_of_units(
		 candidate,
		 position,
		 working_snapshots,
		 neighbors
	  ):
		 continue

	  _apply_position(candidate, position, dt, false)
	  return true

   return false


func _angles_for_plan(plan: AvoidancePlan, near_arrival: bool) -> Array[float]:
   var result: Array[float] = []
   var used: Dictionary[int, bool] = {}
   var side: float = 1.0 if plan.side >= 0 else -1.0
   var selected: float = plan.selected_angle

   if absf(selected) <= EPSILON or selected * side <= 0.0:
	  selected = AVOID_PRIMARY_ANGLE * side

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
   var minimum: float = clampf(min_avoid_speed_ratio, 0.5, 1.0)
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


func _apply_position(
   candidate: MovementCandidate,
   position: Vector2,
   dt: float,
   finish_order: bool
) -> void:
   candidate.position = _quantize_vec(position)
   candidate.velocity = (candidate.position - candidate.start_position) / dt
   candidate.finish_order = finish_order


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
