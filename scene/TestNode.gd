extends Node

const FACILITY_CATALOG: FacilityCatalog = preload("res://data/facility/facility_catalog.tres")

var _tycoonController: TycoonController
var _eventCatalog: EventCatalog

var _eventRequestedCount: int = 0
var _eventResolvedCount: int = 0

var _requestedEventIds: Array[StringName] = []
var _resolvedEventIds: Array[StringName] = []

var _goldBeforeResults: int = 0
var _foodBeforeResults: int = 0


func _ready() -> void:
	print("")
	print("====================================")
	print("       다중 Event 순차 처리 테스트")
	print("====================================")

	# =====================================================
	# 새 게임
	# =====================================================
	GameState.StartNewGame()

	# =====================================================
	# 테스트 EventCatalog 생성
	# =====================================================
	_CreateTestEventCatalog()

	# =====================================================
	# TycoonController
	# =====================================================
	_tycoonController = TycoonController.new()

	add_child(_tycoonController)

	_tycoonController.Setup(
		GameState.campaign,
		GameState.settlement,
		GameState.story,
		FACILITY_CATALOG,
		_eventCatalog,
	)

	# =====================================================
	# Signal
	# =====================================================
	_tycoonController.EventRequested.connect(_OnEventRequested)

	_tycoonController.EventResolved.connect(_OnEventResolved)

	# =====================================================
	# Cycle 시작
	#
	# Event A / B 둘 다 확률 100%
	#
	# 예상:
	# A → Active
	# B → Pending
	# =====================================================
	print("")
	print("========== Cycle 시작 ==========")

	var started := _tycoonController.StartCycle(5)

	_goldBeforeResults = (GameState.settlement.gold)

	_foodBeforeResults = (GameState.settlement.food)

	print("Cycle Started: ", started)

	print("Active Event: ", _tycoonController.GetActiveEventId())

	print("Event Requested Count: ", _eventRequestedCount)

	print("Pending Count: ", GameState.story.pendingEvents.size())

	print("Pending Events: ", GameState.story.pendingEvents)

	# =====================================================
	# 첫 번째 이벤트 상태 검증
	# =====================================================
	var firstEventActive := (_tycoonController.GetActiveEventId() == &"event_a")

	var secondEventPending := (
		GameState.story.pendingEvents.size() == 1 and GameState.story.pendingEvents[0] == &"event_b"
	)

	print("")
	print("========== 초기 이벤트 상태 ==========")

	print("Event A Is Active: ", firstEventActive)

	print("Event B Is Pending: ", secondEventPending)

	# =====================================================
	# Event A 선택
	#
	# 결과:
	# Gold +100
	# =====================================================
	print("")
	print("========== Event A 처리 ==========")

	var firstResolved := (_tycoonController.ResolveActiveEvent(&"accept_a"))

	print("Event A Resolve Result: ", firstResolved)

	print("Active Event After A: [", _tycoonController.GetActiveEventId(), "]")

	print("Pending Count After A: ", GameState.story.pendingEvents.size())

	print("Gold After A: ", GameState.settlement.gold)

	# =====================================================
	# 중요
	#
	# Event A가 끝났다고 Event B가 자동으로
	# 표시되면 안 됨.
	#
	# UI가 결과 화면을 닫은 뒤
	# RequestNextPendingEvent()를 호출하는 구조.
	# =====================================================
	var noAutomaticSecondEvent := (
		_tycoonController.GetActiveEventId() == &"" and _eventRequestedCount == 1
		and GameState.story.pendingEvents.size() == 1
	)

	print("Event B Not Automatically Opened: ", noAutomaticSecondEvent)

	# =====================================================
	# 다음 Pending Event 요청
	# =====================================================
	print("")
	print("========== 다음 Pending Event 요청 ==========")

	var secondRequested := (_tycoonController.RequestNextPendingEvent())

	print("RequestNextPendingEvent Result: ", secondRequested)

	print("Active Event: ", _tycoonController.GetActiveEventId())

	print("Event Requested Count: ", _eventRequestedCount)

	print("Pending Count: ", GameState.story.pendingEvents.size())

	# =====================================================
	# Event B 선택
	#
	# 결과:
	# Food +50
	# =====================================================
	print("")
	print("========== Event B 처리 ==========")

	var secondResolved := (_tycoonController.ResolveActiveEvent(&"accept_b"))

	print("Event B Resolve Result: ", secondResolved)

	print("Active Event After B: [", _tycoonController.GetActiveEventId(), "]")

	print("Pending Count After B: ", GameState.story.pendingEvents.size())

	print("Food After B: ", GameState.settlement.food)

	# =====================================================
	# 더 이상 Pending Event 없음
	# =====================================================
	print("")
	print("========== 빈 Pending 요청 ==========")

	var thirdRequested := (_tycoonController.RequestNextPendingEvent())

	print("Third Request Result: ", thirdRequested)

	# =====================================================
	# 최종 검증
	# =====================================================
	print("")
	print("========== 결과 검증 ==========")

	print("Cycle Started: ", started)

	print("Event A Was Active First: ", firstEventActive)

	print("Event B Was Pending First: ", secondEventPending)

	print(
		"Only One Event Initially Requested: ",
		_requestedEventIds.size() >= 1 and _requestedEventIds[0] == &"event_a",
	)

	print("Event A Resolved: ", firstResolved)

	print("Event B Did Not Auto Open: ", noAutomaticSecondEvent)

	print("Event B Pending Request Success: ", secondRequested)

	print(
		"Event B Requested Second: ",
		_requestedEventIds.size() == 2 and _requestedEventIds[1] == &"event_b",
	)

	print("Event B Resolved: ", secondResolved)

	print("Event A Gold Result Applied: ", GameState.settlement.gold == _goldBeforeResults + 100)

	print("Event B Food Result Applied: ", GameState.settlement.food == _foodBeforeResults + 50)

	print("Both Events Requested Once: ", _eventRequestedCount == 2)

	print("Both Events Resolved Once: ", _eventResolvedCount == 2)

	print("Requested Order Correct: ", _requestedEventIds == [&"event_a", &"event_b"])

	print("Resolved Order Correct: ", _resolvedEventIds == [&"event_a", &"event_b"])

	print("No Active Event: ", _tycoonController.GetActiveEventId() == &"")

	print("Pending Queue Empty: ", GameState.story.pendingEvents.is_empty())

	print("No Third Event: ", not thirdRequested)

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
	# =====================================================
	var eventA := EventData.new()

	eventA.id = (&"event_a")

	eventA.displayName = ("첫 번째 이벤트")

	eventA.description = ("첫 번째로 처리되어야 하는 이벤트입니다.")

	eventA.triggerChance = 1.0

	# =====================================================
	# Event A Result
	#
	# Gold +100
	# =====================================================
	var eventAResult := EventResultData.new()

	eventAResult.goldChange = 100

	# =====================================================
	# Event A Choice
	# =====================================================
	var eventAChoice := EventChoiceData.new()

	eventAChoice.id = (&"accept_a")

	eventAChoice.displayText = ("첫 번째 선택")

	eventAChoice.resultText = ("첫 번째 이벤트를 처리했습니다.")

	eventAChoice.result = (eventAResult)

	eventA.choices.append(eventAChoice)

	# =====================================================
	# Event B
	# =====================================================
	var eventB := EventData.new()

	eventB.id = (&"event_b")

	eventB.displayName = ("두 번째 이벤트")

	eventB.description = ("첫 번째 이벤트가 끝난 뒤 처리되어야 합니다.")

	eventB.triggerChance = 1.0

	# =====================================================
	# Event B Result
	#
	# Food +50
	# =====================================================
	var eventBResult := EventResultData.new()

	eventBResult.foodChange = 50

	# =====================================================
	# Event B Choice
	# =====================================================
	var eventBChoice := EventChoiceData.new()

	eventBChoice.id = (&"accept_b")

	eventBChoice.displayText = ("두 번째 선택")

	eventBChoice.resultText = ("두 번째 이벤트를 처리했습니다.")

	eventBChoice.result = (eventBResult)

	eventB.choices.append(eventBChoice)

	# =====================================================
	# 순서 중요
	#
	# EventSystem이 Catalog 순서대로 확인하므로
	# A가 먼저, B가 두 번째로 발생.
	# =====================================================
	_eventCatalog.events.append(eventA)

	_eventCatalog.events.append(eventB)

# =========================================================
# Signal
# =========================================================


func _OnEventRequested(eventData: EventData) -> void:
	_eventRequestedCount += 1

	_requestedEventIds.append(eventData.id)

	print("")
	print("[Signal] EventRequested")

	print("ID: ", eventData.id)

	print("Name: ", eventData.displayName)


func _OnEventResolved(eventData: EventData, choiceData: EventChoiceData) -> void:
	_eventResolvedCount += 1

	_resolvedEventIds.append(eventData.id)

	print("")
	print("[Signal] EventResolved")

	print("Event ID: ", eventData.id)

	print("Choice ID: ", choiceData.id)

	print("Result Text: ", choiceData.resultText)
