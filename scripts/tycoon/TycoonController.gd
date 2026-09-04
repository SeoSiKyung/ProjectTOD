class_name TycoonController
extends Node

signal TurnReady(currentTurn: int)
signal SettlementChanged()

signal EventRequested(eventData: EventData)
signal EventResolved(eventData: EventData, choiceData: EventChoiceData)

signal OffenseRequested(startData: OffenseStartData)
signal OffenseFinished(result: OffenseResult)

signal DefenseRequested(startData: DefenseStartData)

var _campaign: CampaignState
var _settlement: SettlementState
var _story: StoryState
var _eventState: EventState

var _currentStats: DerivedStats
var _currentTurnContext: TurnContext

var _facilitySystem: FacilitySystem
var _constructionSystem: ConstructionSystem
var _statSystem: StatSystem
var _productionSystem: ProductionSystem
var _populationSystem: PopulationSystem
var _stabilitySystem: StabilitySystem
var _facilityInteractionSystem: FacilityInteractionSystem

var _eventSystem: EventSystem
var _eventResolutionSystem: EventResolutionSystem

var _turnSystem: TurnSystem

var _offenseBridge: OffenseBridge
var _defenseBridge: DefenseBridge

# =========================================================
# 초기화
# =========================================================


func Setup(
	campaign: CampaignState,
	settlement: SettlementState,
	story: StoryState,
	eventState: EventState,
	facilityCatalog: FacilityCatalog,
	eventCatalog: EventCatalog,
) -> void:
	_campaign = campaign
	_settlement = settlement
	_story = story
	_eventState = eventState

	_CreateSystems()

	_facilitySystem.Setup(facilityCatalog)

	_statSystem.Setup(facilityCatalog)

	_facilityInteractionSystem.Setup(facilityCatalog)

	_eventSystem.Setup(eventCatalog)

	_RefreshStats()


func _CreateSystems() -> void:
	_facilitySystem = FacilitySystem.new()
	_constructionSystem = ConstructionSystem.new()
	_statSystem = StatSystem.new()
	_productionSystem = ProductionSystem.new()
	_populationSystem = PopulationSystem.new()
	_stabilitySystem = StabilitySystem.new()
	_facilityInteractionSystem = FacilityInteractionSystem.new()

	_eventSystem = EventSystem.new()
	_eventResolutionSystem = EventResolutionSystem.new()

	_turnSystem = TurnSystem.new()

	_offenseBridge = OffenseBridge.new()
	_defenseBridge = DefenseBridge.new()

	add_child(_facilitySystem)

	add_child(_constructionSystem)

	add_child(_statSystem)

	add_child(_productionSystem)

	add_child(_populationSystem)

	add_child(_stabilitySystem)

	add_child(_facilityInteractionSystem)

	add_child(_eventSystem)

	add_child(_eventResolutionSystem)

	add_child(_turnSystem)

	add_child(_offenseBridge)

	add_child(_defenseBridge)

# =========================================================
# 사이클
# =========================================================


func StartCycle(turnLimit: int) -> bool:
	if (_campaign == null or _settlement == null):
		push_error("TycoonController: 게임 State가 설정되지 않았습니다.")

		return false

	_ProcessCycleStart()

	var success := _turnSystem.StartCycle(_campaign, turnLimit)

	if not success:
		return false

	_ProcessTurnStart()

	return true


func PrepareNextCycle() -> void:
	if _campaign == null:
		return

	# =====================================================
	# Defense 승리 여부는 여기서 판단하지 않음.
	#
	# 상위 GameFlow가 Defense 결과를 판단한 뒤
	# 다음 Tycoon Cycle로 진행하기로 결정했을 때
	# 이 함수를 호출.
	# =====================================================
	_campaign.cycle += 1

	_campaign.currentTurn = 0
	_campaign.cycleTurnLimit = 0

	_campaign.currentPhase = (CampaignState.Phase.TYCOON)


