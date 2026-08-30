extends Node2D
class_name Unit

@export var unitId: int = 0
@export_range(8, 256, 2) var footprintSize: int = 32
@export var playerControllable: bool = true
@export var moveSpeed: float = 96.0

@onready var fsm: UnitFSM = $UnitFSM

var _sceneManager: OffenseSceneManager


func _ready() -> void:
	fsm.BindUnit(self)
	add_to_group("unit")


func GetFootprintSize() -> int:
	return footprintSize


func GetHalfSize() -> int:
	return footprintSize / 2


func CanReceiveCommands() -> bool:
	return fsm != null and fsm.CanReceiveCommands()


func BindSceneManager(sceneManager: OffenseSceneManager) -> void:
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
