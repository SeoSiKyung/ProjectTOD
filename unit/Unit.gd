extends Node2D
class_name Unit

@export var unitId: int = 0
@export_range(8, 256, 2) var footprintSize: int = 32
@export var playerControllable: bool = true

signal MoveSpeedChanged(moveSpeed: float)
@export var moveSpeed: float = 96.0:
	set(value):
		if not is_finite(value) or value < 0.0:
			push_error("Unit: moveSpeed는 0 이상의 유효한 값이어야 합니다.")
			return

		if is_equal_approx(moveSpeed, value):
			return

		moveSpeed = value
		MoveSpeedChanged.emit(moveSpeed)

@onready var fsm: UnitFSM = $UnitFSM

var _sceneManager: SceneManager


func _ready() -> void:
	fsm.BindUnit(self)
	add_to_group("unit")


func GetFootprintSize() -> int:
	return footprintSize


func GetHalfSize() -> int:
	return footprintSize / 2


func CanReceiveCommands() -> bool:
	return fsm != null and fsm.CanReceiveCommands()


func BindSceneManager(sceneManager: SceneManager) -> void:
	_sceneManager = sceneManager


func IsMoving() -> bool:
	return is_instance_valid(_sceneManager) and _sceneManager.IsUnitMoving(unitId)


func PauseMovement() -> void:
	if is_instance_valid(_sceneManager):
		_sceneManager.PauseUnit(unitId)


func ResumeMovement() -> void:
	if is_instance_valid(_sceneManager):
		_sceneManager.ResumeUnit(unitId)


func StopMovement() -> void:
	if is_instance_valid(_sceneManager):
		_sceneManager.StopUnit(unitId)


func ApplyStun(duration: float) -> void:
	if fsm == null:
		return

	fsm.ApplyStun(duration)


func Die() -> void:
	if fsm == null:
		return

	fsm.Die()


func ResetForReuse() -> void:
	_sceneManager = null

	if fsm != null:
		fsm.ResetForReuse()
