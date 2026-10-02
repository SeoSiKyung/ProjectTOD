class_name DefenseDeploymentInfoView
extends Node2D

const PARCHMENT_FRAME_SCENE: PackedScene = preload("res://ui/common/parchment/ParchmentFrame.tscn")

var _grid: DefenseDeploymentGrid

var _ratioLabelByCell: Dictionary[Vector2i, Label] = { }
var _mercenaryBadgeByCell: Dictionary[Vector2i, Control] = { }


func Initialize(grid: DefenseDeploymentGrid) -> void:
	_grid = grid


func SetRecruitRatio(cell: Vector2i, recruitRatio: int) -> void:
	var label: Label = _ratioLabelByCell.get(cell)
	if label == null:
		label = _CreateRatioLabel(cell)
		_ratioLabelByCell[cell] = label

	label.text = "%d%%" % Math.RatioToPercent(recruitRatio)


func RemoveRecruitRatio(cell: Vector2i) -> void:
	var label: Label = _ratioLabelByCell.get(cell)
	if label == null:
		return

	label.queue_free()
	_ratioLabelByCell.erase(cell)


func SetMercenary(cell: Vector2i, mercenaryData: MercenaryData) -> void:
	var badge: Control = _mercenaryBadgeByCell.get(cell)
	if badge == null:
		badge = _CreateMercenaryBadge(cell)
		_mercenaryBadgeByCell[cell] = badge

	var portrait: TextureRect = badge.get_node("Portrait")
	portrait.texture = load(mercenaryData.iconPath)


func Clear() -> void:
	ClearRatios()
	ClearMercenaries()


func ClearRatios() -> void:
	for label: Label in _ratioLabelByCell.values():
		label.queue_free()

	_ratioLabelByCell.clear()


func ClearMercenaries() -> void:
	for badge: Control in _mercenaryBadgeByCell.values():
		badge.queue_free()

	_mercenaryBadgeByCell.clear()


func _CreateRatioLabel(cell: Vector2i) -> Label:
	var label: Label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(_grid.cellSize, 30.0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 10

	add_child(label)

	var cellCenter: Vector2 = _grid.CellToWorldCenter(cell)
	var localCellCenter: Vector2 = to_local(cellCenter)
	label.position = Vector2(localCellCenter.x - _grid.cellSize * 0.5, localCellCenter.y + 25.0)

	return label


func _CreateMercenaryBadge(cell: Vector2i) -> Control:
	var badge: Control = Control.new()
	badge.name = "MercenaryBadge"
	badge.custom_minimum_size = Vector2(44.0, 44.0)
	badge.size = Vector2(44.0, 44.0)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.z_index = 20

	var frame: ParchmentFrame = PARCHMENT_FRAME_SCENE.instantiate()
	frame.name = "Frame"
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.SetSelected(true)

	badge.add_child(frame)

	var portrait: TextureRect = TextureRect.new()
	portrait.name = "Portrait"
	portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE

	badge.add_child(portrait)
	add_child(badge)

	var cellCenter: Vector2 = _grid.CellToWorldCenter(cell)
	var localCellCenter: Vector2 = to_local(cellCenter)
	badge.position = Vector2(
		localCellCenter.x - badge.size.x * 0.5,
		localCellCenter.y - badge.size.y * 0.5,
	)

	return badge
