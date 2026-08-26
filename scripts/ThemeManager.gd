extends Node

const FONT_KO: Font = preload("res://fonts/Hahmlet_variation.tres")
const FONT_EN: Font = preload("res://fonts/Cinzel-Bold.ttf")


func SetLanguage(locale: String) -> void:
	TranslationServer.set_locale(locale)

	var theme := ThemeDB.get_project_theme()

	if locale.begins_with("en"):
		theme.default_font = FONT_EN
	else:
		theme.default_font = FONT_KO
