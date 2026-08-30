class_name DefenseBridge
extends Node


func CreateStartData(campaign: CampaignState, stats: DerivedStats) -> DefenseStartData:
	var startData := DefenseStartData.new()

	startData.cycle = campaign.cycle

	startData.defensePhysicalAttackBonus = (stats.defensePhysicalAttackBonus)

	return startData
