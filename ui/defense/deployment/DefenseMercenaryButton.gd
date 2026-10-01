class_name DefenseMercenaryButton
extends PanelContainer

signal selected

const BUFF_HEADER_COUNT: int = 3
const STAT_COLUMN_WIDTH: float = 44.0
const FLAT_COLUMN_WIDTH: float = 44.0
const RATIO_COLUMN_WIDTH: float = 50.0

@onready var _parchmentFrame: ParchmentFrame = $ParchmentFrame
@onready var _selectButton: Button = $SelectButton
@onready var _icon: TextureRect = $MarginContainer/VBoxContainer/TextureRect
@onready var _nameLabel: Label = $MarginContainer/VBoxContainer/NameLabel
@onready var _buffGrid: GridContainer = $MarginContainer/VBoxContainer/BuffGrid


func _ready() -> void:
	_selectButton.mouse_entered.connect(_OnMouseEntered)
	_selectButton.mouse_exited.connect(_OnMouseExited)
	_selectButton.button_down.connect(_OnButtonDown)
	_selectButton.button_up.connect(_OnButtonUp)
	_selectButton.toggled.connect(_OnToggled)
	_selectButton.pressed.connect(_OnSelectButtonPressed)

	_parchmentFrame.SetSelected(_selectButton.button_pressed)
	_parchmentFrame.SetDisabled(_selectButton.disabled)


func SetButtonGroup(buttonGroup: ButtonGroup) -> void:
	_selectButton.button_group = buttonGroup


func SetSelected(isSelected: bool) -> void:
	_selectButton.set_pressed_no_signal(isSelected)
	_parchmentFrame.SetSelected(isSelected)


func IsSelected() -> bool:
	return _selectButton.button_pressed


func SetDisabled(isDisabled: bool) -> void:
	_selectButton.disabled = isDisabled
	_parchmentFrame.SetDisabled(isDisabled)


func _OnMouseEntered() -> void:
	if _selectButton.disabled:
		return

	_parchmentFrame.SetHovered(true)


func _OnMouseExited() -> void:
	_parchmentFrame.SetHovered(false)
	_parchmentFrame.SetPressed(false)


func _OnButtonDown() -> void:
	if _selectButton.disabled:
		return

	_parchmentFrame.SetPressed(true)


func _OnButtonUp() -> void:
	_parchmentFrame.SetPressed(false)


func _OnToggled(isPressed: bool) -> void:
	_parchmentFrame.SetSelected(isPressed)


func _OnSelectButtonPressed() -> void:
	selected.emit()


func Initialize(mercenaryData: MercenaryData, buffDataList: Array[MercenaryBuffData]) -> void:
	_icon.texture = _LoadIcon(mercenaryData.parchmentIconPath)

	if mercenaryData.isHero:
		_nameLabel.text = "★ " + mercenaryData.name
		_nameLabel.theme_type_variation = &"ParchmentHeroCardTitleLabel"
	else:
		_nameLabel.text = mercenaryData.name
		_nameLabel.theme_type_variation = &"ParchmentLargeCardTitleLabel"

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