func _ProcessCycleStart() -> void:
	# 추후:
	# 교회 사이클 버프
	# 제국연구소 기술 복원
	# 사이클 시작 이벤트
	pass

# =========================================================
# 턴
# =========================================================


func EndTurn() -> bool:
	if _campaign == null:
		return false
	if (_eventState != null and _eventState.HasActiveEvent()):
		push_warning("TycoonController: 현재 이벤트를 먼저 처리해야 합니다.")

		return false
	var hasNextTurn := _turnSystem.EndTurn(_campaign)

	# =====================================================
	# 마지막 턴 종료
	#
	# TycoonController는
	# "Defense를 시작해야 한다"까지만 결정.
	#
	# Defense 승패 / Game Over 판단은
	# 상위 GameFlow의 책임.
	# =====================================================
	if not hasNextTurn:
		_RequestDefense()

		return false

	_ProcessTurnStart()

	return true


func _ProcessTurnStart(notifyPlayer: bool = true) -> void:
	# =====================================================
	# 1. 이번 턴 Context 생성
	# =====================================================
	_currentTurnContext = TurnContext.new()

	# =====================================================
	# 2. 현재 완공 시설 기준 Stat 계산
	# =====================================================
	_RefreshStats()

	_currentTurnContext.stats = (_currentStats)

	# =====================================================
	# 3. 자원 생산
	# =====================================================
	_productionSystem.ProcessTurnStart(_settlement, _currentTurnContext)

	# =====================================================
	# 4. 식량 소비
	# =====================================================
	_populationSystem.ProcessFoodConsumption(_settlement, _currentTurnContext)

	# =====================================================
	# 5. 안정도
	# =====================================================
	_stabilitySystem.ProcessTurnStart(_settlement, _currentTurnContext)

	# =====================================================
	# 6. 인구 증감
	# =====================================================
	_populationSystem.ProcessPopulationChange(_settlement, _currentTurnContext)

	# =====================================================
	# 7. 건설 / 업그레이드 진행
	# =====================================================
	_constructionSystem.ProcessTurnStart(_settlement)

	# =====================================================
	# 8. 완공 시설 포함 Stat 재계산
	# =====================================================
	_RefreshStats()

	# =====================================================
	# 9. 게임 이벤트 발생 판정
	# =====================================================
	_eventSystem.ProcessTurnStart(_campaign, _settlement, _story, _eventState, _currentTurnContext)

	# =====================================================
	# 10. 발생한 게임 이벤트 처리
	#
	# TYCOON
	# → 현재 이벤트가 없으면 즉시 표시
	# → 이미 이벤트 처리 중이면 Pending
	#
	# OFFENSE
	# → Pending
	# =====================================================
	_ProcessTriggeredEvents()

	# =====================================================
	# 일반 Tycoon 턴에서만 외부 알림
	#
	# Offense 중 흐르는 턴은
	# 영지 시뮬레이션만 수행.
	# =====================================================
	if notifyPlayer:
		TurnReady.emit(_campaign.currentTurn)

		SettlementChanged.emit()

# =========================================================
# 게임 이벤트
# =========================================================


func _ProcessTriggeredEvents() -> void:
	if (_campaign == null or _eventState == null or _currentTurnContext == null):
		return

	for eventId in _currentTurnContext.triggeredEvents:
		# =================================================
		# Offense 중 발생한 이벤트
		#
		# 플레이어가 영지를 떠나 있으므로
		# 즉시 표시하지 않고 Pending으로 저장.
		# =================================================
		if (_campaign.currentPhase == CampaignState.Phase.OFFENSE):
			_eventState.AddPendingEvent(eventId)

			continue

		# =================================================
		# Tycoon 중 발생한 이벤트
		# =================================================
		if (_campaign.currentPhase != CampaignState.Phase.TYCOON):
			continue

		# =================================================
		# 이미 다른 이벤트가 처리 중이면
		# 동시에 UI를 띄우지 않고 Pending 처리.
		# =================================================
		if _eventState.HasActiveEvent():
			_eventState.AddPendingEvent(eventId)

			continue

		# =================================================
		# 현재 처리 중인 이벤트가 없다면
		# Active로 전환하고 즉시 이벤트 표시 요청.
		# =================================================
		_RequestEvent(eventId)


