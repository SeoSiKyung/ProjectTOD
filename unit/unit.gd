extends Node2D
class_name Unit

@export var unitId: int = 0
@export_range(8, 256, 2) var footprintSize: int = 32
@export var playerControllable: bool = true
@export var moveSpeed: float = 96.0

@onready var fsm: UnitFSM = $UnitFSM


func _ready() -> void:
	fsm.BindUnit(self)
	add_to_group("unit")


func GetFootprintSize() -> int:
	return footprintSize


func GetHalfSize() -> int:
	return footprintSize / 2


func CanReceiveCommands() -> bool:
	return fsm != null and fsm.CanReceiveCommands()


func ApplyStun(duration: float) -> void:
	if fsm == null:
		return

	fsm.ApplyStun(duration)


func Die() -> void:
	if fsm == null:
		return

	fsm.Die()
