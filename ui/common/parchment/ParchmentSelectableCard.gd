class_name ParchmentSelectableCard
extends PanelContainer

signal selected
signal drag_requested

const DRAG_START_DISTANCE: float = 12.0

@onready var _parchmentFrame: ParchmentFrame = $ParchmentFrame
@onready var _selectButton: Button = $SelectButton

var _dragStartPosition: Vector2 = Vector2.ZERO
var _isDragArmed: bool = false


func _ready() -> void:
	_selectButton.mouse_entered.connect(_OnMouseEntered)
	_selectButton.mouse_exited.connect(_OnMouseExited)
	_selectButton.button_down.connect(_OnButtonDown)
	_selectButton.button_up.connect(_OnButtonUp)
	_selectButton.toggled.connect(_OnToggled)
	_selectButton.pressed.connect(_OnPressed)
	_selectButton.gui_input.connect(_OnGuiInput)

	_parchmentFrame.SetSelected(_selectButton.button_pressed)
	_parchmentFrame.SetDisabled(_selectButton.disabled)


func SetButtonGroup(buttonGroup: ButtonGroup) -> void:
	_selectButton.button_group = buttonGroup


func SetSelected(isSelected: bool) -> void:
	_selectButton.button_pressed = isSelected
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


func _OnPressed() -> void:
	selected.emit()


func _OnGuiInput(event: InputEvent) -> void:
	if _selectButton.disabled:
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
	drag_requested.emit()
