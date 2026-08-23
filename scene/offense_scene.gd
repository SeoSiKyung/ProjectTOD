extends Node2D


@onready var movement_controller: MovementController = $MovementController


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event

		if (
			mouse_event.button_index == MOUSE_BUTTON_RIGHT
			and mouse_event.pressed
		):
			var units: Array[Unit] = []

			for node: Node in get_tree().get_nodes_in_group("unit"):
				if node is Unit:
					units.append(node as Unit)

			movement_controller.issue_move_order(
				units,
				get_global_mouse_position()
			)
