class_name OffenseStageManager
extends Node

@export var _navigationService: NavigationService
var movementSimulator: MovementSimulator = MovementSimulator.new()
var unitManager: UnitManager = UnitManager.new()
var snapshot: StageSnapshot = null

func _ready() -> void:
	_navigationService.Ready()

func _process(delta: float) -> void:
	pass
