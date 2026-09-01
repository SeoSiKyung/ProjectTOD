class_name EventResolutionSystem
extends Node

# =========================================================
# 이벤트 선택 결과 적용
# =========================================================


func ApplyChoice(
	campaign: CampaignState,
	settlement: SettlementState,
	story: StoryState,
	eventData: EventData,
	choiceId: StringName,
) -> EventChoiceData:
	if (campaign == null or settlement == null or story == null or eventData == null):
		return null

	var choiceData := eventData.GetChoiceData(choiceId)

	if choiceData == null:
		push_warning("EventResolutionSystem: 선택지를 찾을 수 없습니다: %s" % choiceId)

		return null

	if choiceData.result != null:
		_ApplyResult(campaign, settlement, story, choiceData.result)

	return choiceData

# =========================================================
# 결과 적용
# =========================================================


func _ApplyResult(
	campaign: CampaignState,
	settlement: SettlementState,
	story: StoryState,
	result: EventResultData,
) -> void:
	# =====================================================
	# 자원
	# =====================================================
	settlement.gold = maxi(0, settlement.gold + result.goldChange)

	settlement.food = maxi(0, settlement.food + result.foodChange)

	settlement.wood = maxi(0, settlement.wood + result.woodChange)

	settlement.stone = maxi(0, settlement.stone + result.stoneChange)

	settlement.iron = maxi(0, settlement.iron + result.ironChange)

	settlement.magicStone = maxi(0, settlement.magicStone + result.magicStoneChange)

	# =====================================================
	# 안정도
	# =====================================================
	settlement.stability = clampi(settlement.stability + result.stabilityChange, 0, 100)

	# =====================================================
	# Story Flag 설정
	# =====================================================
	for flag in result.setStoryFlags:
		story.SetStoryFlag(flag, true)

	for flag in result.clearStoryFlags:
		story.SetStoryFlag(flag, false)

	# =====================================================
	# 정보 획득
	# =====================================================
	for intelId in result.intelToAdd:
		story.AddIntel(intelId)

	# =====================================================
	# 지역 해금
	# =====================================================
	for regionId in result.regionsToUnlock:
		campaign.UnlockRegion(regionId)
