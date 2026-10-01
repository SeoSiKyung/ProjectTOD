@tool
class_name BasicButton
extends Control

signal pressed
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
@onready var _parchmentFrame: ParchmentFrame = $ParchmentFrame


func _ready() -> void:
	_UpdateText()
	_button.mouse_entered.connect(_OnMouseEntered)
	_button.mouse_exited.connect(_OnMouseExited)
	_button.button_down.connect(_OnButtonDown)
	_button.button_up.connect(_OnButtonUp)

	if not _button.pressed.is_connected(_OnButtonPressed):
		_button.pressed.connect(_OnButtonPressed)

	_parchmentFrame.SetDisabled(_button.disabled)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		if is_node_ready():
			_UpdateText()


func _UpdateText() -> void:
	var button: Button = $Button

	button.text = tr(textKey)

	var font: Font = button.get_theme_font("font")
	var fontSize: int = maxFontSize
	var availableWidth: float = button.size.x - horizontalPadding * 2.0

	while fontSize > minFontSize:
		var textWidth: float = font \
				.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fontSize) \
				.x

		if textWidth <= availableWidth:
			break

		fontSize -= 1

	button.add_theme_font_size_override("font_size", fontSize)


func SetDisabled(isDisabled: bool) -> void:
	_button.disabled = isDisabled
	_parchmentFrame.SetDisabled(isDisabled)
	_parchmentFrame.SetHovered(false)
	_parchmentFrame.SetPressed(false)


func _OnButtonPressed() -> void:
	pressed.emit()
	action_pressed.emit(actionKey)


func _OnMouseEntered() -> void:
	if _button.disabled:
		return

	_parchmentFrame.SetHovered(true)


func _OnMouseExited() -> void:
	_parchmentFrame.SetHovered(false)
	_parchmentFrame.SetPressed(false)


func _OnButtonDown() -> void:
	if _button.disabled:
		return

	_parchmentFrame.SetPressed(true)


func _OnButtonUp() -> void:
	_parchmentFrame.SetPressed(false)