func _RequestEvent(eventId: StringName) -> bool:
	if (_eventState == null or eventId == &""):
		return false

	# =====================================================
	# 먼저 EventData가 실제로 존재하는지 확인.
	#
	# 잘못된 ID를 Active 상태로 만들어버리지 않도록
	# State 변경 전에 Catalog를 검사.
	# =====================================================
	var eventData := _eventSystem.GetEventData(eventId)

	if eventData == null:
		push_warning("TycoonController: EventData를 찾을 수 없습니다: %s" % eventId)

		return false

	# =====================================================
	# EventState에서 Active 전환.
	# =====================================================
	var activated := _eventState.ActivateEvent(eventId)

	if not activated:
		return false

	# =====================================================
	# UI / 외부 흐름에 이벤트 표시 요청.
	# =====================================================
	EventRequested.emit(eventData)

	return true


func ResolveActiveEvent(choiceId: StringName) -> bool:
	if (_campaign == null or _settlement == null or _story == null or _eventState == null):
		return false

	# =====================================================
	# 이벤트 선택은 Tycoon Phase에서만 처리
	# =====================================================
	if (_campaign.currentPhase != CampaignState.Phase.TYCOON):
		return false

	# =====================================================
	# 현재 처리 중인 이벤트가 없는 경우
	# =====================================================
	if not _eventState.HasActiveEvent():
		push_warning("TycoonController: 현재 처리 중인 이벤트가 없습니다.")

		return false

	# =====================================================
	# 현재 EventData 조회
	# =====================================================
	var activeEventId := _eventState.GetActiveEventId()

	var eventData := _eventSystem.GetEventData(activeEventId)

	if eventData == null:
		push_warning("TycoonController: 현재 EventData를 찾을 수 없습니다: %s" % activeEventId)

		return false

	# =====================================================
	# 선택지 결과 적용
	# =====================================================
	var choiceData := (
		_eventResolutionSystem.ApplyChoice(_campaign, _settlement, _story, eventData, choiceId)
	)

	# =====================================================
	# 잘못된 ChoiceId 등으로 결과 적용에 실패한 경우
	#
	# Active Event는 그대로 유지.
	# 플레이어가 다시 선택할 수 있음.
	# =====================================================
	if choiceData == null:
		return false

	# =====================================================
	# 이벤트 처리 완료
	# =====================================================
	_eventState.CompleteActiveEvent()

	# =====================================================
	# 이벤트 결과로 State가 변경되었으므로
	# 현재 DerivedStats도 갱신.
	# =====================================================
	_RefreshStats()

	# =====================================================
	# UI 갱신
	# =====================================================
	SettlementChanged.emit()

	# =====================================================
	# 이벤트 결과 전달
	#
	# choiceData.resultText 등을
	# UI에서 사용할 수 있음.
	# =====================================================
	EventResolved.emit(eventData, choiceData)

	return true

# =========================================================
# 저장 / 로드된 Active Event 재표시
#
# EventState에 Active Event가 이미 존재하는 경우
# 새로 Activate하지 않고 UI 요청만 다시 보냄.
#
# Save → Load 후 Tycoon Scene이 준비된 시점에
# 호출하기 위한 함수.
# =========================================================


func RequestActiveEvent() -> bool:
	if (_campaign == null or _eventState == null):
		return false

	if (_campaign.currentPhase != CampaignState.Phase.TYCOON):
		return false

	if not _eventState.HasActiveEvent():
		return false

	var eventId := _eventState.GetActiveEventId()

	var eventData := _eventSystem.GetEventData(eventId)

	if eventData == null:
		push_warning("TycoonController: Active EventData를 찾을 수 없습니다: %s" % eventId)

		return false

	EventRequested.emit(eventData)

	return true


