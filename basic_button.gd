@tool
class_name BasicButton
extends Control

signal action_pressed(action_key: StringName)

@export var text_key: String = "":
	set(value):
		text_key = value
		if is_node_ready():
			update_text()
@export var action_key: StringName = ""

@export var max_font_size: int = 32
@export var min_font_size: int = 18
@export var horizontal_padding: float = 24.0

@onready var button: Button = $Button
@onready var border: NinePatchRect = $Border
@onready var mask: NinePatchRect = $Mask


func _ready():
	update_text()
	button.mouse_entered.connect(_on_mouse_entered)
	button.mouse_exited.connect(_on_mouse_exited)
	button.button_down.connect(_on_button_down)
	button.button_up.connect(_on_button_up)
	
	if not $Button.pressed.is_connected(_on_button_pressed):
		$Button.pressed.connect(_on_button_pressed)


func _notification(what):
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		if is_node_ready():
			update_text()


func update_text():
	var button: Button = $Button

	button.text = tr(text_key)

	var font: Font = button.get_theme_font("font")
	var font_size := max_font_size
	var available_width := button.size.x - horizontal_padding * 2.0

	while font_size > min_font_size:
		var text_width := font.get_string_size(
			button.text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size
		).x

		if text_width <= available_width:
			break

		font_size -= 1

	button.add_theme_font_size_override("font_size", font_size)


func _on_button_pressed():
	action_pressed.emit(action_key)


func _on_mouse_entered():
	# 양피지를 조금 따뜻하게
	mask.self_modulate = Color(1.1, 1.1, 1.1)

	# 테두리도 살짝 밝게
	border.self_modulate = Color(1.0, 0.95, 0.82)


func _on_mouse_exited():
	_set_normal()



func _on_button_down():
	# 눌렀을 때 전체적으로 어둡게
	mask.self_modulate = Color(0.75, 0.75, 0.75)
	border.self_modulate = Color(0.75, 0.75, 0.75)


func _on_button_up():
	if button.is_hovered():
		_on_mouse_entered()
	else:
		_set_normal()


func _set_normal():
	mask.self_modulate = Color.WHITE
	border.self_modulate = Color.WHITE
