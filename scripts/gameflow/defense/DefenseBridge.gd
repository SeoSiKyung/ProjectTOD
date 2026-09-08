class_name DefenseBridge
extends Node

const TEMP_COMMAND_POST_MAX_HP: int = 1000


func CreateStartData(campaign: CampaignState, population: int) -> DefenseStartData:
	var startData: DefenseStartData = DefenseStartData.new()
	startData.cycle = campaign.cycle
	startData.population = population

	startData.commandPostMaxHp = TEMP_COMMAND_POST_MAX_HP

	return startData


func ApplyResult(settlement: SettlementState, result: DefenseResult) -> void:
	settlement.population = maxi(settlement.population - result.deadPopulation, 0)
