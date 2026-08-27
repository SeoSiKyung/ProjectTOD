class_name ProductionSystem
extends Node


func ProcessTurnStart(settlement: SettlementState, context: TurnContext) -> void:
	if context.stats == null:
		push_error("ProductionSystem: TurnContext에 DerivedStats가 없습니다.")
		return

	var stats := context.stats

	# =====================================================
	# 이번 턴 생산량 계산
	# =====================================================
	context.producedGold = int(stats.goldIncome)

	context.producedFood = int(stats.foodDelta)

	context.producedWood = int(stats.woodIncome)

	context.producedStone = int(stats.stoneIncome)

	context.producedIron = int(stats.ironIncome)

	context.producedMagicStone = int(stats.magicStoneIncome)

	# =====================================================
	# SettlementState 반영
	# =====================================================
	settlement.gold += context.producedGold
	settlement.food += context.producedFood
	settlement.wood += context.producedWood
	settlement.stone += context.producedStone
	settlement.iron += context.producedIron
	settlement.magicStone += context.producedMagicStone
