extends Node2D
class_name Unit


@export var unit_id: int = 0
@export var player_controllable: bool = true
@export var footprint_size: Vector2 = Vector2(32.0, 32.0)
@export var move_speed: float = 96.0


@onready var movement: MovementComponent = $MovementComponent


func _ready() -> void:
	add_to_group("unit")


func get_half_size() -> Vector2:
	return footprint_size * 0.5


func set_selected(value: bool) -> void:
	var selection_indicator: Node2D = get_node_or_null("select")

	if selection_indicator != null:
		selection_indicator.visible = value
