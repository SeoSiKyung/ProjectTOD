class_name NavigationService
extends Node

const EPSILON: float = 0.00001
const CONTACT_EPSILON: float = 0.001
const BIG_NUMBER: float = 1.0e30
const SQRT_2: float = 1.41421356237

@export var NavigationData: NavigationData
@export_range(0.0, 2.0, 0.05) var static_contact_slop: float = 1.0

var _navigation_ready: bool = false
var _nav_cell_size: float = 8.0
var _grid_width: int = 0
var _grid_height: int = 0
var _world_rect: Rect2 = Rect2()
var _blocked: PackedByteArray = PackedByteArray()
var _prefix_sum: PackedInt32Array = PackedInt32Array()

var _path_g: PackedFloat64Array = PackedFloat64Array()
var _path_turn_cost: PackedFloat64Array = PackedFloat64Array()
var _path_parent: PackedInt32Array = PackedInt32Array()
var _path_incoming_direction: PackedInt32Array = PackedInt32Array()
var _path_closed: PackedByteArray = PackedByteArray()


class HeapEntry:
	var index: int = 0
	var f: float = 0.0
	var h: float = 0.0
	var turn: float = 0.0
	var g: float = 0.0


	func _init(p_index: int, p_f: float, p_h: float, p_turn: float, p_g: float) -> void:
		index = p_index
		f = p_f
		h = p_h
		turn = p_turn
		g = p_g


const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(1, 1),
	Vector2i(0, 1),
	Vector2i(-1, 1),
	Vector2i(-1, 0),
	Vector2i(-1, -1),
	Vector2i(0, -1),
	Vector2i(1, -1),
]


func _ready() -> void:
	_loadNavigationData()


func IsReady() -> bool:
	return _navigation_ready


func Reload() -> void:
	_loadNavigationData()


func _loadNavigationData() -> void:
	_navigation_ready = false

	if NavigationData == null:
		push_error("NavigationData가 지정되지 않았습니다.")
		return

	_nav_cell_size = float(NavigationData.cellSize)
	_grid_width = NavigationData.gridSize.x
	_grid_height = NavigationData.gridSize.y
	_world_rect = NavigationData.GetWorldRect()
	_blocked = NavigationData.blocked
	_prefix_sum = NavigationData.prefixSum

	if _nav_cell_size <= 0.0:
		push_error("NavigationData의 cell_size가 잘못되었습니다.")
		return

	var expected_blocked: int = _grid_width * _grid_height
	var expected_prefix: int = (_grid_width + 1) * (_grid_height + 1)

	if _blocked.size() != expected_blocked:
		push_error("NavigationData의 blocked 크기가 잘못되었습니다.")
		return

	if _prefix_sum.size() != expected_prefix:
		push_error("NavigationData의 prefix_sum 크기가 잘못되었습니다.")
		return

	_ensurePathBuffers()
	_navigation_ready = true


func _ensurePathBuffers() -> void:
	var total: int = _grid_width * _grid_height

	if _path_g.size() == total:
		return

	_path_g.resize(total)
	_path_turn_cost.resize(total)
	_path_parent.resize(total)
	_path_incoming_direction.resize(total)
	_path_closed.resize(total)


func _resetPathBuffers() -> void:
	_path_g.fill(BIG_NUMBER)
	_path_turn_cost.fill(BIG_NUMBER)
	_path_parent.fill(-1)
	_path_incoming_direction.fill(-1)
	_path_closed.fill(0)


func _collisionHalf(a_half: Vector2, b_half: Vector2) -> Vector2:
	return Vector2(
		maxf(EPSILON, a_half.x + b_half.x - CONTACT_EPSILON),
		maxf(EPSILON, a_half.y + b_half.y - CONTACT_EPSILON),
	)


