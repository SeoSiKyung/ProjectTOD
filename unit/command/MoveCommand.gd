class_name MoveCommand
extends UnitCommand

var targetWorld: Vector2 = Vector2.ZERO


func _init(pUnitIds: PackedInt32Array, pTargetWorld: Vector2) -> void:
	super(pUnitIds)
	targetWorld = pTargetWorld
