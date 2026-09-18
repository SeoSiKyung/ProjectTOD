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
	context.producedGold = stats.goldIncome

	context.producedFood = stats.foodDelta

	context.producedWood = stats.woodIncome

	context.producedStone = stats.stoneIncome

	context.producedIron = stats.ironIncome

	context.producedMagicStone = stats.magicStoneIncome

	# =====================================================
	# SettlementState 반영
	# =====================================================
	settlement.gold += context.producedGold
	settlement.food += context.producedFood
	settlement.wood += context.producedWood
	settlement.stone += context.producedStone
	settlement.iron += context.producedIron
	settlement.magicStone += context.producedMagicStone
