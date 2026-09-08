class_name TycoonScene
extends Node

# =========================================================
# Data
# =========================================================

const FACILITY_CATALOG: FacilityCatalog = preload("res://data/facility/facility_catalog.tres")

const EVENT_CATALOG: EventCatalog = preload("res://data/event/event_catalog.tres")

# =========================================================
# Runtime
# =========================================================

var _tycoonController: TycoonController

# =========================================================
# UI
# =========================================================

@onready var _eventPopup: EventPopup = ($UI/UIRoot/EventPopup)

# =========================================================
# Lifecycle
# =========================================================


func _ready() -> void:
	_CreateTycoonController()

	_ConnectControllerSignals()

	_ConnectUISignals()

	_StartOrRestoreTycoon()

# =========================================================
# Controller Setup
# =========================================================


func _CreateTycoonController() -> void:
	_tycoonController = TycoonController.new()

	add_child(_tycoonController)

	_tycoonController.Setup(
		GameState.campaign,
		GameState.settlement,
		GameState.story,
		GameState.event,
		FACILITY_CATALOG,
		EVENT_CATALOG,
	)

# =========================================================
# Signal 연결
# =========================================================


func _ConnectControllerSignals() -> void:
	if not _tycoonController.EventRequested.is_connected(_OnEventRequested):
		_tycoonController.EventRequested.connect(_OnEventRequested)

	if not _tycoonController.EventResolved.is_connected(_OnEventResolved):
		_tycoonController.EventResolved.connect(_OnEventResolved)


func _ConnectUISignals() -> void:
	if not _eventPopup.ChoiceSelected.is_connected(_OnEventChoiceSelected):
		_eventPopup.ChoiceSelected.connect(_OnEventChoiceSelected)

	if not _eventPopup.ContinueRequested.is_connected(_OnEventContinueRequested):
		_eventPopup.ContinueRequested.connect(_OnEventContinueRequested)

# =========================================================
# Tycoon 시작 / Load 복구
# =========================================================


func _StartOrRestoreTycoon() -> void:
	# =====================================================
	# Save에서 Active Event가 복구된 경우
	#
	# EventState에 저장되어 있던 Event를
	# EventRequested Signal로 다시 보내 UI에 표시.
	# =====================================================
	if GameState.event.HasActiveEvent():
		var requested: bool = (_tycoonController.RequestActiveEvent())

		if not requested:
			push_warning("TycoonScene: 저장된 Active Event 표시 실패")

		return

	# =====================================================
	# 임시 새 게임 진입 코드
	#
	# 아직 실제 Campaign/GameFlow의 Scene 진입 연결을
	# 완성하지 않았기 때문에 새 게임이면 Cycle 1을 시작.
	#
	# 나중에 GameFlow 연결 시 이 부분은 제거/교체.
	# =====================================================
	if (GameState.campaign.currentTurn == 0 and GameState.campaign.cycleTurnLimit == 0):
		var started: bool = (_tycoonController.StartCycle(5))

		if not started:
			push_warning("TycoonScene: Cycle 시작 실패")

# =========================================================
# Controller -> UI
# =========================================================


func _OnEventRequested(eventData: EventData) -> void:
	if eventData == null:
		return

	_eventPopup.ShowEvent(eventData)


func _OnEventResolved(_eventData: EventData, choiceData: EventChoiceData) -> void:
	if choiceData == null:
		return

	_eventPopup.ShowResult(choiceData)

# =========================================================
# UI -> Controller
# =========================================================


func _OnEventChoiceSelected(choiceId: StringName) -> void:
	var resolved: bool = (_tycoonController.ResolveActiveEvent(choiceId))

	if not resolved:
		push_warning("TycoonScene: Event 선택 처리 실패: " + String(choiceId))


func _OnEventContinueRequested() -> void:
	# =====================================================
	# Pending Event가 있다면 다음 Event 표시
	# =====================================================
	if _tycoonController.HasPendingEvents():
		var requested: bool = (_tycoonController.RequestNextPendingEvent())

		if requested:
			return

	# =====================================================
	# 더 이상 Event가 없으면 Popup 종료
	# =====================================================
	_eventPopup.Close()
