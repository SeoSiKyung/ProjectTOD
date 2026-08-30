extends Node

const FACILITY_CATALOG: FacilityCatalog = preload("res://data/facility/facility_catalog.tres")

var _tycoonController: TycoonController

var _offenseStartData: OffenseStartData


func _ready() -> void:
	print("")
	print("====================================")
	print("       Offense Bridge 테스트")
	print("====================================")

	GameState.StartNewGame()

	_tycoonController = TycoonController.new()

	add_child(_tycoonController)

	_tycoonController.Setup(
		GameState.campaign,
		GameState.settlement,
		GameState.story,
		FACILITY_CATALOG,
	)

	# =====================================================
	# Signal 연결
	# =====================================================
	_tycoonController.OffenseRequested.connect(_OnOffenseRequested)

	_tycoonController.OffenseFinished.connect(_OnOffenseFinished)

	_tycoonController.TurnReady.connect(_OnTurnReady)

	# =====================================================
	# 1. Cycle 시작
	# =====================================================
	print("")
	print("========== Cycle 시작 ==========")

	var cycleStarted := _tycoonController.StartCycle(10)

	print("Cycle Started: ", cycleStarted)

	_PrintCurrentState()

	# =====================================================
	# 2. Turn 1에서 농지 건설
	# =====================================================
	print("")
	print("========== Turn 1 농지 건설 ==========")

	var buildSuccess := (_tycoonController.RequestBuild(&"farm"))

	print("Farm Build Success: ", buildSuccess)

	_PrintFarmState()

	# =====================================================
	# 3. Turn 2로 진행
	# =====================================================
	print("")
	print("========== Turn 2 ==========")

	var nextTurn := (_tycoonController.EndTurn())

	print("EndTurn Result: ", nextTurn)

	_PrintCurrentState()
	_PrintFarmState()

	# =====================================================
	# 4. Offense 요청
	#
	# Turn 2에서 3턴짜리 공격
	# → 귀환 시 Turn 5가 되어야 함
	# =====================================================
	print("")
	print("========== Offense 요청 ==========")

	var offenseRequested := (_tycoonController.RequestOffense(&"test_region", 3))

	print("RequestOffense Result: ", offenseRequested)

	print("Current Phase: ", GameState.campaign.currentPhase)

	print("Current Turn: ", GameState.campaign.currentTurn)

	# =====================================================
	# Request Signal에서 받은 StartData 확인
	# =====================================================
	if _offenseStartData == null:
		push_error("OffenseStartData를 전달받지 못했습니다.")
		return

	print("")
	print("========== StartData 확인 ==========")

	print("Region: ", _offenseStartData.regionId)

	print("Turn Cost: ", _offenseStartData.turnCost)

	print("Cycle: ", _offenseStartData.cycle)

	print("Start Turn: ", _offenseStartData.startTurn)

	# =====================================================
	# 5. 가짜 Offense 결과 생성
	# =====================================================
	print("")
	print("========== 가짜 Offense 결과 ==========")

	var goldBeforeResult: int = (GameState.settlement.gold)

	var magicStoneBeforeResult: int = (GameState.settlement.magicStone)

	var result := OffenseResult.new()

	result.victory = true

	result.goldReward = 100
	result.magicStoneReward = 5

	result.acquiredIntel.append(&"test_offense_intel")

	result.unlockedRegions.append(&"test_region_2")

	print("Victory: ", result.victory)

	print("Gold Reward: ", result.goldReward)

	print("Magic Stone Reward: ", result.magicStoneReward)

	# =====================================================
	# 6. Offense 결과 적용
	# =====================================================
	print("")
	print("========== Offense 귀환 ==========")

	_tycoonController.ApplyOffenseResult(_offenseStartData, result)

	# =====================================================
	# 7. 최종 상태
	# =====================================================
	_PrintCurrentState()
	_PrintFarmState()

	print("")
	print("========== 결과 검증 ==========")

	# =====================================================
	# Turn
	# =====================================================
	print("Turn 5 Expected: ", GameState.campaign.currentTurn == 5)

	# =====================================================
	# Phase
	# =====================================================
	print("Tycoon Phase Expected: ", GameState.campaign.currentPhase == CampaignState.Phase.TYCOON)

	# =====================================================
	# 보상
	# =====================================================
	print("Gold Reward Applied: ", GameState.settlement.gold == goldBeforeResult + 100)

	print(
		"Magic Stone Reward Applied: ",
		GameState.settlement.magicStone == magicStoneBeforeResult + 5,
	)

	# =====================================================
	# Intel
	# =====================================================
	print("Intel Added: ", GameState.story.HasIntel(&"test_offense_intel"))

	# =====================================================
	# Region
	# =====================================================
	print("Region Unlocked: ", GameState.campaign.IsRegionUnlocked(&"test_region_2"))

	# =====================================================
	# Farm
	# =====================================================
	var farm := GameState.settlement.GetFacility(&"farm")

	print("Farm Built: ", farm != null and farm.IsBuilt())

	var farmTask := (GameState.settlement.GetConstructionTask(&"farm"))

	print("Farm Construction Finished: ", farmTask == null)

	# =====================================================
	# Farm Stat
	# =====================================================
	var stats := (_tycoonController.GetCurrentStats())

	print("Current Food Delta: ", stats.foodDelta)

	print("")
	print("====================================")
	print("          테스트 종료")
	print("====================================")

# =========================================================
# Signal
# =========================================================


func _OnOffenseRequested(startData: OffenseStartData) -> void:
	print("")
	print("[Signal] OffenseRequested")

	_offenseStartData = startData


func _OnOffenseFinished(result: OffenseResult) -> void:
	print("[Signal] OffenseFinished: Victory = ", result.victory)


func _OnTurnReady(currentTurn: int) -> void:
	print("[Signal] TurnReady: ", currentTurn)

# =========================================================
# 출력
# =========================================================


func _PrintCurrentState() -> void:
	print("Cycle: ", GameState.campaign.cycle)

	print("Turn: ", GameState.campaign.currentTurn, "/", GameState.campaign.cycleTurnLimit)

	print("Phase: ", GameState.campaign.currentPhase)

	print("Gold: ", GameState.settlement.gold)

	print("Food: ", GameState.settlement.food)

	print("Wood: ", GameState.settlement.wood)

	print("Magic Stone: ", GameState.settlement.magicStone)

	print("Population: ", GameState.settlement.population)

	print("Stability: ", GameState.settlement.stability)


func _PrintFarmState() -> void:
	var farm := GameState.settlement.GetFacility(&"farm")

	if farm == null:
		print("Farm: 없음")
		return

	print("Farm Level: ", farm.level)

	print("Farm Status: ", farm.status)

	print("Farm Built: ", farm.IsBuilt())

	var task := (GameState.settlement.GetConstructionTask(&"farm"))

	if task == null:
		print("Farm Construction Task: 없음")
	else:
		print("Farm Remaining Turns: ", task.remainingTurns)
