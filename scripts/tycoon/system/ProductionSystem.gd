class_name ProductionSystem
extends Node

var _statSystem: StatSystem


func Setup(pStatSystem: StatSystem) -> void:
	_statSystem = pStatSystem


func ProcessTurnStart(settlement: SettlementState) -> void:
	if _statSystem == null:
		push_error("ProductionSystem: StatSystem이 설정되지 않았습니다.")
		return

	var stats := _statSystem.Calculate(settlement)

	settlement.gold += int(stats.goldIncome)
	settlement.food += int(stats.foodDelta)
	settlement.wood += int(stats.woodIncome)
	settlement.stone += int(stats.stoneIncome)
	settlement.iron += int(stats.ironIncome)
	settlement.magicStone += int(stats.magicStoneIncome)
