@tool
class_name ParchmentFrame
extends Control

const HOVER_PAPER_MODULATE: Color = Color(1.08, 1.04, 0.92, 1.0)
const HOVER_BORDER_MODULATE: Color = Color(1.05, 0.95, 0.75, 1.0)
const SELECTED_BORDER_MODULATE: Color = Color(1.35, 1.05, 0.45, 1.0)
const PRESSED_PAPER_MODULATE: Color = Color(0.82, 0.82, 0.82, 1.0)
const PRESSED_BORDER_MODULATE: Color = Color(0.86, 0.82, 0.72, 1.0)
const DISABLED_MODULATE: Color = Color(0.55, 0.55, 0.55, 1.0)

@onready var _paper: NinePatchRect = $Paper
@onready var _border: NinePatchRect = $Border

var _isSelected: bool = false
var _isHovered: bool = false
var _isPressed: bool = false
var _isDisabled: bool = false


func _ready() -> void:
	_RefreshVisual()


func SetSelected(isSelected: bool) -> void:
	_isSelected = isSelected
	_RefreshVisual()


func SetHovered(isHovered: bool) -> void:
	_isHovered = isHovered
	_RefreshVisual()


func SetPressed(isPressed: bool) -> void:
	_isPressed = isPressed
	_RefreshVisual()


func SetDisabled(isDisabled: bool) -> void:
	_isDisabled = isDisabled
	if isDisabled:
		_isHovered = false
		_isPressed = false

	_RefreshVisual()


func _RefreshVisual() -> void:
	if not is_node_ready():
		return

	if _isDisabled:
		_paper.self_modulate = DISABLED_MODULATE
		_border.self_modulate = DISABLED_MODULATE
		return

	if _isPressed:
		_paper.self_modulate = PRESSED_PAPER_MODULATE
		_border.self_modulate = (
			SELECTED_BORDER_MODULATE if _isSelected else PRESSED_BORDER_MODULATE
		)
		return

	_paper.self_modulate = HOVER_PAPER_MODULATE if _isHovered else Color.WHITE

	if _isSelected:
		_border.self_modulate = SELECTED_BORDER_MODULATE
	elif _isHovered:
		_border.self_modulate = HOVER_BORDER_MODULATE
	else:
		_border.self_modulate = Color.WHITE
