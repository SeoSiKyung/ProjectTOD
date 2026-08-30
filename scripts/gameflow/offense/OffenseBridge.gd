class_name OffenseBridge
extends Node

# =========================================================
# Offense 시작 데이터 생성
# =========================================================


func CreateStartData(
	campaign: CampaignState,
	regionId: StringName,
	turnCost: int,
) -> OffenseStartData:
	var startData := OffenseStartData.new()

	startData.regionId = regionId
	startData.turnCost = turnCost

	startData.cycle = campaign.cycle
	startData.startTurn = campaign.currentTurn

	return startData

# =========================================================
# Offense 결과 반영
# =========================================================


func ApplyResult(
	campaign: CampaignState,
	settlement: SettlementState,
	story: StoryState,
	result: OffenseResult,
) -> void:
	# =====================================================
	# 자원
	# =====================================================
	settlement.gold += result.goldReward
	settlement.food += result.foodReward
	settlement.wood += result.woodReward
	settlement.stone += result.stoneReward
	settlement.iron += result.ironReward
	settlement.magicStone += result.magicStoneReward

	# =====================================================
	# 정보
	# =====================================================
	for intelId in result.acquiredIntel:
		story.AddIntel(intelId)

	# =====================================================
	# 지역
	# =====================================================
	for regionId in result.unlockedRegions:
		campaign.UnlockRegion(regionId)
