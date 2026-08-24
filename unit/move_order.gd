class_name MoveOrder
extends RefCounted


const EPSILON: float = 0.00001
const FORMATION_GAP: float = 1.0
const MIN_GRID_STEP: float = 8.0
const FORMATION_CANDIDATE_MULTIPLIER: int = 64
const MIN_FORMATION_CANDIDATES: int = 512
const MAX_FORMATION_CANDIDATES: int = 8192
const MAX_SLOT_LOCAL_CHECKS: int = 32
const SLOT_DEPTH_WEIGHT: float = 2.0
const SLOT_LATERAL_WEIGHT: float = 0.7
const SLOT_RADIUS_WEIGHT: float = 0.15


var order_id: int = 0
var issued_tick: int = 0
var target_world: Vector2 = Vector2.ZERO
var member_ids: Array[int] = []
var arrival_radius: float = 0.0

var _navigation_service: NavigationService
var _arrival_center: Vector2 = Vector2.ZERO
var _group_start_center: Vector2 = Vector2.ZERO
var _approach_direction: Vector2 = Vector2.RIGHT
var _approach_right: Vector2 = Vector2.DOWN
var _slot_by_unit: Dictionary[int, Vector2] = {}
var _priority_by_unit: Dictionary[int, int] = {}
var _claimed_slots: Array[ClaimedSlot] = []
var _grid_step: float = MIN_GRID_STEP
var _formation_span: float = 32.0


class ClaimedSlot:
	var unit_id: int = -1
	var position: Vector2 = Vector2.ZERO
	var half_size: Vector2 = Vector2.ZERO


class SlotOption:
	var position: Vector2 = Vector2.ZERO
	var score: float = 0.0
	var spiral_index: int = 0


class UnitOrderInfo:
	var unit_id: int = -1
	var front: float = 0.0
	var lateral: float = 0.0
	var distance_to_target: float = 0.0


func _init(
	p_order_id: int,
	p_issued_tick: int,
	p_target_world: Vector2,
	p_member_ids: Array[int],
	p_navigation_service: NavigationService
) -> void:
	order_id = p_order_id
	issued_tick = p_issued_tick
	target_world = p_target_world
	member_ids = p_member_ids.duplicate()
	member_ids.sort()
	_navigation_service = p_navigation_service


func start(units: Dictionary[int, Unit]) -> void:
	if _navigation_service == null:
		push_error("MoveOrder에 NavigationService가 없습니다.")
		return

	_group_start_center = _average_member_position(units)
	var largest_half: Vector2 = _largest_member_half_size(units)
	var anchor_path: PackedVector2Array = _navigation_service.find_path(
		_group_start_center,
		target_world,
		largest_half
	)

	if not anchor_path.is_empty():
		_arrival_center = anchor_path[anchor_path.size() - 1]
	else:
		_arrival_center = _navigation_service.nearest_placeable_point(
			target_world,
			largest_half,
			_group_start_center
		)

	var approach_delta: Vector2 = _arrival_center - _group_start_center

	if anchor_path.size() >= 2:
		approach_delta = anchor_path[anchor_path.size() - 1] - anchor_path[anchor_path.size() - 2]

	if approach_delta.length_squared() > EPSILON:
		_approach_direction = approach_delta.normalized()
	else:
		_approach_direction = Vector2.RIGHT

	_approach_right = Vector2(-_approach_direction.y, _approach_direction.x)
	_prepare_formation_metrics(units)
	_assign_slots(units)

	for unit_id: int in member_ids:
		if not units.has(unit_id):
			continue

		var unit: Unit = units[unit_id]
		var slot: Vector2 = _slot_by_unit.get(unit_id, _arrival_center)
		var path: PackedVector2Array = _navigation_service.find_path(
			unit.position,
			slot,
			unit.get_half_size()
		)

		if path.is_empty():
			var fallback: Vector2 = _navigation_service.nearest_placeable_point(
				slot,
				unit.get_half_size(),
				unit.position
			)
			path = _navigation_service.find_path(
				unit.position,
				fallback,
				unit.get_half_size()
			)

			if not path.is_empty():
				_slot_by_unit[unit_id] = path[path.size() - 1]

		if path.is_empty():
			path.append(unit.position)

		unit.movement.begin_move_order(self, path)

	_update_arrival_radius(units)


func simulate(
	dt: float,
	all_units: Dictionary[int, Unit]
) -> Array[MovementCandidate]:
	var result: Array[MovementCandidate] = []

	for unit_id: int in member_ids:
		if not all_units.has(unit_id):
			continue

		var unit: Unit = all_units[unit_id]
		var movement: MovementComponent = unit.movement

		if not _owns_movement(movement):
			continue

		if movement.is_paused():
			movement.reset_sim_velocity()
			continue

		movement.sync_path_progress(movement.move_speed * dt, _navigation_service)
		result.append(_make_candidate(unit, movement, dt))

	return result


func is_finished(all_units: Dictionary[int, Unit]) -> bool:
	for unit_id: int in member_ids:
		if not all_units.has(unit_id):
			continue

		if _owns_movement(all_units[unit_id].movement):
			return false

	return true


