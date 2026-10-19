class_name NavigationPathHeap
extends IntHeap

var _state: NavigationPathSearchState


func _init(state: NavigationPathSearchState) -> void:
	_state = state
	super(state.heapPosition)


func _Less(aIndex: int, bIndex: int) -> bool:
	if absf(_state.f[aIndex] - _state.f[bIndex]) > Math.EPSILON:
		return _state.f[aIndex] < _state.f[bIndex]

	if absf(_state.turnCost[aIndex] - _state.turnCost[bIndex]) > Math.EPSILON:
		return _state.turnCost[aIndex] < _state.turnCost[bIndex]

	if absf(_state.h[aIndex] - _state.h[bIndex]) > Math.EPSILON:
		return _state.h[aIndex] < _state.h[bIndex]

	return aIndex < bIndex
