class_name DefenseCharacterButton
extends Button

signal drag_started(characterKey: int, previewTexture: Texture2D)

const DRAG_START_DISTANCE: float = 12.0

@onready var _parchmentFrame: ParchmentFrame = $ParchmentFrame
@onready var _icon: TextureRect = $MarginContainer/VBoxContainer/TextureRect
@onready var _nameLabel: Label = $MarginContainer/VBoxContainer/Label
@onready var _countLabel: Label = $Overlay/CountLabel

var _characterKey: int = -1
var _dragStartPosition: Vector2 = Vector2.ZERO
var _isDragArmed: bool = false


func _ready() -> void:
	mouse_entered.connect(_OnMouseEntered)
	mouse_exited.connect(_OnMouseExited)
	button_down.connect(_OnButtonDown)
	button_up.connect(_OnButtonUp)
	toggled.connect(_OnToggled)

	_parchmentFrame.SetSelected(button_pressed)
	_parchmentFrame.SetDisabled(disabled)


func Initialize(characterData: CharacterData) -> void:
	_characterKey = characterData.characterKey
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


func GetIconTexture() -> Texture2D:
	return _icon.texture


func _gui_input(event: InputEvent) -> void:
	if disabled:
		_isDragArmed = false
		return

	if event is InputEventMouseButton:
		var mouseEvent: InputEventMouseButton = event
		if mouseEvent.button_index != MOUSE_BUTTON_LEFT:
			return

		_isDragArmed = mouseEvent.pressed
		if mouseEvent.pressed:
			_dragStartPosition = mouseEvent.position
		return

	if event is not InputEventMouseMotion or not _isDragArmed:
		return

	var motionEvent: InputEventMouseMotion = event
	if (motionEvent.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
		_isDragArmed = false
		return

	if motionEvent.position.distance_to(_dragStartPosition) < DRAG_START_DISTANCE:
		return

	_isDragArmed = false
	SetSelected(true)
	drag_started.emit(_characterKey, _icon.texture)


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