func _segmentAabbEntryFraction(start: Vector2, delta: Vector2, half: Vector2) -> float:
	var t_min: float = 0.0
	var t_max: float = 1.0

	if absf(delta.x) <= EPSILON:
		if start.x < -half.x or start.x > half.x:
			return -1.0
	else:
		var tx1: float = (-half.x - start.x) / delta.x
		var tx2: float = (half.x - start.x) / delta.x

		if tx1 > tx2:
			var temp_x: float = tx1
			tx1 = tx2
			tx2 = temp_x

		t_min = maxf(t_min, tx1)
		t_max = minf(t_max, tx2)

		if t_min > t_max:
			return -1.0

	if absf(delta.y) <= EPSILON:
		if start.y < -half.y or start.y > half.y:
			return -1.0
	else:
		var ty1: float = (-half.y - start.y) / delta.y
		var ty2: float = (half.y - start.y) / delta.y

		if ty1 > ty2:
			var temp_y: float = ty1
			ty1 = ty2
			ty2 = temp_y

		t_min = maxf(t_min, ty1)
		t_max = minf(t_max, ty2)

		if t_min > t_max:
			return -1.0

	if t_max < 0.0:
		return -1.0

	if t_min > 1.0:
		return -1.0

	return clampf(t_min, 0.0, 1.0)


func _segmentIntersectsCenteredAabb(start: Vector2, end: Vector2, half: Vector2) -> bool:
	return _segmentAabbEntryFraction(start, end - start, half) >= 0.0


func SegmentClear(start: Vector2, end: Vector2, half_size: Vector2) -> bool:
	return _segmentStaticClear(start, end, half_size)


func _prefixRectCount(x0: int, y0: int, x1: int, y1: int) -> int:
	var width: int = (_grid_width + 1)

	return (
		_prefix_sum[y1 * width + x1] - _prefix_sum[y0 * width + x1] - _prefix_sum[y1 * width + x0]
		+ _prefix_sum[y0 * width + x0]
	)


func CanPlaceStatic(center: Vector2, half_size: Vector2) -> bool:
	return _canPlaceStaticWithHalf(center, _staticHalfSize(half_size))


func _staticHalfSize(half_size: Vector2) -> Vector2:
	var slop: float = maxf(static_contact_slop, 0.0)

	return Vector2(maxf(0.0, half_size.x - slop), maxf(0.0, half_size.y - slop))


func _canPlaceStaticWithHalf(center: Vector2, half_size: Vector2) -> bool:
	var world_end: Vector2 = _world_rect.position + _world_rect.size
	var rect_min: Vector2 = center - half_size
	var rect_max: Vector2 = center + half_size

	if rect_min.x < _world_rect.position.x - EPSILON:
		return false

	if rect_min.y < _world_rect.position.y - EPSILON:
		return false

	if rect_max.x > world_end.x + EPSILON:
		return false

	if rect_max.y > world_end.y + EPSILON:
		return false

	var local_min: Vector2 = rect_min - _world_rect.position
	var local_max: Vector2 = rect_max - _world_rect.position
	var min_x: int = floori((local_min.x + EPSILON) / _nav_cell_size)
	var min_y: int = floori((local_min.y + EPSILON) / _nav_cell_size)
	var max_x: int = floori((local_max.x - EPSILON) / _nav_cell_size)
	var max_y: int = floori((local_max.y - EPSILON) / _nav_cell_size)

	min_x = clampi(min_x, 0, _grid_width - 1)
	min_y = clampi(min_y, 0, _grid_height - 1)
	max_x = clampi(max_x, 0, _grid_width - 1)
	max_y = clampi(max_y, 0, _grid_height - 1)

	return _prefixRectCount(min_x, min_y, max_x + 1, max_y + 1) == 0


