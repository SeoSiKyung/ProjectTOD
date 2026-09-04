class_name DefenseBridge
extends Node


func CreateStartData(campaign: CampaignState, population: int) -> DefenseStartData:
	var startData: DefenseStartData = DefenseStartData.new()
	startData.cycle = campaign.cycle
	startData.population = population

	return startData


func ApplyResult(settlement: SettlementState, result: DefenseResult) -> void:
	settlement.population = maxi(settlement.population - result.deadPopulation, 0)
