class_name TurnSystem
extends Node

signal TurnStarted(currentTurn: int)
signal CycleFinished(cycle: int)


func StartCycle(campaign: CampaignState, turnLimit: int) -> bool:
	if turnLimit <= 0:
		push_warning("TurnSystem: 사이클 턴 수는 1 이상이어야 합니다.")
		return false

	campaign.currentTurn = 1
	campaign.cycleTurnLimit = turnLimit
	campaign.currentPhase = CampaignState.Phase.TYCOON

	TurnStarted.emit(campaign.currentTurn)

	return true


func EndTurn(campaign: CampaignState) -> bool:
	if IsLastTurn(campaign):
		CycleFinished.emit(campaign.cycle)

		return false

	campaign.currentTurn += 1

	TurnStarted.emit(campaign.currentTurn)

	return true


func IsLastTurn(campaign: CampaignState) -> bool:
	return campaign.IsLastTurn()