func NearestPlaceablePoint(
	world_position: Vector2,
	half_size: Vector2,
	reference_position: Vector2,
) -> Vector2:
	if CanPlaceStatic(world_position, half_size):
		return world_position

	var path_offset: Vector2 = _pathLatticeOffset(half_size)
	var center_cell: Vector2i = _worldToNearestPathCell(world_position, path_offset)
	center_cell.x = clampi(center_cell.x, 0, _grid_width - 1)
	center_cell.y = clampi(center_cell.y, 0, _grid_height - 1)
	var max_radius: int = maxi(_grid_width, _grid_height)

	for radius: int in range(max_radius + 1):
		var best: Vector2i = Vector2i(-1, -1)
		var best_target_distance: float = BIG_NUMBER
		var best_reference_distance: float = BIG_NUMBER

		for y: int in range(center_cell.y - radius, center_cell.y + radius + 1):
			for x: int in range(center_cell.x - radius, center_cell.x + radius + 1):
				var ring_distance: int = maxi(absi(x - center_cell.x), absi(y - center_cell.y))

				if ring_distance != radius:
					continue

				var cell: Vector2i = Vector2i(x, y)

				if not _validCell(cell):
					continue

				var point: Vector2 = _pathPoint(cell, path_offset)

				if not CanPlaceStatic(point, half_size):
					continue

				var target_distance: float = point.distance_squared_to(world_position)
				var reference_distance: float = point.distance_squared_to(reference_position)
				var better: bool = false

				if target_distance < best_target_distance - EPSILON:
					better = true
				elif absf(target_distance - best_target_distance) <= EPSILON:
					if reference_distance < best_reference_distance - EPSILON:
						better = true
					elif absf(reference_distance - best_reference_distance) <= EPSILON:
						if best.x < 0 or y < best.y or (y == best.y and x < best.x):
							better = true

				if not better:
					continue

				best = cell
				best_target_distance = target_distance
				best_reference_distance = reference_distance

		if best.x >= 0:
			return _pathPoint(best, path_offset)

	return world_position


func FindPath(
	start_world: Vector2,
	target_world: Vector2,
	half_size: Vector2,
) -> PackedVector2Array:
	var empty: PackedVector2Array = (PackedVector2Array())

	if not _navigation_ready:
		return empty

	var path_offset: Vector2 = _pathLatticeOffset(half_size)

	var start_cell: Vector2i = (_nearestValidPathCell(start_world, half_size, path_offset))

	if start_cell.x < 0:
		return empty

	var goal_cell: Vector2i = (_nearestValidPathCell(target_world, half_size, path_offset))

	if goal_cell.x < 0:
		return empty

	_ensurePathBuffers()
	_resetPathBuffers()

	var start_index: int = (_cellIndex(start_cell))

	var goal_index: int = (_cellIndex(goal_cell))

	_path_g[start_index] = 0.0
	_path_turn_cost[start_index] = 0.0

	var heap: Array[HeapEntry] = []

	var start_h: float = (_octileHeuristic(start_cell, goal_cell))

	_heapPush(heap, HeapEntry.new(start_index, start_h, start_h, 0.0, 0.0))

	var best_index: int = start_index

	var best_target_distance: float = (
		_pathPoint(start_cell, path_offset).distance_squared_to(target_world)
	)

	var found_goal: bool = false

	while not heap.is_empty():
		var entry: HeapEntry = (_heapPop(heap))

		var current_index: int = (entry.index)

		if _path_closed[current_index] != 0:
			continue

		if (absf(entry.g - _path_g[current_index]) > EPSILON):
			continue

		_path_closed[current_index] = 1

		var current_cell: Vector2i = (_indexCell(current_index))

		var current_world: Vector2 = (_pathPoint(current_cell, path_offset))

		var target_distance: float = (current_world.distance_squared_to(target_world))

		if (target_distance < best_target_distance - EPSILON):
			best_target_distance = (target_distance)

			best_index = current_index

		elif (
			absf(target_distance - best_target_distance) <= EPSILON and current_index < best_index
		):
			best_index = current_index

		if current_index == goal_index:
			found_goal = true
			best_index = current_index
			break

		var previous_direction: int = (_path_incoming_direction[current_index])

		for dir_index: int in range(DIRECTIONS.size()):
			var direction: Vector2i = (DIRECTIONS[dir_index])

			var next_cell: Vector2i = (current_cell + direction)

			if not _validCell(next_cell):
				continue

			var next_index: int = (_cellIndex(next_cell))

			if _path_closed[next_index] != 0:
				continue

			var next_world: Vector2 = (_pathPoint(next_cell, path_offset))

			if not CanPlaceStatic(next_world, half_size):
				continue

			if (direction.x != 0 and direction.y != 0):
				var horizontal: Vector2i = (Vector2i(current_cell.x + direction.x, current_cell.y))

				var vertical: Vector2i = (Vector2i(current_cell.x, current_cell.y + direction.y))

				if (not _validCell(horizontal) or not _validCell(vertical)):
					continue

				if not CanPlaceStatic(_pathPoint(horizontal, path_offset), half_size):
					continue

				if not CanPlaceStatic(_pathPoint(vertical, path_offset), half_size):
					continue

			var step_cost: float = 1.0

			if (direction.x != 0 and direction.y != 0):
				step_cost = SQRT_2

			var tentative_g: float = (_path_g[current_index] + step_cost)

			var direction_change: float = 0.0

			if previous_direction >= 0:
				var difference: int = absi(dir_index - previous_direction)

				difference = mini(difference, 8 - difference)

				direction_change = float(difference)

			var tentative_turn: float = (_path_turn_cost[current_index] + direction_change)

			var better: bool = false

			if (tentative_g < _path_g[next_index] - EPSILON):
				better = true

			elif (
				absf(tentative_g - _path_g[next_index]) <= EPSILON
				and tentative_turn < _path_turn_cost[next_index] - EPSILON
			):
				better = true

			if not better:
				continue

			_path_g[next_index] = tentative_g

			_path_turn_cost[next_index] = (tentative_turn)

			_path_parent[next_index] = (current_index)

			_path_incoming_direction[next_index] = dir_index

			var h: float = (_octileHeuristic(next_cell, goal_cell))

			_heapPush(
				heap,
				HeapEntry.new(next_index, tentative_g + h, h, tentative_turn, tentative_g),
			)

	var destination_index: int = (best_index)

	if found_goal:
		destination_index = goal_index

	var raw_path: Array[Vector2] = (
		_reconstructPath(_path_parent, start_index, destination_index, path_offset)
	)

	if raw_path.is_empty():
		return empty

	var last: Vector2 = (raw_path[raw_path.size() - 1])

	var final_point: Vector2 = (_furthestStaticClearPoint(last, target_world, half_size))

	if (last.distance_squared_to(final_point) > EPSILON):
		raw_path.append(final_point)

	return _simplifyPath(start_world, raw_path, half_size)


