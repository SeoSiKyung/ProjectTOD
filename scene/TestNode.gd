extends Node

# =========================================================
# 실제 Resource
# =========================================================

const FACILITY_CATALOG: FacilityCatalog = preload("res://data/facility/facility_catalog.tres")

const EVENT_CATALOG: EventCatalog = preload("res://data/event/event_catalog.tres")

# =========================================================
# Controller
# =========================================================

var _controller: TycoonController

var _requestedEventIds: Array[StringName] = []

# =========================================================
# Test
# =========================================================


func _ready() -> void:
	print("")
	print("============================================")
	print("   실제 Event Resource 최종 통합 테스트")
	print("============================================")

	# =====================================================
	# 1. 새 게임
	# =====================================================
	GameState.StartNewGame()

	var gameStateEventExists: bool = (GameState.event != null)

	print("")
	print("========== 1. GameState ==========")

	print("EventState Exists: ", gameStateEventExists)

	# =====================================================
	# 2. 실제 EventCatalog 확인
	# =====================================================
	print("")
	print("========== 2. 실제 EventCatalog ==========")

	var catalogExists: bool = (EVENT_CATALOG != null)

	var eventCountCorrect: bool = (EVENT_CATALOG.events.size() == 2)

	print("Catalog Exists: ", catalogExists)

	print("Event Count: ", EVENT_CATALOG.events.size())

	var tavernRumor: EventData = (EVENT_CATALOG.GetEventData(&"tavern_rumor"))

	var tavernBrawl: EventData = (EVENT_CATALOG.GetEventData(&"tavern_brawl"))

	var tavernRumorExists: bool = (tavernRumor != null)

	var tavernBrawlExists: bool = (tavernBrawl != null)

	print("Tavern Rumor Exists: ", tavernRumorExists)

	print("Tavern Brawl Exists: ", tavernBrawlExists)

	if (not tavernRumorExists or not tavernBrawlExists):
		push_error("TestNode: 실제 Event Resource 로드 실패")

		return

	# =====================================================
	# 실제 Resource 내용 확인
	# =====================================================
	var rumorOneShotCorrect: bool = (tavernRumor.oneShot)

	var brawlRepeatCorrect: bool = (not tavernBrawl.oneShot)

	var rumorChoiceCountCorrect: bool = (tavernRumor.choices.size() == 2)

	var brawlChoiceCountCorrect: bool = (tavernBrawl.choices.size() == 2)

	var rumorConditionExists: bool = (tavernRumor.condition != null)

	var brawlConditionExists: bool = (tavernBrawl.condition != null)

	print("Rumor OneShot: ", rumorOneShotCorrect)

	print("Brawl Repeat: ", brawlRepeatCorrect)

	print("Rumor Choices: ", tavernRumor.choices.size())

	print("Brawl Choices: ", tavernBrawl.choices.size())

	# =====================================================
	# 3. Controller Setup
	# =====================================================
	_controller = TycoonController.new()

	add_child(_controller)

	_controller.Setup(
		GameState.campaign,
		GameState.settlement,
		GameState.story,
		GameState.event,
		FACILITY_CATALOG,
		EVENT_CATALOG,
	)

	_controller.EventRequested.connect(_OnEventRequested)

	# =====================================================
	# 4. Cycle 시작
	#
	# Tavern은 기본 시설이므로
	# 두 Event 조건이 모두 만족해야 함.
	#
	# Catalog 순서:
	# tavern_rumor
	# tavern_brawl
	#
	# 결과:
	# Rumor → Active
	# Brawl → Pending
	# =====================================================
	print("")
	print("========== 3. 실제 Event 발생 ==========")

	var cycleStarted: bool = (_controller.StartCycle(5))

	var activeEventCorrect: bool = (GameState.event.GetActiveEventId() == &"tavern_rumor")

	var pendingIds: Array[StringName] = (GameState.event.GetPendingEventIds())

	var pendingEventCorrect: bool = (pendingIds.size() == 1 and pendingIds[0] == &"tavern_brawl")

	var rumorOneShotRecorded: bool = (GameState.event.HasTriggeredOneShotEvent(&"tavern_rumor"))

	print("Cycle Started: ", cycleStarted)

	print("Active Event: ", GameState.event.GetActiveEventId())

	print("Pending Events: ", GameState.event.GetPendingEventIds())

	print("Triggered OneShot: ", GameState.event.GetTriggeredOneShotEventIds())

	# =====================================================
	# 5. Active Event 동안 시간 진행 행동 차단
	# =====================================================
	print("")
	print("========== 4. Active Event 행동 차단 ==========")

	var turnBeforeBlockedEnd: int = (GameState.campaign.currentTurn)

	var blockedEndTurnResult: bool = (_controller.EndTurn())

	var endTurnBlocked: bool = (
		not blockedEndTurnResult and GameState.campaign.currentTurn == turnBeforeBlockedEnd
	)

	print("EndTurn Return: ", blockedEndTurnResult)

	print("Turn Unchanged: ", GameState.campaign.currentTurn == turnBeforeBlockedEnd)

	print("EndTurn Blocked Correctly: ", endTurnBlocked)

	var phaseBeforeBlockedOffense: CampaignState.Phase = (GameState.campaign.currentPhase)

	var blockedOffenseResult: bool = (_controller.RequestOffense(&"test_region", 1))

	var offenseBlocked: bool = (
		not blockedOffenseResult and GameState.campaign.currentPhase == phaseBeforeBlockedOffense
		and GameState.campaign.currentTurn == turnBeforeBlockedEnd
	)

	print("RequestOffense Return: ", blockedOffenseResult)

	print("Offense Blocked Correctly: ", offenseBlocked)

	# =====================================================
	# 6. 실제 Resource Choice 처리
	#
	# tavern_rumor
	# choice = listen
	#
	# 결과:
	# StoryFlag
	# Intel
	# =====================================================
	print("")
	print("========== 5. Tavern Rumor 처리 ==========")

	var rumorResolved: bool = (_controller.ResolveActiveEvent(&"listen"))

	var rumorFlagApplied: bool = (GameState.story.HasStoryFlag(&"heard_northern_ruins_rumor"))

	var rumorIntelApplied: bool = (GameState.story.HasIntel(&"northern_ruins_rumor"))

	var rumorActiveCleared: bool = (not GameState.event.HasActiveEvent())

	var brawlStillPendingIds: Array[StringName] = (GameState.event.GetPendingEventIds())

	var brawlStillPending: bool = (
		brawlStillPendingIds.size() == 1 and brawlStillPendingIds[0] == &"tavern_brawl"
	)

	print("Rumor Resolved: ", rumorResolved)

	print("Story Flag Applied: ", rumorFlagApplied)

	print("Intel Applied: ", rumorIntelApplied)

	print("Active Cleared: ", rumorActiveCleared)

	print("Brawl Still Pending: ", brawlStillPending)

	# =====================================================
	# 7. Pending Brawl 활성화
	# =====================================================
	print("")
	print("========== 6. Pending Event 활성화 ==========")

	var brawlRequested: bool = (_controller.RequestNextPendingEvent())

	var brawlActive: bool = (GameState.event.GetActiveEventId() == &"tavern_brawl")

	var pendingEmpty: bool = (not GameState.event.HasPendingEvents())

	print("Brawl Requested: ", brawlRequested)

	print("Brawl Active: ", brawlActive)

	print("Pending Empty: ", pendingEmpty)

	# =====================================================
	# 8. 실제 Brawl Choice 처리
	#
	# fine
	#
	# Gold +20
	# Stability -3
	# =====================================================
	print("")
	print("========== 7. Tavern Brawl 처리 ==========")

	var goldBeforeBrawl: int = (GameState.settlement.gold)

	var stabilityBeforeBrawl: int = (GameState.settlement.stability)

	var brawlResolved: bool = (_controller.ResolveActiveEvent(&"fine"))

	var brawlGoldApplied: bool = (GameState.settlement.gold == goldBeforeBrawl + 20)

	var expectedStability: int = (clampi(stabilityBeforeBrawl - 3, 0, 100))

	var brawlStabilityApplied: bool = (GameState.settlement.stability == expectedStability)

	var allEventsResolved: bool = (
		not GameState.event.HasActiveEvent() and not GameState.event.HasPendingEvents()
	)

	print("Brawl Resolved: ", brawlResolved)

	print("Gold Before: ", goldBeforeBrawl)

	print("Gold After: ", GameState.settlement.gold)

	print("Stability Before: ", stabilityBeforeBrawl)

	print("Stability After: ", GameState.settlement.stability)

	print("All Events Resolved: ", allEventsResolved)

	# =====================================================
	# 9. EventState Save
	# =====================================================
	print("")
	print("========== 8. Save / Load ==========")

	var saveData: GameSaveData = (
		GameSaveMapper.CreateSaveData(
			GameState.campaign,
			GameState.settlement,
			GameState.story,
			GameState.event,
		)
	)

	var oneShotSaved: bool = (
		saveData.event.triggeredOneShotEventIds.size() == 1
		and saveData.event.triggeredOneShotEventIds[0] == "tavern_rumor"
	)

	print("Saved Active: [", saveData.event.activeEventId, "]")

	print("Saved Pending: ", saveData.event.pendingEventIds)

	print("Saved OneShot: ", saveData.event.triggeredOneShotEventIds)

	# =====================================================
	# 새로운 Runtime State 복구
	# =====================================================
	var loadedCampaign: CampaignState = (GameSaveMapper.CreateCampaignState(saveData.campaign))

	var loadedSettlement: SettlementState = (
		GameSaveMapper.CreateSettlementState(saveData.settlement)
	)

	var loadedStory: StoryState = (GameSaveMapper.CreateStoryState(saveData.story))

	var loadedEvent: EventState = (GameSaveMapper.CreateEventState(saveData.event))

	GameState.LoadGame(loadedCampaign, loadedSettlement, loadedStory, loadedEvent)

	var oneShotLoaded: bool = (GameState.event.HasTriggeredOneShotEvent(&"tavern_rumor"))

	var storyFlagLoaded: bool = (GameState.story.HasStoryFlag(&"heard_northern_ruins_rumor"))

	var intelLoaded: bool = (GameState.story.HasIntel(&"northern_ruins_rumor"))

	print("OneShot Loaded: ", oneShotLoaded)

	print("Story Flag Loaded: ", storyFlagLoaded)

	print("Intel Loaded: ", intelLoaded)

	# =====================================================
	# 10. 최종 결과
	# =====================================================
	var eventRequestOrderCorrect: bool = (
		_requestedEventIds.size() == 2 and _requestedEventIds[0] == &"tavern_rumor"
		and _requestedEventIds[1] == &"tavern_brawl"
	)

	var allPassed: bool = (
		gameStateEventExists and catalogExists and eventCountCorrect and tavernRumorExists
		and tavernBrawlExists and rumorOneShotCorrect and brawlRepeatCorrect
		and rumorChoiceCountCorrect and brawlChoiceCountCorrect and rumorConditionExists
		and brawlConditionExists and cycleStarted and activeEventCorrect and pendingEventCorrect
		and rumorOneShotRecorded and endTurnBlocked and offenseBlocked and rumorResolved
		and rumorFlagApplied and rumorIntelApplied and rumorActiveCleared and brawlStillPending
		and brawlRequested and brawlActive and pendingEmpty and brawlResolved and brawlGoldApplied
		and brawlStabilityApplied and allEventsResolved and oneShotSaved and oneShotLoaded
		and storyFlagLoaded and intelLoaded and eventRequestOrderCorrect
	)

	print("")
	print("============================================")
	print("               최종 결과")
	print("============================================")

	print("Actual Catalog Loaded: ", catalogExists)

	print("Actual Events Loaded: ", tavernRumorExists and tavernBrawlExists)

	print("Actual Conditions Worked: ", activeEventCorrect and pendingEventCorrect)

	print("Active Event Blocks EndTurn: ", endTurnBlocked)

	print("Active Event Blocks Offense: ", offenseBlocked)

	print("Rumor Result Worked: ", rumorResolved and rumorFlagApplied and rumorIntelApplied)

	print("Pending Flow Worked: ", brawlStillPending and brawlRequested and brawlActive)

	print("Brawl Result Worked: ", brawlResolved and brawlGoldApplied and brawlStabilityApplied)

	print(
		"Event Save / Load Worked: ",
		oneShotSaved and oneShotLoaded and storyFlagLoaded and intelLoaded,
	)

	print("Event Request Order Correct: ", eventRequestOrderCorrect)

	print("")
	print("All Real Event Integration Tests Passed: ", allPassed)

	print("")
	print("============================================")
	print("               테스트 종료")
	print("============================================")

# =========================================================
# Signal
# =========================================================


func _OnEventRequested(eventData: EventData) -> void:
	_requestedEventIds.append(eventData.id)

	print("")
	print("[EventRequested] ", eventData.id, " / ", eventData.displayName)
