class_name GameSaveMapper
extends RefCounted

# =========================================================
# Runtime State -> SaveData
# =========================================================


static func CreateSaveData(
	campaign: CampaignState,
	settlement: SettlementState,
	story: StoryState,
	eventState: EventState,
) -> GameSaveData:
	var saveData := GameSaveData.new()

	saveData.saveVersion = 1

	saveData.campaign = _CreateCampaignSaveData(campaign)

	saveData.settlement = _CreateSettlementSaveData(settlement)

	saveData.story = _CreateStorySaveData(story)

	saveData.event = _CreateEventSaveData(eventState)

	return saveData

# =========================================================
# SaveData -> Runtime State
# =========================================================


static func CreateCampaignState(saveData: CampaignSaveData) -> CampaignState:
	var campaign := CampaignState.new()

	if saveData == null:
		return campaign

	campaign.cycle = saveData.cycle
	campaign.currentTurn = saveData.currentTurn
	campaign.cycleTurnLimit = saveData.cycleTurnLimit

	campaign.currentPhase = (saveData.currentPhase as CampaignState.Phase)

	for regionId in saveData.unlockedRegions:
		campaign.unlockedRegions.append(StringName(regionId))

	return campaign


static func CreateSettlementState(saveData: SettlementSaveData) -> SettlementState:
	var settlement := SettlementState.new()

	if saveData == null:
		return settlement

	settlement.gold = saveData.gold
	settlement.food = saveData.food
	settlement.wood = saveData.wood
	settlement.stone = saveData.stone
	settlement.iron = saveData.iron
	settlement.magicStone = saveData.magicStone

	settlement.population = saveData.population
	settlement.stability = saveData.stability

	# =====================================================
	# 시설 복원
	# =====================================================
	for facilitySaveData in saveData.facilities:
		var facilityState := FacilityState.new()

		facilityState.facilityId = StringName(facilitySaveData.facilityId)

		facilityState.level = (facilitySaveData.level)

		facilityState.status = (facilitySaveData.status as FacilityState.Status)

		settlement.facilities.append(facilityState)

	# =====================================================
	# 건설 작업 복원
	# =====================================================
	for taskSaveData in saveData.constructionTasks:
		var constructionTask := ConstructionTask.new()

		constructionTask.facilityId = StringName(taskSaveData.facilityId)

		constructionTask.taskType = (taskSaveData.taskType as ConstructionTask.TaskType)

		constructionTask.targetLevel = (taskSaveData.targetLevel)

		constructionTask.remainingTurns = (taskSaveData.remainingTurns)

		settlement.constructionTasks.append(constructionTask)

	return settlement


static func CreateStoryState(saveData: StorySaveData) -> StoryState:
	var story := StoryState.new()

	if saveData == null:
		return story

	# =====================================================
	# Story Flag
	# =====================================================
	story.storyFlags = (saveData.storyFlags.duplicate(true))

	# =====================================================
	# Intel
	# =====================================================
	for intelId in saveData.collectedIntel:
		story.collectedIntel.append(StringName(intelId))

	return story


static func CreateEventState(saveData: EventSaveData) -> EventState:
	var eventState := EventState.new()

	if saveData == null:
		return eventState

	# =====================================================
	# Pending Event 변환
	#
	# Save:
	# Array[String]
	#
	# Runtime:
	# Array[StringName]
	# =====================================================
	var pendingEventIds: Array[StringName] = []

	for eventId in saveData.pendingEventIds:
		pendingEventIds.append(StringName(eventId))

	# =====================================================
	# Triggered OneShot Event 변환
	# =====================================================
	var triggeredOneShotEventIds: Array[StringName] = []

	for eventId in saveData.triggeredOneShotEventIds:
		triggeredOneShotEventIds.append(StringName(eventId))

	# =====================================================
	# EventState 복원
	#
	# Active / Pending / OneShot 기록을
	# EventState가 자기 메서드를 통해 복구.
	# =====================================================
	eventState.Restore(
		StringName(saveData.activeEventId),
		pendingEventIds,
		triggeredOneShotEventIds,
	)

	return eventState

# =========================================================
# Campaign
# =========================================================


static func _CreateCampaignSaveData(campaign: CampaignState) -> CampaignSaveData:
	var saveData := CampaignSaveData.new()

	if campaign == null:
		return saveData

	saveData.cycle = campaign.cycle
	saveData.currentTurn = campaign.currentTurn
	saveData.cycleTurnLimit = campaign.cycleTurnLimit
	saveData.currentPhase = campaign.currentPhase

	for regionId in campaign.unlockedRegions:
		saveData.unlockedRegions.append(String(regionId))

	return saveData

# =========================================================
# Settlement
# =========================================================


static func _CreateSettlementSaveData(settlement: SettlementState) -> SettlementSaveData:
	var saveData := SettlementSaveData.new()

	if settlement == null:
		return saveData

	saveData.gold = settlement.gold
	saveData.food = settlement.food
	saveData.wood = settlement.wood
	saveData.stone = settlement.stone
	saveData.iron = settlement.iron
	saveData.magicStone = settlement.magicStone

	saveData.population = settlement.population
	saveData.stability = settlement.stability

	# =====================================================
	# 시설
	# =====================================================
	for facilityState in settlement.facilities:
		var facilitySaveData := FacilitySaveData.new()

		facilitySaveData.facilityId = String(facilityState.facilityId)

		facilitySaveData.level = (facilityState.level)

		facilitySaveData.status = (facilityState.status)

		saveData.facilities.append(facilitySaveData)

	# =====================================================
	# 건설 작업
	# =====================================================
	for constructionTask in settlement.constructionTasks:
		var taskSaveData := ConstructionTaskSaveData.new()

		taskSaveData.facilityId = String(constructionTask.facilityId)

		taskSaveData.taskType = (constructionTask.taskType)

		taskSaveData.targetLevel = (constructionTask.targetLevel)

		taskSaveData.remainingTurns = (constructionTask.remainingTurns)

		saveData.constructionTasks.append(taskSaveData)

	return saveData

# =========================================================
# Story
# =========================================================


static func _CreateStorySaveData(story: StoryState) -> StorySaveData:
	var saveData := StorySaveData.new()

	if story == null:
		return saveData

	# =====================================================
	# Story Flag
	# =====================================================
	saveData.storyFlags = (story.storyFlags.duplicate(true))

	# =====================================================
	# Intel
	# =====================================================
	for intelId in story.collectedIntel:
		saveData.collectedIntel.append(String(intelId))

	return saveData

# =========================================================
# Event
# =========================================================


static func _CreateEventSaveData(eventState: EventState) -> EventSaveData:
	var saveData := EventSaveData.new()

	if eventState == null:
		return saveData

	# =====================================================
	# Active Event
	# =====================================================
	saveData.activeEventId = String(eventState.GetActiveEventId())

	# =====================================================
	# Pending Events
	# =====================================================
	for eventId in eventState.GetPendingEventIds():
		saveData.pendingEventIds.append(String(eventId))

	# =====================================================
	# 발생한 OneShot Events
	# =====================================================
	for eventId in eventState.GetTriggeredOneShotEventIds():
		saveData.triggeredOneShotEventIds.append(String(eventId))

	return saveData
