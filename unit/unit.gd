extends Node2D
class_name Unit

@export var unit_id: int = 0
@export var player_controllable: bool = true
@export var footprint_size: Vector2 = Vector2(32.0, 32.0)
@export var move_speed: float = 96.0

@onready var movement: MovementComponent = $MovementComponent
@onready var fsm: UnitFSM = $UnitFSM


func _ready() -> void:
	fsm.BindUnit(self)
	add_to_group("unit")


func getHalfSize() -> Vector2:
	return footprint_size * 0.5


func canReceiveCommands() -> bool:
	return fsm != null and fsm.CanReceiveCommands()


func applyStun(duration: float) -> void:
	if fsm == null:
		return

	fsm.ApplyStun(duration)


func Die() -> void:
	if fsm == null:
		return

	fsm.Die()