func HasPendingEvents() -> bool:
	if _eventState == null:
		return false

	return _eventState.HasPendingEvents()


func RequestNextPendingEvent() -> bool:
	if (_campaign == null or _eventState == null):
		return false

	# =====================================================
	# Tycoon으로 복귀한 상태에서만
	# 대기 이벤트를 표시할 수 있음.
	# =====================================================
	if (_campaign.currentPhase != CampaignState.Phase.TYCOON):
		return false

	# =====================================================
	# 이미 이벤트 하나를 처리 중이라면
	# 다음 Pending Event를 열지 않음.
	# =====================================================
	if _eventState.HasActiveEvent():
		return false

	# =====================================================
	# Pending Event를 하나씩 Active로 전환.
	#
	# 데이터가 삭제되어 Catalog에 존재하지 않는 ID라면
	# 해당 Active를 비우고 다음 Pending을 확인.
	# =====================================================
	while _eventState.HasPendingEvents():
		var eventId: StringName = _eventState.ActivateNextPendingEvent()

		if eventId == &"":
			return false

		var eventData := _eventSystem.GetEventData(eventId)

		if eventData == null:
			push_warning("TycoonController: Pending EventData를 찾을 수 없습니다: %s" % eventId)

			_eventState.CompleteActiveEvent()

			continue

		EventRequested.emit(eventData)

		return true

	return false


func GetActiveEventId() -> StringName:
	if _eventState == null:
		return &""

	return _eventState.GetActiveEventId()

# =========================================================
# 시설 건설 / 업그레이드
# =========================================================


func RequestBuild(facilityId: StringName) -> bool:
	if _settlement == null:
		return false

	var success := _facilitySystem.RequestBuild(_settlement, facilityId)

	if success:
		SettlementChanged.emit()

	return success


func RequestUpgrade(facilityId: StringName) -> bool:
	if _settlement == null:
		return false

	var success := _facilitySystem.RequestUpgrade(_settlement, facilityId)

	if success:
		SettlementChanged.emit()

	return success

# =========================================================
# 시설 상호작용
# =========================================================


func CanInteractWithFacility(facilityId: StringName) -> bool:
	if _settlement == null:
		return false

	return _facilityInteractionSystem.CanInteract(_settlement, facilityId)


func GetFacilityInteractionId(facilityId: StringName) -> StringName:
	if _settlement == null:
		return &""

	return _facilityInteractionSystem.GetInteractionId(_settlement, facilityId)

# =========================================================
# Offense
# =========================================================


func RequestOffense(regionId: StringName, turnCost: int) -> bool:
	if (_campaign == null or _settlement == null or _story == null):
		return false
	if (_eventState != null and _eventState.HasActiveEvent()):
		push_warning("TycoonController: 현재 이벤트를 먼저 처리해야 합니다.")
		return false
	# =====================================================
	# Tycoon Phase에서만 Offense 진입 가능
	# =====================================================
	if (_campaign.currentPhase != CampaignState.Phase.TYCOON):
		push_warning("TycoonController: Tycoon Phase에서만 Offense에 진입할 수 있습니다.")

		return false

	# =====================================================
	# 공격 지역 검사
	# =====================================================
	if regionId == &"":
		push_warning("TycoonController: 공격 지역이 설정되지 않았습니다.")

		return false

	# =====================================================
	# 턴 비용 검사
	# =====================================================
	if turnCost <= 0:
		push_warning("TycoonController: Offense 턴 비용은 1 이상이어야 합니다.")

		return false

	# =====================================================
	# 남은 턴 검사
	# =====================================================
	if (turnCost > _campaign.GetRemainingTurns()):
		push_warning("TycoonController: Offense에 필요한 턴이 부족합니다.")

		return false

	# =====================================================
	# 출발 시점 StartData 생성
	#
	# 턴 진행 전에 생성해야
	# startTurn이 실제 출발 턴을 나타냄.
	# =====================================================
	var startData := _offenseBridge.CreateStartData(_campaign, regionId, turnCost)

	# =====================================================
	# Offense Phase 전환
	#
	# 이후 진행되는 턴에서 발생한 게임 이벤트는
	# EventState의 Pending으로 저장됨.
	# =====================================================
	_campaign.currentPhase = (CampaignState.Phase.OFFENSE)

	# =====================================================
	# Offense 동안 영지 시간 진행
	#
	# 농지 생산
	# 식량 소비
	# 안정도
	# 인구 변화
	# 건설 / 업그레이드
	# 게임 이벤트
	#
	# 모두 정상적으로 진행.
	# =====================================================
	_AdvanceOffenseTurns(turnCost)

	# =====================================================
	# 실제 Offense 시작 요청
	# =====================================================
	OffenseRequested.emit(startData)

	return true


