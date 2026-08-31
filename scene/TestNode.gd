extends Node

const FACILITY_CATALOG: FacilityCatalog = preload("res://data/facility/facility_catalog.tres")

var _tycoonController: TycoonController
var _gameFlowController: GameFlowController

var _campaignData: CampaignData

var _defenseStartData: DefenseStartData

var _nextCycleRequestCount: int = 0
var _campaignCompletedCount: int = 0


func _ready() -> void:
	print("")
	print("====================================")
	print("       Campaign Cycle 테스트")
	print("====================================")

	GameState.StartNewGame()

	# =====================================================
	# 테스트 CampaignData 생성
	#
	# Cycle 1 = 3턴
	# Cycle 2 = 5턴
	# =====================================================
	_CreateCampaignData()

	# =====================================================
	# Controller 생성
	# =====================================================
	_tycoonController = TycoonController.new()
	_gameFlowController = GameFlowController.new()

	add_child(_tycoonController)

	add_child(_gameFlowController)

	_tycoonController.Setup(
		GameState.campaign,
		GameState.settlement,
		GameState.story,
		FACILITY_CATALOG,
	)

	_gameFlowController.Setup(GameState.campaign, _tycoonController, _campaignData)

	# =====================================================
	# Signal
	# =====================================================
	_gameFlowController.DefenseSceneRequested.connect(_OnDefenseSceneRequested)

	_gameFlowController.NextCycleRequested.connect(_OnNextCycleRequested)

	_gameFlowController.CampaignCompleted.connect(_OnCampaignCompleted)

	# =====================================================
	# Cycle 1 시작
	#
	# 직접 StartCycle(3)을 호출하지 않음.
	# CampaignData에서 읽어야 함.
	# =====================================================
	print("")
	print("========== Cycle 1 시작 ==========")

	var started := (_gameFlowController.StartCurrentCycle())

	print("Cycle Started: ", started)

	_PrintCampaign()

	# =====================================================
	# Cycle 1
	# Turn 1 → 2
	# =====================================================
	print("")
	print("========== Turn 1 종료 ==========")

	_tycoonController.EndTurn()

	_PrintCampaign()

	# =====================================================
	# Turn 2 → 3
	# =====================================================
	print("")
	print("========== Turn 2 종료 ==========")

	_tycoonController.EndTurn()

	_PrintCampaign()

	# =====================================================
	# 마지막 Turn 종료
	# → Defense
	# =====================================================
	print("")
	print("========== Cycle 1 Defense ==========")

	_tycoonController.EndTurn()

	_PrintCampaign()

	# =====================================================
	# Defense 승리 결과
	# =====================================================
	print("")
	print("========== Defense 승리 ==========")

	var defenseResult := DefenseResult.new()

	defenseResult.victory = true
	defenseResult.commandPostDestroyed = false

	var resultAccepted := (_gameFlowController.SubmitDefenseResult(defenseResult))

	print("Defense Result Accepted: ", resultAccepted)

	# =====================================================
	# 여기서 자동으로:
	#
	# Cycle 2
	# Turn 1/5
	#
	# 가 되어야 함.
	# =====================================================
	_PrintCampaign()

	# =====================================================
	# 결과 검증
	# =====================================================
	print("")
	print("========== 결과 검증 ==========")

	print("Cycle Is 2: ", GameState.campaign.cycle == 2)

	print("Turn Is 1: ", GameState.campaign.currentTurn == 1)

	print("Turn Limit Is 5: ", GameState.campaign.cycleTurnLimit == 5)

	print("Phase Is Tycoon: ", GameState.campaign.currentPhase == CampaignState.Phase.TYCOON)

	print("Next Cycle Requested Once: ", _nextCycleRequestCount == 1)

	print("Campaign Not Completed: ", _campaignCompletedCount == 0)

	print("")
	print("====================================")
	print("          테스트 종료")
	print("====================================")

# =========================================================
# 테스트 CampaignData
# =========================================================


func _CreateCampaignData() -> void:
	_campaignData = CampaignData.new()

	var cycle1Data := CycleData.new()

	cycle1Data.cycle = 1
	cycle1Data.turnLimit = 3

	var cycle2Data := CycleData.new()

	cycle2Data.cycle = 2
	cycle2Data.turnLimit = 5

	_campaignData.cycles.append(cycle1Data)

	_campaignData.cycles.append(cycle2Data)

# =========================================================
# Signal
# =========================================================


func _OnDefenseSceneRequested(startData: DefenseStartData) -> void:
	print("")
	print("[GameFlow] DefenseSceneRequested")

	_defenseStartData = startData


func _OnNextCycleRequested(cycle: int) -> void:
	print("")
	print("[GameFlow] NextCycleRequested: ", cycle)

	_nextCycleRequestCount += 1


func _OnCampaignCompleted() -> void:
	print("")
	print("[GameFlow] CampaignCompleted")

	_campaignCompletedCount += 1

# =========================================================
# 출력
# =========================================================


func _PrintCampaign() -> void:
	print("Cycle: ", GameState.campaign.cycle)

	print("Turn: ", GameState.campaign.currentTurn, "/", GameState.campaign.cycleTurnLimit)

	print("Phase: ", GameState.campaign.currentPhase)