func _furthestStaticClearPoint(start: Vector2, target: Vector2, half_size: Vector2) -> Vector2:
	if (start.distance_squared_to(target) <= EPSILON):
		return start

	if _segmentStaticClear(start, target, half_size):
		return target

	var low: float = 0.0
	var high: float = 1.0

	for _iteration: int in range(24):
		var mid: float = ((low + high) * 0.5)

		var point: Vector2 = (start.lerp(target, mid))

		if _segmentStaticClear(start, point, half_size):
			low = mid
		else:
			high = mid

	return start.lerp(target, low)


func _nearestValidPathCell(
	world_position: Vector2,
	half_size: Vector2,
	path_offset: Vector2,
) -> Vector2i:
	var center_cell: Vector2i = (_worldToNearestPathCell(world_position, path_offset))

	center_cell.x = clampi(center_cell.x, 0, _grid_width - 1)
	center_cell.y = clampi(center_cell.y, 0, _grid_height - 1)
	var max_radius: int = maxi(_grid_width, _grid_height)

	for radius: int in range(max_radius + 1):
		var best: Vector2i = Vector2i(-1, -1)
		var best_distance: float = BIG_NUMBER

		for y: int in range(center_cell.y - radius, center_cell.y + radius + 1):
			for x: int in range(center_cell.x - radius, center_cell.x + radius + 1):
				var ring_distance: int = maxi(absi(x - center_cell.x), absi(y - center_cell.y))

				if ring_distance != radius:
					continue

				var cell: Vector2i = Vector2i(x, y)

				if not _validCell(cell):
					continue

				var point: Vector2 = _pathPoint(cell, path_offset)

				if not CanPlaceStatic(point, half_size):
					continue

				var distance: float = point.distance_squared_to(world_position)

				if distance < best_distance - EPSILON:
					best_distance = distance
					best = cell
				elif absf(distance - best_distance) <= EPSILON:
					if (best.x < 0 or y < best.y or (y == best.y and x < best.x)):
						best = cell

		if best.x >= 0:
			return best

	return Vector2i(-1, -1)


