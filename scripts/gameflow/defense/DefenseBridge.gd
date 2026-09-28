class_name DefenseBridge
extends Node

const TEMP_CP_MAX_HP: int = 1000

const TEMP_AUTO_CROSSBOW_COUNT: int = 2
const TEMP_CANNON_COUNT: int = 2
const TEMP_SPIKE_TRAP_COUNT: int = 2
const TEMP_EXPLOSIVE_TRAP_COUNT: int = 2


func CreateStartData(campaign: CampaignState, population: int) -> DefenseStartData:
	var startData: DefenseStartData = DefenseStartData.new()
	startData.cycle = campaign.cycle
	startData.population = population

	startData.cpMaxHp = TEMP_CP_MAX_HP

	startData.installableCountByCharacterKey[500] = TEMP_AUTO_CROSSBOW_COUNT
	startData.installableCountByCharacterKey[501] = TEMP_CANNON_COUNT
	startData.installableCountByCharacterKey[750] = TEMP_SPIKE_TRAP_COUNT
	startData.installableCountByCharacterKey[751] = TEMP_EXPLOSIVE_TRAP_COUNT

	startData.availableMercenaryKeys = [1, 2, 3]

	return startData


func ApplyResult(settlement: SettlementState, result: DefenseResult) -> void:
	settlement.population = maxi(settlement.population - result.deadPopulation, 0)
