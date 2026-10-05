class_name DefenseCharacterButton
extends ParchmentSelectableCard

signal drag_started(characterKey: int, previewTexture: Texture2D)

@onready var _icon: TextureRect = $ContentContainer/VBoxContainer/TextureRect
@onready var _nameLabel: Label = $ContentContainer/VBoxContainer/Label
@onready var _countLabel: Label = $Overlay/CountLabel

var _characterKey: int = -1


func _ready() -> void:
	super._ready()

	drag_requested.connect(_OnDragRequested)


func Initialize(characterData: CharacterData) -> void:
	_characterKey = characterData.characterKey
	_icon.texture = _LoadIcon(characterData.parchmentIconPath)
	_nameLabel.text = characterData.characterName


func ShowRemainingCount(count: int) -> void:
	_countLabel.visible = true
	_countLabel.text = "x%d" % count


func HideRemainingCount() -> void:
	_countLabel.visible = false


func GetIconTexture() -> Texture2D:
	return _icon.texture


func _OnDragRequested() -> void:
	drag_started.emit(_characterKey, _icon.texture)


func _LoadIcon(iconPath: String) -> Texture2D:
	if iconPath.is_empty():
		return null

	var texture: Texture2D = load(iconPath)
	if texture == null:
		push_error("DefenseCharacterButton: 아이콘을 불러오지 못했습니다. path: " + iconPath)

	return texture