func _octileHeuristic(a: Vector2i, b: Vector2i) -> float:
	var dx: int = absi(a.x - b.x)

	var dy: int = absi(a.y - b.y)

	var diagonal: int = mini(dx, dy)

	var straight: int = (maxi(dx, dy) - diagonal)

	return (float(diagonal) * SQRT_2 + float(straight))


func _reconstructPath(
	parent: PackedInt32Array,
	start_index: int,
	destination_index: int,
	path_offset: Vector2,
) -> Array[Vector2]:
	var reversed: Array[Vector2] = []

	var current: int = destination_index

	while current >= 0:
		reversed.append(_pathPoint(_indexCell(current), path_offset))

		if current == start_index:
			break

		current = parent[current]

	if (reversed.is_empty() or current != start_index):
		return []

	reversed.reverse()

	return reversed


func _simplifyPath(
	actual_start: Vector2,
	raw_path: Array[Vector2],
	half_size: Vector2,
) -> PackedVector2Array:
	var result: PackedVector2Array = (PackedVector2Array())

	if raw_path.is_empty():
		return result

	var anchor: Vector2 = actual_start
	var index: int = 0

	while index < raw_path.size():
		var farthest: int = index

		for candidate_index: int in range(raw_path.size() - 1, index - 1, -1):
			if _segmentStaticClear(anchor, raw_path[candidate_index], half_size):
				farthest = candidate_index
				break

		var point: Vector2 = (raw_path[farthest])

		if (anchor.distance_squared_to(point) > EPSILON):
			result.append(point)

		anchor = point
		index = farthest + 1

	return result


func _segmentStaticClear(start: Vector2, end: Vector2, half_size: Vector2) -> bool:
	var static_half: Vector2 = _staticHalfSize(half_size)
	var start_valid: bool = _canPlaceStaticWithHalf(start, static_half)
	var end_valid: bool = _canPlaceStaticWithHalf(end, static_half)

	if not end_valid:
		return false

	if not start_valid:
		return _segmentStaticClearRecovering(start, end, static_half)

	return _segmentStaticClearValidStart(start, end, static_half)


func _segmentStaticClearRecovering(start: Vector2, end: Vector2, half_size: Vector2) -> bool:
	var delta: Vector2 = end - start

	if delta.length_squared() <= EPSILON:
		return false

	var recovery_limit: float = maxf(_nav_cell_size * 0.5, maxf(static_contact_slop, 0.0) * 4.0)

	if delta.length() > recovery_limit + EPSILON:
		return false

	var first_valid: Vector2 = end
	var found_valid: bool = false

	for step: int in range(1, 9):
		var t: float = float(step) / 8.0
		var point: Vector2 = start.lerp(end, t)

		if _canPlaceStaticWithHalf(point, half_size):
			first_valid = point
			found_valid = true
			break

	if not found_valid:
		return false

	return _segmentStaticClearValidStart(first_valid, end, half_size)


func _segmentStaticClearValidStart(start: Vector2, end: Vector2, half_size: Vector2) -> bool:
	var broad_min: Vector2 = Vector2(minf(start.x, end.x), minf(start.y, end.y)) - half_size

	var broad_max: Vector2 = Vector2(maxf(start.x, end.x), maxf(start.y, end.y)) + half_size

	var min_cell: Vector2i = _worldToCellFloor(broad_min)
	var max_cell: Vector2i = _worldToCellFloor(broad_max)

	min_cell.x = clampi(min_cell.x, 0, _grid_width - 1)
	min_cell.y = clampi(min_cell.y, 0, _grid_height - 1)
	max_cell.x = clampi(max_cell.x, 0, _grid_width - 1)
	max_cell.y = clampi(max_cell.y, 0, _grid_height - 1)

	for y: int in range(min_cell.y, max_cell.y + 1):
		for x: int in range(min_cell.x, max_cell.x + 1):
			if not _isBlockedCell(x, y):
				continue

			var rect: Rect2 = _cellRect(Vector2i(x, y))
			var center: Vector2 = rect.position + rect.size * 0.5
			var expanded_half: Vector2 = _collisionHalf(half_size, rect.size * 0.5)

			if _segmentIntersectsCenteredAabb(start - center, end - center, expanded_half):
				return false

	return true


