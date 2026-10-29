class_name NavigationPathHeap
extends IntHeap

var _state: NavigationPathSearchState


func _init(state: NavigationPathSearchState) -> void:
	_state = state
	super(state.heapPosition)


func _Less(aIndex: int, bIndex: int) -> bool:
	if not Math.IsNearlyEqual(_state.f[aIndex], _state.f[bIndex]):
		return _state.f[aIndex] < _state.f[bIndex]

	if not Math.IsNearlyEqual(_state.turnCost[aIndex], _state.turnCost[bIndex]):
		return _state.turnCost[aIndex] < _state.turnCost[bIndex]

	if not Math.IsNearlyEqual(_state.h[aIndex], _state.h[bIndex]):
		return _state.h[aIndex] < _state.h[bIndex]

	return aIndex < bIndex
