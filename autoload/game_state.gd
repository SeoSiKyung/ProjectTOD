extends Node


var settlement: SettlementState


func _ready() -> void:
	if settlement == null:
		start_new_game()


func start_new_game() -> void:
	settlement = SettlementState.new()

	# 테스트용 초기값
	settlement.cycle = 1
	settlement.current_turn = 0
	settlement.cycle_turn_limit = 10

	settlement.gold = 500
	settlement.food = 100
	settlement.wood = 200
	settlement.stone = 0
	settlement.iron = 0
	settlement.magic_stone = 0

	settlement.population = 10
	settlement.stability = 100


func reset_game() -> void:
	start_new_game()
