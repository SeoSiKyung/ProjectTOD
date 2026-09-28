class_name DefenseDeploymentInfoView
extends Node2D

var _grid: DefenseDeploymentGrid

var _ratioLabelByCell: Dictionary[Vector2i, Label] = { }
var _mercenaryLabelByCell: Dictionary[Vector2i, Label] = { }


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


func SetMercenary(cell: Vector2i, mercenaryName: String) -> void:
	var label: Label = _mercenaryLabelByCell.get(cell)
	if label == null:
		label = _CreateMercenaryLabel(cell)
		_mercenaryLabelByCell[cell] = label

	label.text = mercenaryName


func Clear() -> void:
	ClearRatios()
	ClearMercenaries()


func ClearRatios() -> void:
	for label: Label in _ratioLabelByCell.values():
		label.queue_free()

	_ratioLabelByCell.clear()


func ClearMercenaries() -> void:
	for label: Label in _mercenaryLabelByCell.values():
		label.queue_free()

	_mercenaryLabelByCell.clear()


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


func _CreateMercenaryLabel(cell: Vector2i) -> Label:
	var label: Label = Label.new()

	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(_grid.cellSize, 30.0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 11

	add_child(label)

	var cellCenter: Vector2 = _grid.CellToWorldCenter(cell)
	var localCellCenter: Vector2 = to_local(cellCenter)

	label.position = Vector2(localCellCenter.x - _grid.cellSize * 0.5, localCellCenter.y - 50.0)

	return label
