class_name DefenseBridge
extends Node


# 타이쿤에서 호출
func CreateStartData(campaign: CampaignState, population: int) -> DefenseStartData:
	var startData: DefenseStartData = DefenseStartData.new()
	startData.cycle = campaign.cycle
	startData.population = population

	return startData
