class_name GameSaveMapper
extends RefCounted

# =========================================================
# Runtime State -> SaveData
# =========================================================


static func CreateSaveData(
	campaign: CampaignState,
	settlement: SettlementState,
	story: StoryState,
) -> GameSaveData:
	var saveData := GameSaveData.new()

	saveData.saveVersion = 1

	saveData.campaign = _CreateCampaignSaveData(campaign)

	saveData.settlement = _CreateSettlementSaveData(settlement)

	saveData.story = _CreateStorySaveData(story)

	return saveData

# =========================================================
# SaveData -> Runtime State
# =========================================================


static func CreateCampaignState(saveData: CampaignSaveData) -> CampaignState:
	var campaign := CampaignState.new()

	campaign.cycle = saveData.cycle
	campaign.currentTurn = saveData.currentTurn
	campaign.cycleTurnLimit = saveData.cycleTurnLimit
	campaign.currentPhase = (saveData.currentPhase as CampaignState.Phase)

	for regionId in saveData.unlockedRegions:
		campaign.unlockedRegions.append(StringName(regionId))

	return campaign


static func CreateSettlementState(saveData: SettlementSaveData) -> SettlementState:
	var settlement := SettlementState.new()

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

		facilityState.level = facilitySaveData.level
		facilityState.status = (facilitySaveData.status as FacilityState.Status)

		settlement.facilities.append(facilityState)

	# =====================================================
	# 건설 작업 복원
	# =====================================================
	for taskSaveData in saveData.constructionTasks:
		var constructionTask := ConstructionTask.new()

		constructionTask.facilityId = StringName(taskSaveData.facilityId)

		constructionTask.taskType = (taskSaveData.taskType as ConstructionTask.TaskType)
		constructionTask.targetLevel = taskSaveData.targetLevel
		constructionTask.remainingTurns = taskSaveData.remainingTurns

		settlement.constructionTasks.append(constructionTask)

	return settlement


static func CreateStoryState(saveData: StorySaveData) -> StoryState:
	var story := StoryState.new()

	# Dictionary는 저장 데이터와 런타임 데이터가
	# 같은 객체를 공유하지 않도록 복사
	story.storyFlags = saveData.storyFlags.duplicate(true)

	for intelId in saveData.collectedIntel:
		story.collectedIntel.append(StringName(intelId))

	for eventId in saveData.pendingEvents:
		story.pendingEvents.append(StringName(eventId))

	return story

# =========================================================
# Campaign
# =========================================================


static func _CreateCampaignSaveData(campaign: CampaignState) -> CampaignSaveData:
	var saveData := CampaignSaveData.new()

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

	saveData.gold = settlement.gold
	saveData.food = settlement.food
	saveData.wood = settlement.wood
	saveData.stone = settlement.stone
	saveData.iron = settlement.iron
	saveData.magicStone = settlement.magicStone

	saveData.population = settlement.population
	saveData.stability = settlement.stability

	for facilityState in settlement.facilities:
		var facilitySaveData := FacilitySaveData.new()

		facilitySaveData.facilityId = String(facilityState.facilityId)

		facilitySaveData.level = facilityState.level
		facilitySaveData.status = facilityState.status

		saveData.facilities.append(facilitySaveData)

	for constructionTask in settlement.constructionTasks:
		var taskSaveData := ConstructionTaskSaveData.new()

		taskSaveData.facilityId = String(constructionTask.facilityId)

		taskSaveData.taskType = constructionTask.taskType
		taskSaveData.targetLevel = constructionTask.targetLevel
		taskSaveData.remainingTurns = constructionTask.remainingTurns

		saveData.constructionTasks.append(taskSaveData)

	return saveData

# =========================================================
# Story
# =========================================================


static func _CreateStorySaveData(story: StoryState) -> StorySaveData:
	var saveData := StorySaveData.new()

	saveData.storyFlags = story.storyFlags.duplicate(true)

	for intelId in story.collectedIntel:
		saveData.collectedIntel.append(String(intelId))

	for eventId in story.pendingEvents:
		saveData.pendingEvents.append(String(eventId))

	return saveData
