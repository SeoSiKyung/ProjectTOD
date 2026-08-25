extends Node2D
class_name Unit

@export var unitId: int = 0
@export var playerControllable: bool = true
@export var footprintSize: Vector2 = Vector2(32.0, 32.0)
@export var moveSpeed: float = 96.0

@onready var movement: MovementComponent = $MovementComponent
@onready var fsm: UnitFSM = $UnitFSM


func _ready() -> void:
	fsm.BindUnit(self)
	add_to_group("unit")


func GetHalfSize() -> Vector2:
	return footprintSize * 0.5


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
