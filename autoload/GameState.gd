extends Node

var settlement: SettlementState


func _ready() -> void:
	if settlement == null:
		StartNewGame()


func StartNewGame() -> void:
	settlement = SettlementState.new()

	# 테스트용 초기값
	settlement.cycle = 1
	settlement.currentTurn = 0
	settlement.cycleTurnLimit = 10

	settlement.gold = 500
	settlement.food = 100
	settlement.wood = 200
	settlement.stone = 0
	settlement.iron = 0
	settlement.magicStone = 0

	settlement.population = 10
	settlement.stability = 100


func ResetGame() -> void:
	StartNewGame()
