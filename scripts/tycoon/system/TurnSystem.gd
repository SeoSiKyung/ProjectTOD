class_name TurnSystem
extends Node

signal TurnAdvanced(currentTurn: int)
signal CycleFinished(cycle: int)


func AdvanceTurn(settlement: SettlementState) -> bool:
	if settlement.IsCycleFinished():
		return false

	settlement.currentTurn += 1

	TurnAdvanced.emit(settlement.currentTurn)

	if settlement.IsCycleFinished():
		CycleFinished.emit(settlement.cycle)

	return true
