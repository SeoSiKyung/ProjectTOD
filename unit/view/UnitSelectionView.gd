class_name UnitSelectionView
extends Node

@export var selectSprite: Sprite2D
@export var healthBar: UnitHealthBar


func ConfigureFaction(faction: Faction.Type, friendlyColor: Color, enemyColor: Color) -> void:
	if selectSprite == null:
		return

	match faction:
		Faction.Type.ALLY:
			selectSprite.self_modulate = friendlyColor
		Faction.Type.ENEMY:
			selectSprite.self_modulate = enemyColor
		_:
			selectSprite.self_modulate = Color.WHITE


func SetSelected(selected: bool) -> void:
	if selectSprite != null:
		selectSprite.visible = selected

	if healthBar != null:
		healthBar.SetSelected(selected)
