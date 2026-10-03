class_name DefenseMercenaryAssignmentBadge
extends Control

@onready var _parchmentFrame: ParchmentFrame = $ParchmentFrame
@onready var _portrait: TextureRect = $Margin/VBoxContainer/Portrait
@onready var _nameLabel: Label = $Margin/VBoxContainer/NameLabel


func Initialize(mercenaryData: MercenaryData) -> void:
	if mercenaryData == null:
		return

	var iconPath: String = mercenaryData.parchmentIconPath
	if iconPath.is_empty():
		iconPath = mercenaryData.iconPath

	if not iconPath.is_empty():
		_portrait.texture = load(iconPath)

	_nameLabel.text = mercenaryData.name


func SetHighlighted(isHighlighted: bool) -> void:
	_parchmentFrame.SetSelected(isHighlighted)
