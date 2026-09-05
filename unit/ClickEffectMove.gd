extends Node2D

@export var radius: float = 18.0
@export var duration: float = 0.25
@export var lineWidth: float = 3.0


func _ready() -> void:
	scale = Vector2(0.6, 0.6)

	var tween := create_tween()

	tween.set_parallel(true)

	tween.tween_property(self, "scale", Vector2(1.4, 1.4), duration)

	tween.tween_property(self, "modulate:a", 0.0, duration)

	tween.chain().tween_callback(queue_free)


func _draw() -> void:
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, Color(0.3, 1.0, 0.4), lineWidth)

	draw_circle(Vector2.ZERO, 3.0, Color(0.3, 1.0, 0.4))
