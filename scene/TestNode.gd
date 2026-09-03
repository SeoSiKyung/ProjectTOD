extends Node

const FACILITY_CATALOG: FacilityCatalog = preload("res://data/facility/facility_catalog.tres")

var _eventCatalog: EventCatalog

var _firstController: TycoonController
var _loadedController: TycoonController

var _beforeSaveRequestedCount: int = 0
var _afterLoadRequestedCount: int = 0

var _loadedRequestedEventIds: Array[StringName] = []


func _ready() -> void:
	print("")
	print("====================================")
	print("       Active Event Save 테스트")
	print("====================================")

	# =====================================================
	# 새 게임
	#
	# GameState
	# ├ campaign
	# ├ settlement
	# ├ story
	# └ event
	# =====================================================
	GameState.StartNewGame()

	print("")
	print("========== 초기 GameState 확인 ==========")

	print("Event State Exists: ", GameState.event != null)

	# =====================================================
	# 테스트 Event Catalog
	# =====================================================
	_CreateTestEventCatalog()

	# =====================================================
	# 첫 번째 TycoonController
	# =====================================================
	_firstController = TycoonController.new()

	add_child(_firstController)

	_firstController.Setup(
		GameState.campaign,
		GameState.settlement,
		GameState.story,
		GameState.event,
		FACILITY_CATALOG,
		_eventCatalog,
	)

	_firstController.EventRequested.connect(_OnBeforeSaveEventRequested)

	# =====================================================
	# Cycle 시작
	#
	# Event A
	# → OneShot
	# → Active
	#
	# Event B
	# → 반복 가능
	# → Pending
	# =====================================================
	print("")
	print("========== 이벤트 발생 ==========")

	var started: bool = (_firstController.StartCycle(5))

	print("Cycle Started: ", started)

	print("Active Before Save: ", GameState.event.GetActiveEventId())

	print("Pending Before Save: ", GameState.event.GetPendingEventIds())

	print("OneShot Before Save: ", GameState.event.GetTriggeredOneShotEventIds())

	print("Before Save Request Count: ", _beforeSaveRequestedCount)

	# =====================================================
	# 저장 직전 상태 검증
	# =====================================================
	var activeBeforeSaveCorrect: bool = (GameState.event.GetActiveEventId() == &"event_a")

	var pendingBeforeSaveIds: Array[StringName] = (GameState.event.GetPendingEventIds())

	var pendingBeforeSaveCorrect: bool = (
		pendingBeforeSaveIds.size() == 1 and pendingBeforeSaveIds[0] == &"event_b"
	)

	var oneShotBeforeSaveCorrect: bool = (GameState.event.HasTriggeredOneShotEvent(&"event_a"))

	print("")
	print("========== 저장 전 상태 검증 ==========")

	print("Event A Active: ", activeBeforeSaveCorrect)

	print("Event B Pending: ", pendingBeforeSaveCorrect)

	print("Event A OneShot Recorded: ", oneShotBeforeSaveCorrect)

	# =====================================================
	# Save
	#
	# Event A를 선택하지 않은 상태에서 저장.
	# =====================================================
	print("")
	print("========== Save ==========")

	var saveData: GameSaveData = (
		GameSaveMapper.CreateSaveData(
			GameState.campaign,
			GameState.settlement,
			GameState.story,
			GameState.event,
		)
	)

	print("Saved Active: ", saveData.event.activeEventId)

	print("Saved Pending: ", saveData.event.pendingEventIds)

	print("Saved OneShot: ", saveData.event.triggeredOneShotEventIds)

	# =====================================================
	# SaveData 검증
	# =====================================================
	var activeSavedCorrectly: bool = (saveData.event.activeEventId == "event_a")

	var pendingSavedCorrectly: bool = (
		saveData.event.pendingEventIds.size() == 1
		and saveData.event.pendingEventIds[0] == "event_b"
	)

	var oneShotSavedCorrectly: bool = (
		saveData.event.triggeredOneShotEventIds.size() == 1
		and saveData.event.triggeredOneShotEventIds[0] == "event_a"
	)

	print("")
	print("========== SaveData 검증 ==========")

	print("Active Saved Correctly: ", activeSavedCorrectly)

	print("Pending Saved Correctly: ", pendingSavedCorrectly)

	print("OneShot Saved Correctly: ", oneShotSavedCorrectly)

	# =====================================================
	# SaveData -> 새로운 Runtime State
	#
	# 실제 게임을 껐다 켠 상황을 흉내냄.
	# =====================================================
	print("")
	print("========== Runtime State 복구 ==========")

	var loadedCampaign: CampaignState = (GameSaveMapper.CreateCampaignState(saveData.campaign))

	var loadedSettlement: SettlementState = (
		GameSaveMapper.CreateSettlementState(saveData.settlement)
	)

	var loadedStory: StoryState = (GameSaveMapper.CreateStoryState(saveData.story))

	var loadedEvent: EventState = (GameSaveMapper.CreateEventState(saveData.event))

	# =====================================================
	# GameState에 복구 State 장착
	# =====================================================
	GameState.LoadGame(loadedCampaign, loadedSettlement, loadedStory, loadedEvent)

	print("Loaded Active: ", GameState.event.GetActiveEventId())

	print("Loaded Pending: ", GameState.event.GetPendingEventIds())

	print("Loaded OneShot: ", GameState.event.GetTriggeredOneShotEventIds())

	# =====================================================
	# 로드 직후 상태를 바로 검증
	#
	# 이후 Event A를 처리하면 Active가 비워지므로
	# 반드시 여기서 먼저 기록.
	# =====================================================
	var activeLoadedCorrectly: bool = (GameState.event.GetActiveEventId() == &"event_a")

	var loadedPendingIds: Array[StringName] = (GameState.event.GetPendingEventIds())

	var pendingLoadedCorrectly: bool = (
		loadedPendingIds.size() == 1 and loadedPendingIds[0] == &"event_b"
	)

	var oneShotLoadedCorrectly: bool = (GameState.event.HasTriggeredOneShotEvent(&"event_a"))

	print("")
	print("========== 로드 상태 검증 ==========")

	print("Active Restored Correctly: ", activeLoadedCorrectly)

	print("Pending Restored Correctly: ", pendingLoadedCorrectly)

	print("OneShot Restored Correctly: ", oneShotLoadedCorrectly)

	# =====================================================
	# 새로운 Controller 생성
	#
	# GameState는 Load된 새로운 State를 가지고 있음.
	# =====================================================
	_loadedController = TycoonController.new()

	add_child(_loadedController)

	_loadedController.Setup(
		GameState.campaign,
		GameState.settlement,
		GameState.story,
		GameState.event,
		FACILITY_CATALOG,
		_eventCatalog,
	)

	_loadedController.EventRequested.connect(_OnAfterLoadEventRequested)

	# =====================================================
	# 중요
	#
	# Setup 과정에서 Active Event가 사라지면 안 됨.
	# =====================================================
	var activeSurvivedControllerSetup: bool = (GameState.event.GetActiveEventId() == &"event_a")

	print("")
	print("========== Controller 재생성 ==========")

	print("Active Survived Setup: ", activeSurvivedControllerSetup)

	# =====================================================
	# 저장되어 있던 Active Event 다시 표시
	#
	# 실제로는 Tycoon Scene UI 준비 완료 후 호출.
	# =====================================================
	print("")
	print("========== Active Event 재표시 ==========")

	var activeRequested: bool = (_loadedController.RequestActiveEvent())

	print("RequestActiveEvent Result: ", activeRequested)

	print("Active After Request: ", GameState.event.GetActiveEventId())

	print("Pending After Request: ", GameState.event.GetPendingEventIds())

	print("After Load Request Count: ", _afterLoadRequestedCount)

	var eventARequestedAfterLoad: bool = (
		_loadedRequestedEventIds.size() == 1 and _loadedRequestedEventIds[0] == &"event_a"
	)

	# =====================================================
	# 복구된 Event A 처리
	#
	# Gold +100
	# =====================================================
	print("")
	print("========== 복구된 Event A 처리 ==========")

	var goldBeforeA: int = (GameState.settlement.gold)

	var eventAResolved: bool = (_loadedController.ResolveActiveEvent(&"accept_a"))

	var eventAResultApplied: bool = (GameState.settlement.gold == goldBeforeA + 100)

	var activeClearedAfterA: bool = (not GameState.event.HasActiveEvent())

	var pendingAfterAIds: Array[StringName] = (GameState.event.GetPendingEventIds())

	var eventBStillPending: bool = (
		pendingAfterAIds.size() == 1 and pendingAfterAIds[0] == &"event_b"
	)

	print("Event A Resolve Result: ", eventAResolved)

	print("Gold After A: ", GameState.settlement.gold)

	print("Active After A: [", GameState.event.GetActiveEventId(), "]")

	print("Pending After A: ", GameState.event.GetPendingEventIds())

	# =====================================================
	# Pending B → Active
	# =====================================================
	print("")
	print("========== Pending Event B 요청 ==========")

	var eventBRequested: bool = (_loadedController.RequestNextPendingEvent())

	var eventBActive: bool = (GameState.event.GetActiveEventId() == &"event_b")

	var pendingEmptyAfterBActivation: bool = (not GameState.event.HasPendingEvents())

	print("Event B Request Result: ", eventBRequested)

	print("Active Event: ", GameState.event.GetActiveEventId())

	print("Pending Events: ", GameState.event.GetPendingEventIds())

	var eventBRequestedSecond: bool = (
		_loadedRequestedEventIds.size() == 2 and _loadedRequestedEventIds[1] == &"event_b"
	)

	# =====================================================
	# Event B 처리
	#
	# Food +50
	# =====================================================
	print("")
	print("========== Event B 처리 ==========")

	var foodBeforeB: int = (GameState.settlement.food)

	var eventBResolved: bool = (_loadedController.ResolveActiveEvent(&"accept_b"))

	var eventBResultApplied: bool = (GameState.settlement.food == foodBeforeB + 50)

	var noActiveEvent: bool = (not GameState.event.HasActiveEvent())

	var noPendingEvents: bool = (not GameState.event.HasPendingEvents())

	var oneShotStillRecorded: bool = (GameState.event.HasTriggeredOneShotEvent(&"event_a"))

	print("Event B Resolve Result: ", eventBResolved)

	print("Food After B: ", GameState.settlement.food)

	print("Final Active: [", GameState.event.GetActiveEventId(), "]")

	print("Final Pending: ", GameState.event.GetPendingEventIds())

	print("Final OneShot: ", GameState.event.GetTriggeredOneShotEventIds())

	# =====================================================
	# 최종 검증
	# =====================================================
	print("")
	print("========== 결과 검증 ==========")

	print("Event State Exists: ", GameState.event != null)

	print("Cycle Started: ", started)

	print("Active Before Save Correct: ", activeBeforeSaveCorrect)

	print("Pending Before Save Correct: ", pendingBeforeSaveCorrect)

	print("OneShot Before Save Correct: ", oneShotBeforeSaveCorrect)

	print("Active Saved Correctly: ", activeSavedCorrectly)

	print("Pending Saved Correctly: ", pendingSavedCorrectly)

	print("OneShot Saved Correctly: ", oneShotSavedCorrectly)

	print("Active Loaded Correctly: ", activeLoadedCorrectly)

	print("Pending Loaded Correctly: ", pendingLoadedCorrectly)

	print("OneShot Loaded Correctly: ", oneShotLoadedCorrectly)

	print("Active Survived Controller Setup: ", activeSurvivedControllerSetup)

	print("Active Event Re-Requested: ", activeRequested)

	print("Loaded Event A Requested First: ", eventARequestedAfterLoad)

	print("Event A Resolved After Load: ", eventAResolved)

	print("Event A Result Applied Once: ", eventAResultApplied)

	print("Active Cleared After A: ", activeClearedAfterA)

	print("Event B Stayed Pending: ", eventBStillPending)

	print("Event B Requested From Pending: ", eventBRequested)

	print("Event B Became Active: ", eventBActive)

	print("Pending Removed On Activation: ", pendingEmptyAfterBActivation)

	print("Loaded Event B Requested Second: ", eventBRequestedSecond)

	print("Event B Resolved: ", eventBResolved)

	print("Event B Result Applied: ", eventBResultApplied)

	print("OneShot Record Still Exists: ", oneShotStillRecorded)

	print("No Active Event: ", noActiveEvent)

	print("No Pending Events: ", noPendingEvents)

	# =====================================================
	# 전체 결과
	# =====================================================
	var allPassed: bool = (
		GameState.event != null and started and activeBeforeSaveCorrect and pendingBeforeSaveCorrect
		and oneShotBeforeSaveCorrect and activeSavedCorrectly and pendingSavedCorrectly
		and oneShotSavedCorrectly and activeLoadedCorrectly and pendingLoadedCorrectly
		and oneShotLoadedCorrectly and activeSurvivedControllerSetup and activeRequested
		and eventARequestedAfterLoad and eventAResolved and eventAResultApplied
		and activeClearedAfterA and eventBStillPending and eventBRequested and eventBActive
		and pendingEmptyAfterBActivation and eventBRequestedSecond and eventBResolved
		and eventBResultApplied and oneShotStillRecorded and noActiveEvent and noPendingEvents
	)

	print("")
	print("All Active Event Save Tests Passed: ", allPassed)

	print("")
	print("====================================")
	print("             테스트 종료")
	print("====================================")

