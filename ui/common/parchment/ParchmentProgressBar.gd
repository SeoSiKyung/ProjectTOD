@tool
class_name ParchmentProgressBar
extends ProgressBar

@export var fillColor: Color = Color(0.56, 0.24, 0.12, 1.0)
@export var backgroundColor: Color = Color(0.22, 0.13, 0.06, 0.82)
@export var borderColor: Color = Color(0.35, 0.20, 0.09, 1.0)


func _ready() -> void:
	_ApplyStyle()


func _ApplyStyle() -> void:
	var backgroundStyle: StyleBoxFlat = StyleBoxFlat.new()
	backgroundStyle.bg_color = backgroundColor
	backgroundStyle.border_color = borderColor
	backgroundStyle.border_width_left = 1
	backgroundStyle.border_width_top = 1
	backgroundStyle.border_width_right = 1
	backgroundStyle.border_width_bottom = 1
	backgroundStyle.corner_radius_top_left = 3
	backgroundStyle.corner_radius_top_right = 3
	backgroundStyle.corner_radius_bottom_right = 3
	backgroundStyle.corner_radius_bottom_left = 3

	var fillStyle: StyleBoxFlat = StyleBoxFlat.new()
	fillStyle.bg_color = fillColor
	fillStyle.border_color = fillColor.darkened(0.25)
	fillStyle.border_width_left = 1
	fillStyle.border_width_top = 1
	fillStyle.border_width_right = 1
	fillStyle.border_width_bottom = 1
	fillStyle.corner_radius_top_left = 3
	fillStyle.corner_radius_top_right = 3
	fillStyle.corner_radius_bottom_right = 3
	fillStyle.corner_radius_bottom_left = 3

	add_theme_stylebox_override("background", backgroundStyle)
	add_theme_stylebox_override("fill", fillStyle)
