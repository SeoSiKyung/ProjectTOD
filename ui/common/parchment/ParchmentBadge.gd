@tool
class_name ParchmentBadge
extends PanelContainer

@export var text: String = "":
	set(value):
		text = value
		if is_node_ready():
			_UpdateText()

@onready var _label: Label = $Margin/Label


func _ready() -> void:
	_UpdateText()


func SetText(value: String) -> void:
	text = value


func _UpdateText() -> void:
	_label.text = text
