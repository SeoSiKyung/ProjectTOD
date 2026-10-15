class_name UnitIdList
extends RefCounted

const EOA: int = -1
var _capacity: int
var _idx: int = 0
var _values: PackedInt32Array

func _init(capacity: int = 1000) -> void:
	Reserve(capacity)
	Clear()


func Clear() -> void:
	_idx = 0
	_values[0] = EOA
	

func Reserve(capacity: int) -> void:
	if _capacity <= _idx:
		return
	_capacity = capacity
	_values.resize(_capacity)

	
func Size() -> int:
	return _idx

func IsEmpty() -> bool:
	return _idx == 0


func At(idx: int) -> int:
	return _values[idx]

func Append(value: int) -> void:
	_values[_idx] = value
	_idx += 1
	if (_idx >= _capacity):
		_capacity *= 2
		_values.resize(_capacity)
	_values[_idx] = EOA
