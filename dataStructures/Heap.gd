@tool
class_name Heap
extends RefCounted


class IndexTracker:
	func GetPosition(_value: Variant) -> int:
		return -1


	func SetPosition(_value: Variant, _position: int) -> void:
		pass


	func Remove(value: Variant) -> void:
		SetPosition(value, -1)


class PackedInt32IndexTracker extends IndexTracker:
	var _positions: PackedInt32Array


	func _init(positions: PackedInt32Array) -> void:
		_positions = positions


	func GetPositions() -> PackedInt32Array:
		return _positions


	func GetPosition(value: Variant) -> int:
		var key: int = int(value)
		if key < 0 or key >= _positions.size():
			return -1

		return _positions[key]


	func SetPosition(value: Variant, position: int) -> void:
		var key: int = int(value)
		if key < 0 or key >= _positions.size():
			push_error("Heap index key is out of range: %d" % key)
			return

		_positions[key] = position


class DictionaryIndexTracker extends IndexTracker:
	var _positions: Dictionary = { }


	func GetPosition(value: Variant) -> int:
		return int(_positions.get(value, -1))


	func SetPosition(value: Variant, position: int) -> void:
		if position < 0:
			_positions.erase(value)
			return

		_positions[value] = position


var _values: Array = []
var _less: Callable
var _indexTracker: IndexTracker
var _packedIntPositions: PackedInt32Array = PackedInt32Array()
var _usePackedIntFastPath: bool = false


func _init(less: Callable, indexTracker: IndexTracker = null) -> void:
	_less = less
	_indexTracker = indexTracker

	if indexTracker is PackedInt32IndexTracker:
		var tracker: PackedInt32IndexTracker = (indexTracker as PackedInt32IndexTracker)
		_packedIntPositions = tracker.GetPositions()
		_usePackedIntFastPath = true


func IsEmpty() -> bool:
	return _values.is_empty()


func Size() -> int:
	return _values.size()


func Clear() -> void:
	if _indexTracker != null:
		for value: Variant in _values:
			_indexTracker.Remove(value)

	_values.clear()


func Peek() -> Variant:
	if _values.is_empty():
		push_error("Cannot peek an empty heap.")
		return null

	return _values[0]


func Push(value: Variant) -> void:
	if _indexTracker != null and _GetPosition(value) >= 0:
		push_error("Heap already contains the value. " + "Use PushOrDecrease() for indexed heaps.")
		return

	_values.append(value)

	var position: int = _values.size() - 1
	_SetPosition(value, position)

	_SiftUp(position)


func PushOrDecrease(value: Variant) -> bool:
	if _indexTracker == null:
		push_error("PushOrDecrease() requires an index tracker.")
		return false

	var position: int = _GetPosition(value)

	# 아직 힙에 없음
	if position < 0:
		_values.append(value)

		position = _values.size() - 1
		_SetPosition(value, position)

		_SiftUp(position)
		return true

	# 이미 존재함.
	# 외부에서 priority 값이 작아졌다고 가정하고 위로 이동.
	_SiftUp(position)

	return false


func Pop() -> Variant:
	if _values.is_empty():
		push_error("Cannot pop an empty heap.")
		return null

	var root: Variant = _values[0]
	var last: Variant = _values.pop_back()

	if _usePackedIntFastPath:
		_packedIntPositions[int(root)] = -1
	else:
		_RemovePosition(root)

	if _values.is_empty():
		return root

	_values[0] = last

	if _usePackedIntFastPath:
		_packedIntPositions[int(last)] = 0
	else:
		_SetPosition(last, 0)

	_SiftDown(0)

	return root


func _SiftUp(position: int) -> void:
	var index: int = position

	while index > 0:
		var parentIndex: int = int(index - 1) >> 1
		if not bool(_less.call(_values[index], _values[parentIndex])):
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

		if left < heapSize:
			if bool(_less.call(_values[left], _values[smallest])):
				smallest = left

		if right < heapSize:
			if bool(_less.call(_values[right], _values[smallest])):
				smallest = right

		if smallest == index:
			break

		_Swap(index, smallest)

		index = smallest


func _Swap(a: int, b: int) -> void:
	var temp: Variant = _values[a]
	_values[a] = _values[b]
	_values[b] = temp

	if _usePackedIntFastPath:
		var aKey: int = int(_values[a])
		var bKey: int = int(_values[b])

		_packedIntPositions[aKey] = a
		_packedIntPositions[bKey] = b
		return

	_SetPosition(_values[a], a)
	_SetPosition(_values[b], b)


func _SetPosition(value: Variant, position: int) -> void:
	if _usePackedIntFastPath:
		var key: int = int(value)
		if (key < 0 or key >= _packedIntPositions.size()):
			push_error("Heap index key is out of range: %d" % key)
			return

		_packedIntPositions[key] = position
		return

	if _indexTracker != null:
		_indexTracker.SetPosition(value, position)


func _RemovePosition(value: Variant) -> void:
	if _usePackedIntFastPath:
		var key: int = int(value)
		if (key >= 0 and key < _packedIntPositions.size()):
			_packedIntPositions[key] = -1

		return

	if _indexTracker != null:
		_indexTracker.Remove(value)


func _GetPosition(value: Variant) -> int:
	if _usePackedIntFastPath:
		var key: int = int(value)
		if (key < 0 or key >= _packedIntPositions.size()):
			return -1

		return _packedIntPositions[key]

	if _indexTracker == null:
		return -1

	return _indexTracker.GetPosition(value)
