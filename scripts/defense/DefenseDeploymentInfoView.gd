class_name DefenseDeploymentInfoView
extends Node2D

const MERCENARY_BADGE_SCENE: PackedScene = preload(
	"res://ui/defense/deployment/DefenseMercenaryAssignmentBadge.tscn"
)
const MERCENARY_BADGE_MARGIN: int = 6

var _grid: DefenseDeploymentGrid

var _ratioLabelByCell: Dictionary[Vector2i, Label] = { }
var _mercenaryBadgeByCell: Dictionary[Vector2i, DefenseMercenaryAssignmentBadge] = { }


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
	var badge: DefenseMercenaryAssignmentBadge = _mercenaryBadgeByCell.get(cell)
	if badge == null:
		badge = _CreateMercenaryBadge(cell)
		_mercenaryBadgeByCell[cell] = badge

	badge.Initialize(mercenaryData)


func Clear() -> void:
	ClearRatios()
	ClearMercenaries()


func ClearRatios() -> void:
	for label: Label in _ratioLabelByCell.values():
		label.queue_free()

	_ratioLabelByCell.clear()


func ClearMercenaries() -> void:
	for badge: DefenseMercenaryAssignmentBadge in _mercenaryBadgeByCell.values():
		badge.queue_free()

	_mercenaryBadgeByCell.clear()


func SetMercenaryHighlight(cell: Vector2i, isHighlighted: bool) -> void:
	var badge: DefenseMercenaryAssignmentBadge = _mercenaryBadgeByCell.get(cell)
	if badge == null:
		return

	badge.SetHighlighted(isHighlighted)


func ClearMercenaryHighlights() -> void:
	for badge: DefenseMercenaryAssignmentBadge in _mercenaryBadgeByCell.values():
		badge.SetHighlighted(false)


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


func _CreateMercenaryBadge(cell: Vector2i) -> DefenseMercenaryAssignmentBadge:
	var badge: DefenseMercenaryAssignmentBadge = MERCENARY_BADGE_SCENE.instantiate()

	add_child(badge)

	var cellCenter: Vector2 = _grid.CellToWorldCenter(cell)
	var localCellCenter: Vector2 = to_local(cellCenter)

	var cellTopLeft: Vector2 = (localCellCenter - Vector2.ONE * _grid.cellSize * 0.5)

	badge.position = Vector2(
		cellTopLeft.x + _grid.cellSize - badge.size.x - MERCENARY_BADGE_MARGIN,
		cellTopLeft.y + MERCENARY_BADGE_MARGIN,
	)

	return badge
