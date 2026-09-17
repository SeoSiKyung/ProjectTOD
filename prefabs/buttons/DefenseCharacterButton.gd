class_name DefenseCharacterButton
extends Button

@onready var _icon: TextureRect = $MarginContainer/VBoxContainer/TextureRect
@onready var _nameLabel: Label = $MarginContainer/VBoxContainer/Label

var characterKey: int = -1


func Initialize(characterData: CharacterData) -> void:
	characterKey = characterData.characterKey

	_nameLabel.text = characterData.characterName
	_icon.texture = _LoadIcon(characterData.iconPath)


func _LoadIcon(iconPath: String) -> Texture2D:
	if iconPath.is_empty():
		return null

	var texture: Texture2D = load(iconPath)
	if texture == null:
		push_error("DefenseCharacterButton: 아이콘을 불러오지 못했습니다. path: " + iconPath)

	return texture