func _heapLess(a: HeapEntry, b: HeapEntry) -> bool:
	if absf(a.f - b.f) > EPSILON:
		return a.f < b.f

	if (absf(a.turn - b.turn) > EPSILON):
		return a.turn < b.turn

	if absf(a.h - b.h) > EPSILON:
		return a.h < b.h

	return a.index < b.index


func _heapPush(heap: Array[HeapEntry], entry: HeapEntry) -> void:
	heap.append(entry)

	var index: int = (heap.size() - 1)

	while index > 0:
		var parent_index: int = int((index - 1) / 2)

		if not _heapLess(heap[index], heap[parent_index]):
			break

		var temp: HeapEntry = (heap[index])

		heap[index] = (heap[parent_index])

		heap[parent_index] = temp

		index = parent_index


func _heapPop(heap: Array[HeapEntry]) -> HeapEntry:
	var root: HeapEntry = heap[0]

	var last_index: int = (heap.size() - 1)

	var last: HeapEntry = (heap[last_index])

	heap.remove_at(last_index)

	if heap.is_empty():
		return root

	heap[0] = last

	var index: int = 0

	while true:
		var left: int = (index * 2 + 1)

		var right: int = (left + 1)

		var smallest: int = index

		if (left < heap.size() and _heapLess(heap[left], heap[smallest])):
			smallest = left

		if (right < heap.size() and _heapLess(heap[right], heap[smallest])):
			smallest = right

		if smallest == index:
			break

		var temp: HeapEntry = (heap[index])

		heap[index] = (heap[smallest])

		heap[smallest] = temp

		index = smallest

	return root


func _validCell(cell: Vector2i) -> bool:
	return (cell.x >= 0 and cell.y >= 0 and cell.x < _grid_width and cell.y < _grid_height)


func _cellIndex(cell: Vector2i) -> int:
	return (cell.y * _grid_width + cell.x)


func _indexCell(index: int) -> Vector2i:
	return Vector2i(index % _grid_width, int(index / _grid_width))


func _pathLatticeOffset(half_size: Vector2) -> Vector2:
	return Vector2(_latticeAxisOffset(half_size.x), _latticeAxisOffset(half_size.y))


func _latticeAxisOffset(half_extent: float) -> float:
	var offset: float = fposmod(maxf(half_extent, 0.0), _nav_cell_size)

	if offset <= EPSILON or _nav_cell_size - offset <= EPSILON:
		return 0.0

	return offset


func _pathPoint(cell: Vector2i, path_offset: Vector2) -> Vector2:
	return (
		_world_rect.position
		+ Vector2(
			float(cell.x) * _nav_cell_size + path_offset.x,
			float(cell.y) * _nav_cell_size + path_offset.y,
		)
	)


func _worldToNearestPathCell(position: Vector2, path_offset: Vector2) -> Vector2i:
	var local: Vector2 = position - _world_rect.position - path_offset

	return Vector2i(roundi(local.x / _nav_cell_size), roundi(local.y / _nav_cell_size))


func _cellRect(cell: Vector2i) -> Rect2:
	return Rect2(
		_world_rect.position
		+ Vector2(float(cell.x) * _nav_cell_size, float(cell.y) * _nav_cell_size),
		Vector2(_nav_cell_size, _nav_cell_size),
	)


func _worldToCellFloor(position: Vector2) -> Vector2i:
	var local: Vector2 = (position - _world_rect.position)

	return Vector2i(floori(local.x / _nav_cell_size), floori(local.y / _nav_cell_size))


func _isBlockedCell(x: int, y: int) -> bool:
	if (x < 0 or y < 0 or x >= _grid_width or y >= _grid_height):
		return true

	return (_blocked[y * _grid_width + x] != 0)