# =========================================================
# 테스트 EventCatalog
# =========================================================


func _CreateTestEventCatalog() -> void:
	_eventCatalog = EventCatalog.new()

	# =====================================================
	# Event A
	#
	# OneShot
	# Active
	# Gold +100
	# =====================================================
	var eventA: EventData = (EventData.new())

	eventA.id = (&"event_a")

	eventA.displayName = ("저장 테스트 이벤트 A")

	eventA.description = ("저장 시 Active 상태로 남아야 합니다.")

	eventA.triggerChance = 1.0
	eventA.oneShot = true

	var eventAResult: EventResultData = (EventResultData.new())

	eventAResult.goldChange = 100

	var eventAChoice: EventChoiceData = (EventChoiceData.new())

	eventAChoice.id = (&"accept_a")

	eventAChoice.displayText = ("A 선택")

	eventAChoice.resultText = ("복구된 이벤트 A를 처리했습니다.")

	eventAChoice.result = (eventAResult)

	eventA.choices.append(eventAChoice)

	# =====================================================
	# Event B
	#
	# Repeat
	# Pending
	# Food +50
	# =====================================================
	var eventB: EventData = (EventData.new())

	eventB.id = (&"event_b")

	eventB.displayName = ("저장 테스트 이벤트 B")

	eventB.description = ("저장 시 Pending 상태로 남아야 합니다.")

	eventB.triggerChance = 1.0
	eventB.oneShot = false

	var eventBResult: EventResultData = (EventResultData.new())

	eventBResult.foodChange = 50

	var eventBChoice: EventChoiceData = (EventChoiceData.new())

	eventBChoice.id = (&"accept_b")

	eventBChoice.displayText = ("B 선택")

	eventBChoice.resultText = ("복구된 Pending 이벤트 B를 처리했습니다.")

	eventBChoice.result = (eventBResult)

	eventB.choices.append(eventBChoice)

	# =====================================================
	# Catalog 순서
	#
	# A → Active
	# B → Pending
	# =====================================================
	_eventCatalog.events.append(eventA)

	_eventCatalog.events.append(eventB)

# =========================================================
# Signal
# =========================================================


func _OnBeforeSaveEventRequested(eventData: EventData) -> void:
	_beforeSaveRequestedCount += 1

	print("")
	print("[Before Save] EventRequested: ", eventData.id)


func _OnAfterLoadEventRequested(eventData: EventData) -> void:
	_afterLoadRequestedCount += 1

	_loadedRequestedEventIds.append(eventData.id)

	print("")
	print("[After Load] EventRequested: ", eventData.id)
