class_name EventSystem
extends Node

var _eventCatalog: EventCatalog

var _random: RandomNumberGenerator

# =========================================================
# 초기화
# =========================================================


func Setup(eventCatalog: EventCatalog) -> void:
	_eventCatalog = eventCatalog

	_random = RandomNumberGenerator.new()

	_random.randomize()

# =========================================================
# Turn 시작 Event 판정
# =========================================================


func ProcessTurnStart(
	campaign: CampaignState,
	settlement: SettlementState,
	story: StoryState,
	eventState: EventState,
	context: TurnContext,
) -> void:
	if (
		_eventCatalog == null or campaign == null or settlement == null
		or story == null or eventState == null or context == null
	):
		return

	for eventData in _eventCatalog.events:
		if eventData == null:
			continue

		if eventData.id == &"":
			continue

		# =================================================
		# 1회성 Event 검사
		# =================================================
		if (eventData.oneShot and eventState.HasTriggeredOneShotEvent(eventData.id)):
			continue

		# =================================================
		# 발생 조건
		# =================================================
		if not _MeetsConditions(eventData, campaign, settlement, story):
			continue

		# =================================================
		# 발생 확률
		# =================================================
		if not _RollTriggerChance(eventData.triggerChance):
			continue

		# =================================================
		# 발생 확정
		# =================================================
		context.triggeredEvents.append(eventData.id)

		# =================================================
		# One Shot 발생 기록
		#
		# "처리 완료"가 아니라
		# "발생한 적 있음"을 기록.
		# =================================================
		if eventData.oneShot:
			eventState.MarkOneShotTriggered(eventData.id)

# =========================================================
# 발생 조건
# =========================================================


func _MeetsConditions(
	eventData: EventData,
	campaign: CampaignState,
	settlement: SettlementState,
	story: StoryState,
) -> bool:
	var condition := eventData.condition

	if condition == null:
		return true

	# =====================================================
	# Cycle
	# =====================================================
	if (condition.minCycle > 0 and campaign.cycle < condition.minCycle):
		return false

	if (condition.maxCycle > 0 and campaign.cycle > condition.maxCycle):
		return false

	# =====================================================
	# StoryFlag
	# =====================================================
	for flag in condition.requiredStoryFlags:
		if not story.HasStoryFlag(flag):
			return false

	for flag in condition.excludedStoryFlags:
		if story.HasStoryFlag(flag):
			return false

	# =====================================================
	# Intel
	# =====================================================
	for intelId in condition.requiredIntelIds:
		if not story.HasIntel(intelId):
			return false

	# =====================================================
	# Facility
	# =====================================================
	for facilityId in condition.requiredFacilityIds:
		var facilityState := settlement.GetFacility(facilityId)

		if facilityState == null:
			return false

		if not facilityState.IsBuilt():
			return false

	return true

# =========================================================
# 확률
# =========================================================


func _RollTriggerChance(triggerChance: float) -> bool:
	if triggerChance <= 0.0:
		return false

	if triggerChance >= 1.0:
		return true

	return (_random.randf() < triggerChance)

# =========================================================
# Event 조회
# =========================================================


func GetEventData(eventId: StringName) -> EventData:
	if _eventCatalog == null:
		return null

	return _eventCatalog.GetEventData(eventId)
