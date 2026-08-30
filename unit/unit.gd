extends Node2D
class_name Unit

const footprintSize: int = 32

@export var unitId: int = 0
@export var playerControllable: bool = true
@export var direction: int = 0



@onready var _fsm: UnitFSM = $UnitFSM

func _ready() -> void:
	_fsm.BindUnit(self)
	add_to_group("unit")

func GetHalfSize() -> int:
	return footprintSize * 0.5

func CanReceiveCommands() -> bool:
	return _fsm != null and _fsm.CanReceiveCommands()

func ApplyStun(duration: float) -> void:
	if _fsm == null:
		return

	_fsm.ApplyStun(duration)

func Die() -> void:
	if _fsm == null:
		return

	_fsm.Die()
