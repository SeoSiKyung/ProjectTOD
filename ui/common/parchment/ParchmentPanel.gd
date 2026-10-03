@tool
class_name ParchmentPanel
extends Container

const PARCHMENT_FRAME_SCENE: PackedScene = preload("res://ui/common/parchment/ParchmentFrame.tscn")

@export_group("Content Margin")
@export_range(0, 128, 1) var contentMarginLeft: int = 16:
	set(value):
		contentMarginLeft = value
		_UpdateLayout()
@export_range(0, 128, 1) var contentMarginTop: int = 14:
	set(value):
		contentMarginTop = value
		_UpdateLayout()
@export_range(0, 128, 1) var contentMarginRight: int = 16:
	set(value):
		contentMarginRight = value
		_UpdateLayout()
@export_range(0, 128, 1) var contentMarginBottom: int = 14:
	set(value):
		contentMarginBottom = value
		_UpdateLayout()

var _parchmentFrame: ParchmentFrame


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_CreateParchmentFrame()


func _notification(what: int) -> void:
	if what != NOTIFICATION_SORT_CHILDREN:
		return

	_LayoutParchmentFrame()
	_LayoutContent()


func _get_minimum_size() -> Vector2:
	var contentMinimumSize: Vector2 = Vector2.ZERO

	for child: Node in get_children():
		if child is not Control:
			continue

		var control: Control = child as Control
		if not control.visible:
			continue

		var childMinimumSize: Vector2 = control.get_combined_minimum_size()
		contentMinimumSize.x = maxf(contentMinimumSize.x, childMinimumSize.x)
		contentMinimumSize.y = maxf(contentMinimumSize.y, childMinimumSize.y)

	return contentMinimumSize + Vector2(
		contentMarginLeft + contentMarginRight,
		contentMarginTop + contentMarginBottom,
	)


func _CreateParchmentFrame() -> void:
	_parchmentFrame = PARCHMENT_FRAME_SCENE.instantiate() as ParchmentFrame
	_parchmentFrame.name = &"_ParchmentFrame"
	_parchmentFrame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_parchmentFrame.z_index = -1
	add_child(_parchmentFrame, false, Node.INTERNAL_MODE_FRONT)


func _LayoutParchmentFrame() -> void:
	if _parchmentFrame == null:
		return

	fit_child_in_rect(_parchmentFrame, Rect2(Vector2.ZERO, size))


func _LayoutContent() -> void:
	var contentPosition: Vector2 = Vector2(contentMarginLeft, contentMarginTop)
	var contentSize: Vector2 = Vector2(
		maxf(size.x - contentMarginLeft - contentMarginRight, 0.0),
		maxf(size.y - contentMarginTop - contentMarginBottom, 0.0),
	)
	var contentRect: Rect2 = Rect2(contentPosition, contentSize)

	for child: Node in get_children():
		if child is Control:
			fit_child_in_rect(child as Control, contentRect)


func _UpdateLayout() -> void:
	if not is_inside_tree():
		return

	update_minimum_size()
	queue_sort()