func ApplyOffenseResult(result: OffenseResult) -> void:
	if (_campaign == null or _settlement == null or _story == null):
		return

	if (_campaign.currentPhase != CampaignState.Phase.OFFENSE):
		push_warning("TycoonController: 현재 Offense Phase가 아닙니다.")

		return

	# =====================================================
	# Offense 결과 반영
	#
	# 턴 진행은 출발할 때 이미 완료됨.
	# =====================================================
	_offenseBridge.ApplyResult(_campaign, _settlement, _story, result)

	# =====================================================
	# Tycoon 복귀
	# =====================================================
	_campaign.currentPhase = (CampaignState.Phase.TYCOON)

	_RefreshStats()

	SettlementChanged.emit()

	# =====================================================
	# Pending Event는 여기서 자동으로 열지 않음.
	#
	# 실제 Tycoon 화면이 준비된 뒤
	# RequestNextPendingEvent()를 호출해야 함.
	# =====================================================
	OffenseFinished.emit(result)


func _AdvanceOffenseTurns(turnCount: int) -> void:
	for _turnIndex in range(turnCount):
		var hasNextTurn := _turnSystem.EndTurn(_campaign)

		if not hasNextTurn:
			push_warning("TycoonController: Offense 시간 진행 중 마지막 턴을 초과했습니다.")

			break

		# =================================================
		# 플레이어에게 TurnReady는 보내지 않지만
		#
		# 생산 / 소비 / 인구 / 건설 / 이벤트 등
		# 영지 내부 시뮬레이션은 정상 진행.
		# =================================================
		_ProcessTurnStart(false)

# =========================================================
# Defense
# =========================================================


func _RequestDefense() -> void:
	if _campaign == null:
		return

	# =====================================================
	# 마지막 Tycoon 상태 기준 Stat 확정
	# =====================================================
	_RefreshStats()

	# =====================================================
	# Defense 시작 데이터 생성
	# =====================================================
	var startData := _defenseBridge.CreateStartData(_campaign, _currentStats)

	# =====================================================
	# Defense Phase 전환
	# =====================================================
	_campaign.currentPhase = (CampaignState.Phase.DEFENSE)

	# =====================================================
	# 상위 GameFlow에 Defense 시작 요청
	# =====================================================
	DefenseRequested.emit(startData)

# =========================================================
# Stat
# =========================================================


func _RefreshStats() -> void:
	_currentStats = _statSystem.Calculate(_settlement)


func GetCurrentStats() -> DerivedStats:
	return _currentStats

# =========================================================
# State 접근
# =========================================================


func GetCampaign() -> CampaignState:
	return _campaign


func GetSettlement() -> SettlementState:
	return _settlement


func GetStory() -> StoryState:
	return _story


func GetEventState() -> EventState:
	return _eventState


func GetCurrentTurnContext() -> TurnContext:
	return _currentTurnContext
