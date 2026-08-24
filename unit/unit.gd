extends Node2D
class_name Unit


@export var unit_id: int = 0
@export var player_controllable: bool = true
@export var footprint_size: Vector2 = Vector2(32.0, 32.0)
@export var move_speed: float = 96.0


@onready var movement: MovementComponent = $MovementComponent
@onready var fsm: UnitFSM = $UnitFSM


func _ready() -> void:
	fsm.bind_unit(self)
	add_to_group("unit")


func get_half_size() -> Vector2:
	return footprint_size * 0.5


func can_receive_commands() -> bool:
	return fsm != null and fsm.can_receive_commands()


func apply_stun(duration: float) -> void:
	if fsm == null:
		return

	fsm.apply_stun(duration)


func die() -> void:
	if fsm == null:
		return

	fsm.die()
