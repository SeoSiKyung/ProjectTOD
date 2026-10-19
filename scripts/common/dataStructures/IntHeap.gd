@abstract
class_name IntHeap
extends RefCounted

var _values: Array[int] = []
var _positions: PackedInt32Array


func _init(positions: PackedInt32Array) -> void:
	_positions = positions


@abstract func _Less(a: int, b: int) -> bool


func IsEmpty() -> bool:
	return _values.is_empty()


func Size() -> int:
	return _values.size()


func Contains(value: int) -> bool:
	return value >= 0 and value < _positions.size() and _positions[value] >= 0


func Clear() -> void:
	for value: int in _values:
		_positions[value] = -1

	_values.clear()


func Peek() -> int:
	if _values.is_empty():
		push_error("Cannot peek an empty IntHeap.")
		return -1

	return _values[0]


func Pop() -> int:
	if _values.is_empty():
		push_error("Cannot pop an empty IntHeap.")
		return -1

	var root: int = _values[0]
	var last: int = _values.pop_back()
	_positions[root] = -1
	if not _values.is_empty():
		_values[0] = last
		_positions[last] = 0
		_SiftDown(0)

	return root


func PushOrUpdate(value: int) -> bool:
	if value < 0 or value >= _positions.size():
		push_error("IntHeap key is out of range: %d" % value)
		return false

	var position: int = _positions[value]
	if position < 0:
		_values.append(value)
		position = _values.size() - 1
		_positions[value] = position
		_SiftUp(position)
		return true

	if position > 0:
		var parentPosition: int = (position - 1) >> 1
		if _Less(value, _values[parentPosition]):
			_SiftUp(position)
			return false

	_SiftDown(position)
	return false


func _SiftUp(position: int) -> void:
	var value: int = _values[position]
	var index: int = position
	while index > 0:
		var parentIndex: int = (index - 1) >> 1
		var parent: int = _values[parentIndex]
		if not _Less(value, parent):
			break

		_values[index] = parent
		_positions[parent] = index
		index = parentIndex

	if index != position:
		_values[index] = value
		_positions[value] = index


func _SiftDown(position: int) -> void:
	var value: int = _values[position]
	var index: int = position
	var heapSize: int = _values.size()
	while true:
		var left: int = index * 2 + 1
		var right: int = left + 1
		var smallest: int = index
		var smallestValue: int = value
		if left < heapSize and _Less(_values[left], smallestValue):
			smallest = left
			smallestValue = _values[left]
		if right < heapSize and _Less(_values[right], smallestValue):
			smallest = right
			smallestValue = _values[right]
		if smallest == index:
			break

		_values[index] = smallestValue
		_positions[smallestValue] = index
		index = smallest

	if index != position:
		_values[index] = value
		_positions[value] = index
