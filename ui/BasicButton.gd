@tool
class_name BasicButton
extends Control

signal action_pressed(actionKey: StringName)

@export var textKey: String = "":
	set(value):
		textKey = value
		if is_node_ready():
			_UpdateText()

@export var actionKey: StringName = ""

@export var maxFontSize: int = 32
@export var minFontSize: int = 18
@export var horizontalPadding: float = 24.0

@onready var _button: Button = $Button
@onready var _border: NinePatchRect = $Border
@onready var _mask: NinePatchRect = $Mask


func _ready():
	_UpdateText()
	_button.mouse_entered.connect(_OnMouseEntered)
	_button.mouse_exited.connect(_OnMouseExited)
	_button.button_down.connect(_OnButtonDown)
	_button.button_up.connect(_OnButtonUp)

	if not _button.pressed.is_connected(_OnButtonPressed):
		_button.pressed.connect(_OnButtonPressed)


func _notification(what):
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		if is_node_ready():
			_UpdateText()


func _UpdateText():
	var button: Button = $Button

	button.text = tr(textKey)

	var font: Font = button.get_theme_font("font")
	var fontSize := maxFontSize
	var availableWidth := button.size.x - horizontalPadding * 2.0

	while fontSize > minFontSize:
		var textWidth := font \
				.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fontSize) \
				.x

		if textWidth <= availableWidth:
			break

		fontSize -= 1

	button.add_theme_font_size_override("font_size", fontSize)


func _OnButtonPressed():
	action_pressed.emit(actionKey)


func _OnMouseEntered():
	# 양피지를 조금 따뜻하게
	_mask.self_modulate = Color(1.1, 1.1, 1.1)

	# 테두리도 살짝 밝게
	_border.self_modulate = Color(1.0, 0.95, 0.82)


func _OnMouseExited():
	_SetNormal()


func _OnButtonDown():
	# 눌렀을 때 전체적으로 어둡게
	_mask.self_modulate = Color(0.75, 0.75, 0.75)
	_border.self_modulate = Color(0.75, 0.75, 0.75)


func _OnButtonUp():
	if _button.is_hovered():
		_OnMouseEntered()
	else:
		_SetNormal()


func _SetNormal():
	_mask.self_modulate = Color.WHITE
	_border.self_modulate = Color.WHITE
