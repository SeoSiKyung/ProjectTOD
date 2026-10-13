@abstract
class_name BaseState
extends RefCounted

var _unit: Unit
var _fsm: WeakRef

func _init(unit: Unit, fsm: UnitFSM) -> void:
	_unit = unit
	_fsm = weakref(fsm)

@abstract
func Action() -> void

@abstract
func Get() -> void
