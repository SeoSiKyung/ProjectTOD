extends Node2D

@onready var _offenseSceneManager: OffenseSceneManager = $OffenseSceneManager
@onready var _worldCamera: WorldCamera2D = $Camera2D
@onready var _worldMap: Sprite2D = $WorldMap
@onready var _commandController: CommandController = $CommandController
@onready var _minimapView: MinimapView = $CommandPannel/MinimapView


func _ready() -> void:
	_worldCamera.SetWorldRect(_offenseSceneManager.GetNavigationWorldRect())

	_minimapView.Initialize(_worldCamera, _worldMap.texture)

	_minimapView.MoveCommandRequested.connect(_OnMinimapMoveCommandRequested)


func _OnMinimapMoveCommandRequested(worldPosition: Vector2) -> void:
	var commandId: int = _commandController.IssueMoveCommand(worldPosition)
	if commandId >= 0:
		_commandController.CancelTargetingCommand()
