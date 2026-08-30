class_name NavigationBakeScene
extends Node2D

@onready var navigationBaker: NavigationBaker = $NavigationBaker
@onready var bakeButton: Button = $BakeButton


func _ready() -> void:
	bakeButton.pressed.connect(_OnBakeButtonPressed)


func _OnBakeButtonPressed() -> void:
	var bakeSuccess: bool = navigationBaker.BakeNavigation()
	if bakeSuccess:
		get_tree().quit()
	else:
		push_error("Bake Fail")
