class_name TycoonController
extends Node

signal TurnReady(currentTurn: int)
signal SettlementChanged()
signal DefenseRequested()

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
var _turnSystem: TurnSystem

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

	_RefreshStats()


func _CreateSystems() -> void:
	_facilitySystem = FacilitySystem.new()
	_constructionSystem = ConstructionSystem.new()
	_statSystem = StatSystem.new()
	_productionSystem = ProductionSystem.new()
	_populationSystem = PopulationSystem.new()
	_stabilitySystem = StabilitySystem.new()
	_turnSystem = TurnSystem.new()

	add_child(_facilitySystem)
	add_child(_constructionSystem)
	add_child(_statSystem)
	add_child(_productionSystem)
	add_child(_populationSystem)
	add_child(_stabilitySystem)
	add_child(_turnSystem)

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

	if not hasNextTurn:
		_campaign.currentPhase = CampaignState.Phase.DEFENSE

		DefenseRequested.emit()

		return false

	_ProcessTurnStart()

	return true


func _ProcessTurnStart() -> void:
	# =====================================================
	# 1. 이번 턴 Context 생성
	# =====================================================
	_currentTurnContext = TurnContext.new()

	# =====================================================
	# 2. 현재 시설 기준 Stat 계산
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
	# 7. 건설 / 업그레이드
	# =====================================================
	_constructionSystem.ProcessTurnStart(_settlement)

	# =====================================================
	# 8. 완공 시설 포함 Stat 재계산
	# =====================================================
	_RefreshStats()

	# =====================================================
	# 추후 EventSystem
	# =====================================================
	TurnReady.emit(_campaign.currentTurn)

	SettlementChanged.emit()
# =========================================================
# 시설
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
