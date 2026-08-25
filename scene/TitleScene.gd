extends Control


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			ThemeManager.SetLanguage("ko")
			print("언어 변경: 한국어")

		elif event.keycode == KEY_F2:
			ThemeManager.SetLanguage("en")
			print("언어 변경: 영어")


func _ready():
	for child in $VBoxContainer.get_children():
		if child is BasicButton:
			child.action_pressed.connect(_OnMenuAction)


func _OnMenuAction(actionKey: StringName):
	match actionKey:
		&"new_game":
			_StartNewGame()

		&"continue":
			_ContinueGame()

		&"records":
			_OpenRecords()

		&"settings":
			_OpenSettings()

		&"quit":
			get_tree().quit()

		_:
			push_warning("알 수 없는 버튼 Action Key: " + str(actionKey))


func _StartNewGame():
	print("새 게임")


func _ContinueGame():
	print("이어하기")


func _OpenRecords():
	print("기록실")


func _OpenSettings():
	print("설정")
