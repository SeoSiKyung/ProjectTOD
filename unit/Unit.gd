extends Node2D
class_name Unit

@export var unitId: int = 0
@export_range(8, 256, 2) var footprintSize: int = 32
@export var playerControllable: bool = true

signal MoveSpeedChanged(moveSpeed: int)
@export var moveSpeed: int = 96:
	set(value):
		if value < 0:
			push_error("Unit: moveSpeed는 0 이상의 값이어야 합니다.")
			return

		if moveSpeed == value:
			return

		moveSpeed = value
		MoveSpeedChanged.emit(moveSpeed)

@onready var fsm: UnitFSM = $UnitFSM

var _unitRuntime: UnitRuntime


func _ready() -> void:
	fsm.BindUnit(self)
	add_to_group("unit")


func GetFootprintSize() -> int:
	return footprintSize


func GetHalfSize() -> int:
	return Math.DivideInt(footprintSize, 2)


func CanReceiveCommands() -> bool:
	return fsm != null and fsm.CanReceiveCommands()


func BindUnitRuntime(unitRuntime: UnitRuntime) -> void:
	_unitRuntime = unitRuntime


func IsMoving() -> bool:
	return is_instance_valid(_unitRuntime) and _unitRuntime.IsUnitMoving(unitId)


func PauseMovement() -> void:
	if is_instance_valid(_unitRuntime):
		_unitRuntime.PauseUnit(unitId)


func ResumeMovement() -> void:
	if is_instance_valid(_unitRuntime):
		_unitRuntime.ResumeUnit(unitId)


func StopMovement() -> void:
	if is_instance_valid(_unitRuntime):
		_unitRuntime.StopUnit(unitId)


func ApplyStun(duration: float) -> void:
	if fsm == null:
		return

	fsm.ApplyStun(duration)


func Die() -> void:
	if fsm == null:
		return

	fsm.Die()


func ResetForReuse() -> void:
	_unitRuntime = null

	if fsm != null:
		fsm.ResetForReuse()
