@abstract
class_name Heap
extends RefCounted

var _values: Array = []


@abstract func _Less(_a: Variant, _b: Variant) -> bool


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


func _OnPositionChanged(_value: Variant, _position: int) -> void:
	pass


func _OnValueRemoved(_value: Variant) -> void:
	pass


@abstract class IndexedIntHeap extends Heap:
	var _positions: PackedInt32Array


	func _init(positions: PackedInt32Array) -> void:
		_positions = positions


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
