class_name DefenseMercenaryButton
extends ParchmentSelectableCard

signal drag_started(mercenaryKey: int, previewTexture: Texture2D)

const BUFF_HEADER_COUNT: int = 3
const STAT_COLUMN_WIDTH: float = 38.0
const FLAT_COLUMN_WIDTH: float = 38.0
const RATIO_COLUMN_WIDTH: float = 42.0

@onready var _icon: TextureRect = $ContentContainer/VBoxContainer/TextureRect
@onready var _nameLabel: Label = $ContentContainer/VBoxContainer/NameLabel
@onready var _buffGrid: GridContainer = $ContentContainer/VBoxContainer/BuffGrid
@onready var _assignedBadge: ParchmentBadge = $AssignedBadge

var _mercenaryKey: int = -1


func _ready() -> void:
	super._ready()

	drag_requested.connect(_OnDragRequested)


func Initialize(mercenaryData: MercenaryData, buffDataList: Array[MercenaryBuffData]) -> void:
	_mercenaryKey = mercenaryData.mercenaryKey
	_icon.texture = _LoadIcon(mercenaryData.parchmentIconPath)

	_nameLabel.theme_type_variation = &"ParchmentLabel"
	_nameLabel.add_theme_font_size_override("font_size", 18)
	_nameLabel.remove_theme_color_override("font_color")

	if mercenaryData.isHero:
		_nameLabel.text = "★ " + mercenaryData.name
		_nameLabel.theme_type_variation = &"ParchmentTitleLabel"
		_nameLabel.add_theme_font_size_override("font_size", 20)
		_nameLabel.add_theme_color_override(
			"font_color",
			Color(0.40784314, 0.23529412, 0.05490196, 1),
		)
	else:
		_nameLabel.text = mercenaryData.name

	_ClearBuffRows()

	var hasBuff: bool = false
	for buffData: MercenaryBuffData in buffDataList:
		if buffData == null:
			continue

		if buffData.flatValue == 0 and buffData.ratioValue == 0:
			continue

		_AddBuffRow(buffData)
		hasBuff = true

	if not hasBuff:
		_AddEmptyBuffRow()


func SetAssigned(isAssigned: bool) -> void:
	_assignedBadge.visible = isAssigned


func GetIconTexture() -> Texture2D:
	return _icon.texture


func _OnDragRequested() -> void:
	drag_started.emit(_mercenaryKey, _icon.texture)


func _LoadIcon(iconPath: String) -> Texture2D:
	if iconPath.is_empty():
		return null

	var texture: Texture2D = load(iconPath)
	if texture == null:
		push_error("DefenseMercenaryButton: 아이콘을 불러오지 못했습니다. path: " + iconPath)

	return texture


func _ClearBuffRows() -> void:
	while _buffGrid.get_child_count() > BUFF_HEADER_COUNT:
		var child: Node = _buffGrid.get_child(BUFF_HEADER_COUNT)
		_buffGrid.remove_child(child)
		child.queue_free()


func _AddBuffRow(buffData: MercenaryBuffData) -> void:
	var statLabel: Label = _CreateBuffLabel(
		_GetStatName(buffData.statType),
		HORIZONTAL_ALIGNMENT_LEFT,
		STAT_COLUMN_WIDTH,
	)

	var flatLabel: Label = _CreateBuffLabel(
		_FormatFlatValue(buffData.flatValue),
		HORIZONTAL_ALIGNMENT_RIGHT,
		FLAT_COLUMN_WIDTH,
	)

	var ratioLabel: Label = _CreateBuffLabel(
		_FormatRatioValue(buffData.ratioValue),
		HORIZONTAL_ALIGNMENT_RIGHT,
		RATIO_COLUMN_WIDTH,
	)

	_buffGrid.add_child(statLabel)
	_buffGrid.add_child(flatLabel)
	_buffGrid.add_child(ratioLabel)


func _AddEmptyBuffRow() -> void:
	_buffGrid.add_child(_CreateBuffLabel("효과 없음", HORIZONTAL_ALIGNMENT_LEFT, STAT_COLUMN_WIDTH))
	_buffGrid.add_child(_CreateBuffLabel("-", HORIZONTAL_ALIGNMENT_RIGHT, FLAT_COLUMN_WIDTH))
	_buffGrid.add_child(_CreateBuffLabel("-", HORIZONTAL_ALIGNMENT_RIGHT, RATIO_COLUMN_WIDTH))


func _CreateBuffLabel(text: String, alignment: HorizontalAlignment, minWidth: float) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.horizontal_alignment = alignment
	label.custom_minimum_size.x = minWidth
	label.theme_type_variation = &"ParchmentSmallLabel"
	label.add_theme_font_size_override("font_size", 14)

	return label


func _FormatFlatValue(value: int) -> String:
	if value == 0:
		return "-"

	return "+%d" % value


func _FormatRatioValue(value: int) -> String:
	if value == 0:
		return "-"

	return "+%d%%" % Math.RatioToPercent(value)


func _GetStatName(type: CharacterStats.Type) -> String:
	match type:
		CharacterStats.Type.ATK:
			return "공격"
		CharacterStats.Type.DEF:
			return "방어"
		CharacterStats.Type.MAX_HP:
			return "체력"
		_:
			return str(CharacterStats.Type.keys()[type])
