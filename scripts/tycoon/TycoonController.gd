class_name TycoonController
extends Node

signal TurnReady(currentTurn: int)
signal SettlementChanged()

signal OffenseRequested(startData: OffenseStartData)
signal OffenseFinished(result: OffenseResult)

signal DefenseRequested(startData: DefenseStartData)

var _campaign: CampaignState
var _settlement: SettlementState
var _story: StoryState

var _currentStats: DerivedStats
var _currentTurnContext: TurnContext

var _facilitySystem: FacilitySystem
var _constructionSystem: ConstructionSystem
var _statSystem: StatSystem
var _productionSystem: ProductionSystem
var _populationSystem: PopulationSystem
var _stabilitySystem: StabilitySystem
var _facilityInteractionSystem: FacilityInteractionSystem
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
	facilityCatalog: FacilityCatalog,
) -> void:
	_campaign = campaign
	_settlement = settlement
	_story = story

	_CreateSystems()

	_facilitySystem.Setup(facilityCatalog)

	_statSystem.Setup(facilityCatalog)

	_facilityInteractionSystem.Setup(facilityCatalog)

	_RefreshStats()


func _CreateSystems() -> void:
	_facilitySystem = FacilitySystem.new()
	_constructionSystem = ConstructionSystem.new()
	_statSystem = StatSystem.new()
	_productionSystem = ProductionSystem.new()
	_populationSystem = PopulationSystem.new()
	_stabilitySystem = StabilitySystem.new()
	_facilityInteractionSystem = FacilityInteractionSystem.new()
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

	_currentTurnContext.stats = _currentStats

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
	# 추후:
	#
	# EventSystem
	#
	# Phase가 OFFENSE라면 발생 이벤트를
	# StoryState.pendingEvents에 저장.
	# =====================================================

	# =====================================================
	# 일반 Tycoon 턴에서만 외부 알림
	#
	# Offense 중 흐르는 턴은 영지 시뮬레이션만 수행.
	# =====================================================
	if notifyPlayer:
		TurnReady.emit(_campaign.currentTurn)

		SettlementChanged.emit()

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
	if turnCost > _campaign.GetRemainingTurns():
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

	OffenseFinished.emit(result)


func _AdvanceOffenseTurns(turnCount: int) -> void:
	for _turnIndex in range(turnCount):
		var hasNextTurn := _turnSystem.EndTurn(_campaign)

		if not hasNextTurn:
			push_warning("TycoonController: Offense 시간 진행 중 마지막 턴을 초과했습니다.")
			break

		# 플레이어에게 TurnReady는 보내지 않지만
		# 영지 내부 시뮬레이션은 정상 진행.
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


func GetCurrentTurnContext() -> TurnContext:
	return _currentTurnContext
