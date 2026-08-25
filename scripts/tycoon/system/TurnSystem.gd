class_name TurnSystem
extends Node


signal turn_advanced(current_turn: int)
signal cycle_finished(cycle: int)


func advance_turn(settlement: SettlementState) -> bool:
	if settlement.is_cycle_finished():
		return false

	settlement.current_turn += 1

	turn_advanced.emit(settlement.current_turn)

	if settlement.is_cycle_finished():
		cycle_finished.emit(settlement.cycle)

	return true