func get_arrival_center() -> Vector2:
	return _arrival_center


func get_arrival_slot(unit_id: int) -> Vector2:
	return _slot_by_unit.get(unit_id, _arrival_center)


func get_unit_priority(unit_id: int) -> int:
	return _priority_by_unit.get(unit_id, 2147483647)


func is_unit_near_arrival(unit_id: int, position: Vector2, full_size: float) -> bool:
	if not _slot_by_unit.has(unit_id):
		return false

	return position.distance_to(_slot_by_unit[unit_id]) <= maxf(full_size * 1.5, 12.0)


func _make_candidate(
	unit: Unit,
	movement: MovementComponent,
	dt: float
) -> MovementCandidate:
	var candidate: MovementCandidate = MovementCandidate.new()
	var slot: Vector2 = _slot_by_unit.get(unit.unit_id, movement.get_effective_goal())
	var desired_velocity: Vector2 = movement.get_desired_velocity(dt)
	var desired_position: Vector2 = unit.position + desired_velocity * dt
	var final_tick: bool = movement.wants_final_tick(dt)

	if final_tick:
		desired_position = movement.get_effective_goal()

		if dt > EPSILON:
			desired_velocity = (desired_position - unit.position) / dt

	candidate.order_id = order_id
	candidate.unit_id = unit.unit_id
	candidate.start_position = unit.position
	candidate.desired_position = desired_position
	candidate.position = desired_position
	candidate.desired_velocity = desired_velocity
	candidate.velocity = desired_velocity
	candidate.target_position = movement.get_current_waypoint()
	candidate.half_size = unit.get_half_size()
	candidate.max_step_distance = movement.move_speed * dt
	candidate.desired_step_distance = unit.position.distance_to(desired_position)
	candidate.final_tick = final_tick
	candidate.finish_order = final_tick
	candidate.arrival_active = true
	candidate.arrival_slot = slot
	candidate.arrival_distance = unit.position.distance_to(slot)
	candidate.priority = get_unit_priority(unit.unit_id)
	return candidate


func _owns_movement(movement: MovementComponent) -> bool:
	if movement == null:
		return false

	if movement.active_move_order == null:
		return false

	return movement.active_move_order.order_id == order_id


func _prepare_formation_metrics(units: Dictionary[int, Unit]) -> void:
	var min_full: float = 1000000.0
	var max_full: float = 1.0
	var valid_count: int = 0

	for unit_id: int in member_ids:
		if not units.has(unit_id):
			continue

		var unit: Unit = units[unit_id]
		var full_size: float = maxf(unit.footprint_size.x, unit.footprint_size.y)
		var min_dimension: float = minf(unit.footprint_size.x, unit.footprint_size.y)
		min_full = minf(min_full, min_dimension)
		max_full = maxf(max_full, full_size)
		valid_count += 1

	if valid_count == 0:
		_grid_step = MIN_GRID_STEP
		_formation_span = 32.0
		return

	_grid_step = maxf(MIN_GRID_STEP, min_full * 0.5 + FORMATION_GAP)
	_formation_span = maxf(
		max_full * 2.0,
		sqrt(float(valid_count)) * max_full * 1.1
	)


func _assign_slots(units: Dictionary[int, Unit]) -> void:
	_slot_by_unit.clear()
	_priority_by_unit.clear()
	_claimed_slots.clear()

	var infos: Array[UnitOrderInfo] = []

	for unit_id: int in member_ids:
		if not units.has(unit_id):
			continue

		var unit: Unit = units[unit_id]
		var info: UnitOrderInfo = UnitOrderInfo.new()
		var relative: Vector2 = unit.position - _group_start_center
		info.unit_id = unit_id
		info.front = relative.dot(_approach_direction)
		info.lateral = relative.dot(_approach_right)
		info.distance_to_target = unit.position.distance_to(_arrival_center)
		infos.append(info)

	infos.sort_custom(
		func(a: UnitOrderInfo, b: UnitOrderInfo) -> bool:
			if absf(a.front - b.front) > EPSILON:
				return a.front > b.front

			if absf(a.distance_to_target - b.distance_to_target) > EPSILON:
				return a.distance_to_target < b.distance_to_target

			return a.unit_id < b.unit_id
	)

	var candidate_count: int = clampi(
		maxi(MIN_FORMATION_CANDIDATES, infos.size() * FORMATION_CANDIDATE_MULTIPLIER),
		MIN_FORMATION_CANDIDATES,
		MAX_FORMATION_CANDIDATES
	)
	var offsets: Array[Vector2i] = _square_spiral_offsets(candidate_count)
	var total: int = infos.size()

	for rank: int in range(total):
		var info: UnitOrderInfo = infos[rank]
		var unit: Unit = units[info.unit_id]
		var t: float = 0.5

		if total > 1:
			t = float(rank) / float(total - 1)

		var desired_depth: float = lerpf(_formation_span * 0.55, -_formation_span * 0.55, t)
		var desired_lateral: float = clampf(
			info.lateral,
			-_formation_span * 0.6,
			_formation_span * 0.6
		)
		var slot: Vector2 = _find_slot_for_unit(
			unit,
			desired_depth,
			desired_lateral,
			offsets
		)
		_slot_by_unit[info.unit_id] = slot
		_priority_by_unit[info.unit_id] = rank

		var claimed: ClaimedSlot = ClaimedSlot.new()
		claimed.unit_id = info.unit_id
		claimed.position = slot
		claimed.half_size = unit.get_half_size()
		_claimed_slots.append(claimed)


