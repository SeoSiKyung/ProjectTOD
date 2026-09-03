class_name AttackCommand
extends UnitCommand

const INVALID_UNIT_ID: int = -1

var targetUnitId: int = INVALID_UNIT_ID


func _init(pUnitIds: PackedInt32Array, pTargetUnitId: int) -> void:
	super(pUnitIds)
	targetUnitId = pTargetUnitId
