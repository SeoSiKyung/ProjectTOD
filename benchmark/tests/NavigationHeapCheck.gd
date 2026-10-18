extends SceneTree


class ReferenceHeap extends RefCounted:
	var state: NavigationPathSearchState


	func _init(searchState: NavigationPathSearchState) -> void:
		state = searchState
		_positions = state.heapPosition


	var _values: Array = []


	func IsEmpty() -> bool:
		return _values.is_empty()


	func Size() -> int:
		return _values.size()


	func Clear() -> void:
		for value: Variant in _values:
			_OnValueRemoved(value)

		_values.clear()


	func Peek() -> Variant:
		if _values.is_empty():
			push_error("Cannot peek an empty heap.")
			return null

		return _values[0]


	func Push(value: Variant) -> void:
		_values.append(value)

		var position: int = _values.size() - 1
		_OnPositionChanged(value, position)

		_SiftUp(position)


	func Pop() -> Variant:
		if _values.is_empty():
			push_error("Cannot pop an empty heap.")
			return null

		var root: Variant = _values[0]
		var last: Variant = _values.pop_back()

		_OnValueRemoved(root)

		if _values.is_empty():
			return root

		_values[0] = last
		_OnPositionChanged(last, 0)

		_SiftDown(0)

		return root


	func _Reheapify(position: int) -> void:
		if not (0 <= position and position < _values.size()):
			return

		if position > 0:
			var parentPosition: int = (position - 1) >> 1
			if _Less(_values[position], _values[parentPosition]):
				_SiftUp(position)
				return

		_SiftDown(position)


	func _SiftUp(position: int) -> void:
		var index: int = position
		while index > 0:
			var parentIndex: int = (index - 1) >> 1
			if not _Less(_values[index], _values[parentIndex]):
				break

			_Swap(index, parentIndex)
			index = parentIndex


	func _SiftDown(position: int) -> void:
		var index: int = position
		var heapSize: int = _values.size()
		while true:
			var left: int = index * 2 + 1
			var right: int = left + 1
			var smallest: int = index

			if left < heapSize and _Less(_values[left], _values[smallest]):
				smallest = left
			if right < heapSize and _Less(_values[right], _values[smallest]):
				smallest = right
			if smallest == index:
				break

			_Swap(index, smallest)
			index = smallest


	func _Swap(a: int, b: int) -> void:
		var temp: Variant = _values[a]
		_values[a] = _values[b]
		_values[b] = temp

		_OnPositionChanged(_values[a], a)
		_OnPositionChanged(_values[b], b)


	var _positions: PackedInt32Array


	func Contains(value: int) -> bool:
		if value < 0 or value >= _positions.size():
			return false

		return _positions[value] >= 0


	func PushOrUpdate(value: int) -> bool:
		if not (0 <= value and value < _positions.size()):
			push_error("Heap index key is out of range: %d" % value)
			return false

		var position: int = _positions[value]
		if position < 0:
			Push(value)
			return true

		_Reheapify(position)
		return false


	func _OnPositionChanged(value: Variant, position: int) -> void:
		_positions[int(value)] = position


	func _OnValueRemoved(value: Variant) -> void:
		_positions[int(value)] = -1


	func _Less(a: Variant, b: Variant) -> bool:
		var aIndex: int = int(a)
		var bIndex: int = int(b)

		if absf(state.f[aIndex] - state.f[bIndex]) > Math.EPSILON:
			return state.f[aIndex] < state.f[bIndex]

		if absf(state.turnCost[aIndex] - state.turnCost[bIndex]) > Math.EPSILON:
			return state.turnCost[aIndex] < state.turnCost[bIndex]

		if absf(state.h[aIndex] - state.h[bIndex]) > Math.EPSILON:
			return state.h[aIndex] < state.h[bIndex]

		return aIndex < bIndex


class BakerReferenceHeap extends ReferenceHeap:
	func _Less(a: Variant, b: Variant) -> bool:
		var ai: int = int(a)
		var bi: int = int(b)
		if absf(state.f[ai] - state.f[bi]) > Math.EPSILON:
			return state.f[ai] < state.f[bi]

		return ai < bi


func _initialize() -> void:
	if not _CheckMode(false) or not _CheckMode(true):
		quit(1)
		return

	print("힙 검증 통과: 길찾기 30000회 / Baker 30000회 / 불일치 0건")
	quit(0)


func _CheckMode(baker: bool) -> bool:
	var oldState: NavigationPathSearchState = NavigationPathSearchState.new()
	var newState: NavigationPathSearchState = NavigationPathSearchState.new()
	var routeState: NavigationBaker.RouteSearchState = NavigationBaker.RouteSearchState.new()
	oldState.Resize(256)
	newState.Resize(256)
	routeState.Resize(256)
	var oldHeap: ReferenceHeap
	var newHeap: IntHeap
	if baker:
		oldHeap = BakerReferenceHeap.new(oldState)
		newHeap = NavigationBaker.RouteHeap.new(routeState)
	else:
		oldHeap = ReferenceHeap.new(oldState)
		newHeap = NavigationPathHeap.new(newState)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20261018
	for step: int in range(30000):
		var action: int = rng.randi_range(0, 99)
		if action < 70:
			var key: int = rng.randi_range(0, 255)
			var f: float = float(rng.randi_range(0, 16)) + float(rng.randi_range(-2, 2)) * Math.EPSILON * 0.75
			var turn: float = float(rng.randi_range(0, 8))
			var h: float = float(rng.randi_range(0, 8))
			for state: NavigationPathSearchState in [oldState, newState]:
				state.f[key] = f
				state.turnCost[key] = turn
				state.h[key] = h

			routeState.f[key] = f

			if oldHeap.PushOrUpdate(key) != newHeap.PushOrUpdate(key):
				return _Fail(step, baker, "삽입·갱신 반환값")

		elif action < 98 and not oldHeap.IsEmpty():
			if int(oldHeap.Pop()) != newHeap.Pop():
				return _Fail(step, baker, "제거 순서")
		else:
			oldHeap.Clear()
			newHeap.Clear()

		var positions: PackedInt32Array = routeState.heapPosition if baker else newState.heapPosition
		if oldHeap._values != newHeap._values or oldState.heapPosition != positions:
			return _Fail(step, baker, "내부 배열 또는 공유 위치 배열")

		for index: int in range(newHeap.Size()):
			if positions[newHeap._values[index]] != index:
				return _Fail(step, baker, "위치 인덱스")

	while not oldHeap.IsEmpty():
		if int(oldHeap.Pop()) != newHeap.Pop():
			return _Fail(30000, baker, "마지막 제거 순서")

	var finalPositions: PackedInt32Array = routeState.heapPosition if baker else newState.heapPosition
	if oldState.heapPosition != finalPositions:
		return _Fail(30000, baker, "마지막 위치 배열")

	return true


func _Fail(step: int, baker: bool, reason: String) -> bool:
	push_error("힙 검증 실패: %s / %d번째 연산 / %s" % ["Baker" if baker else "길찾기", step, reason])
	return false