func _find_slot_for_unit(
	unit: Unit,
	desired_depth: float,
	desired_lateral: float,
	offsets: Array[Vector2i]
) -> Vector2:
	var options: Array[SlotOption] = []
	var half_size: Vector2 = unit.get_half_size()

	for index: int in range(offsets.size()):
		var offset: Vector2i = offsets[index]
		var local: Vector2 = Vector2(
			float(offset.x) * _grid_step,
			float(offset.y) * _grid_step
		)
		var position: Vector2 = _arrival_center + local

		if not _navigation_service.can_place_static(position, half_size):
			continue

		if _overlaps_claimed(position, half_size):
			continue

		var relative: Vector2 = position - _arrival_center
		var depth: float = relative.dot(_approach_direction)
		var lateral: float = relative.dot(_approach_right)
		var option: SlotOption = SlotOption.new()
		option.position = position
		option.spiral_index = index
		option.score = (
			absf(depth - desired_depth) * SLOT_DEPTH_WEIGHT
			+ absf(lateral - desired_lateral) * SLOT_LATERAL_WEIGHT
			+ relative.length() * SLOT_RADIUS_WEIGHT
			+ float(index) * 0.0001
		)
		options.append(option)

	options.sort_custom(
		func(a: SlotOption, b: SlotOption) -> bool:
			if absf(a.score - b.score) > EPSILON:
				return a.score < b.score

			return a.spiral_index < b.spiral_index
	)

	var local_checks: int = mini(MAX_SLOT_LOCAL_CHECKS, options.size())

	for index: int in range(local_checks):
		var option: SlotOption = options[index]

		if _navigation_service.segment_clear(_arrival_center, option.position, half_size):
			return option.position

	var fallback: Vector2 = _navigation_service.nearest_placeable_point(
		_arrival_center,
		half_size,
		unit.position
	)

	if not _overlaps_claimed(fallback, half_size):
		var fallback_path: PackedVector2Array = _navigation_service.find_path(
			unit.position,
			fallback,
			half_size
		)

		if not fallback_path.is_empty():
			return fallback_path[fallback_path.size() - 1]

	for option: SlotOption in options:
		if not _overlaps_claimed(option.position, half_size):
			return option.position

	return unit.position


func _overlaps_claimed(position: Vector2, half_size: Vector2) -> bool:
	for claimed: ClaimedSlot in _claimed_slots:
		if (
			absf(position.x - claimed.position.x)
			< half_size.x + claimed.half_size.x + FORMATION_GAP
			and absf(position.y - claimed.position.y)
			< half_size.y + claimed.half_size.y + FORMATION_GAP
		):
			return true

	return false


func _square_spiral_offsets(count: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []

	if count <= 0:
		return result

	var position: Vector2i = Vector2i.ZERO
	result.append(position)

	if count == 1:
		return result

	var directions: Array[Vector2i] = [
		Vector2i(0, -1),
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(-1, 0),
	]
	var direction_index: int = 0
	var step_length: int = 1

	while result.size() < count:
		for _pair_step: int in range(2):
			var direction: Vector2i = directions[direction_index]

			for _step: int in range(step_length):
				position += direction
				result.append(position)

				if result.size() >= count:
					return result

			direction_index = (direction_index + 1) % directions.size()

		step_length += 1

	return result


func _average_member_position(units: Dictionary[int, Unit]) -> Vector2:
	var sum: Vector2 = Vector2.ZERO
	var count: int = 0

	for unit_id: int in member_ids:
		if not units.has(unit_id):
			continue

		sum += units[unit_id].position
		count += 1

	if count == 0:
		return target_world

	return sum / float(count)


func _largest_member_half_size(units: Dictionary[int, Unit]) -> Vector2:
	var result: Vector2 = Vector2(8.0, 8.0)

	for unit_id: int in member_ids:
		if not units.has(unit_id):
			continue

		var half_size: Vector2 = units[unit_id].get_half_size()
		result.x = maxf(result.x, half_size.x)
		result.y = maxf(result.y, half_size.y)

	return result


func _update_arrival_radius(units: Dictionary[int, Unit]) -> void:
	arrival_radius = 0.0

	for unit_id: int in member_ids:
		if not _slot_by_unit.has(unit_id):
			continue

		var half_extent: float = 0.0

		if units.has(unit_id):
			var half_size: Vector2 = units[unit_id].get_half_size()
			half_extent = maxf(half_size.x, half_size.y)

		arrival_radius = maxf(
			arrival_radius,
			_arrival_center.distance_to(_slot_by_unit[unit_id]) + half_extent
		)
