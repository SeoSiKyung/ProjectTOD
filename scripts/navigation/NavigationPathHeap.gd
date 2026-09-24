class_name NavigationPathHeap
extends Heap.IndexedIntHeap

var _state: NavigationPathSearchState


func _init(state: NavigationPathSearchState) -> void:
	_state = state
	super(state.heapPosition)


func _Less(a: Variant, b: Variant) -> bool:
	var aIndex: int = int(a)
	var bIndex: int = int(b)

	if absf(_state.f[aIndex] - _state.f[bIndex]) > Math.EPSILON:
		return _state.f[aIndex] < _state.f[bIndex]

	if absf(_state.turnCost[aIndex] - _state.turnCost[bIndex]) > Math.EPSILON:
		return _state.turnCost[aIndex] < _state.turnCost[bIndex]

	if absf(_state.h[aIndex] - _state.h[bIndex]) > Math.EPSILON:
		return _state.h[aIndex] < _state.h[bIndex]

	return aIndex < bIndex
