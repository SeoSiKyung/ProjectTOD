class_name DefenseCharacterButton
extends Button

@onready var _parchmentFrame: ParchmentFrame = $ParchmentFrame
@onready var _icon: TextureRect = $MarginContainer/VBoxContainer/TextureRect
@onready var _nameLabel: Label = $MarginContainer/VBoxContainer/Label
@onready var _countLabel: Label = $Overlay/CountLabel


func _ready() -> void:
	mouse_entered.connect(_OnMouseEntered)
	mouse_exited.connect(_OnMouseExited)
	button_down.connect(_OnButtonDown)
	button_up.connect(_OnButtonUp)
	toggled.connect(_OnToggled)

	_parchmentFrame.SetSelected(button_pressed)
	_parchmentFrame.SetDisabled(disabled)


func Initialize(characterData: CharacterData) -> void:
	_icon.texture = _LoadIcon(characterData.parchmentIconPath)
	_nameLabel.text = characterData.characterName


func ShowRemainingCount(count: int) -> void:
	_countLabel.visible = true
	_countLabel.text = "x%d" % count


func HideRemainingCount() -> void:
	_countLabel.visible = false


func SetSelected(isSelected: bool) -> void:
	set_pressed_no_signal(isSelected)
	_parchmentFrame.SetSelected(isSelected)


func SetDisabled(isDisabled: bool) -> void:
	disabled = isDisabled
	_parchmentFrame.SetDisabled(isDisabled)


func _OnMouseEntered() -> void:
	if disabled:
		return

	_parchmentFrame.SetHovered(true)


func _OnMouseExited() -> void:
	_parchmentFrame.SetHovered(false)
	_parchmentFrame.SetPressed(false)


func _OnButtonDown() -> void:
	if disabled:
		return

	_parchmentFrame.SetPressed(true)


func _OnButtonUp() -> void:
	_parchmentFrame.SetPressed(false)


func _OnToggled(isPressed: bool) -> void:
	_parchmentFrame.SetSelected(isPressed)


func _LoadIcon(iconPath: String) -> Texture2D:
	if iconPath.is_empty():
		return null

	var texture: Texture2D = load(iconPath)
	if texture == null:
		push_error("DefenseCharacterButton: 아이콘을 불러오지 못했습니다. path: " + iconPath)

	return texture
