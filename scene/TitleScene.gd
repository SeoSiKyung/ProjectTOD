extends Control


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			ThemeManager.set_language("ko")
			print("언어 변경: 한국어")

		elif event.keycode == KEY_F2:
			ThemeManager.set_language("en")
			print("언어 변경: 영어")


func _ready():
	for child in $VBoxContainer.get_children():
		if child is BasicButton:
			child.action_pressed.connect(_on_menu_action)


func _on_menu_action(action_key: StringName):
	match action_key:
		&"new_game":
			_start_new_game()

		&"continue":
			_continue_game()

		&"records":
			_open_records()

		&"settings":
			_open_settings()

		&"quit":
			get_tree().quit()

		_:
			push_warning("알 수 없는 버튼 Action Key: " + str(action_key))


func _start_new_game():
	print("새 게임")


func _continue_game():
	print("이어하기")


func _open_records():
	print("기록실")


func _open_settings():
	print("설정")
