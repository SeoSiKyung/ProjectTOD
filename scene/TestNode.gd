extends Node

@export var facilityCatalog: FacilityCatalog

var _facilitySystem: FacilitySystem
var _statSystem: StatSystem
var _turnSystem: TurnSystem
var _constructionSystem: ConstructionSystem


func _ready() -> void:
	# =====================================================
	# 시스템 생성
	# =====================================================
	_facilitySystem = FacilitySystem.new()
	_statSystem = StatSystem.new()
	_turnSystem = TurnSystem.new()
	_constructionSystem = ConstructionSystem.new()

	add_child(_facilitySystem)
	add_child(_statSystem)
	add_child(_turnSystem)
	add_child(_constructionSystem)

	_facilitySystem.Setup(facilityCatalog)
	_statSystem.Setup(facilityCatalog)

	# =====================================================
	# 테스트용 영지 생성
	# =====================================================
	var settlement := SettlementState.new()

	settlement.cycle = 1
	settlement.currentTurn = 0
	settlement.cycleTurnLimit = 10

	settlement.gold = 500
	settlement.food = 100
	settlement.wood = 200

	print("")
	print("====================================")
	print("       타이쿤 시스템 테스트 시작")
	print("====================================")

	_PrintSettlement(settlement)

	# =====================================================
	# 농지 Lv1 건설
	# =====================================================
	print("")
	print("========== 농지 건설 요청 ==========")

	var buildSuccess: bool = _facilitySystem.RequestBuild(settlement, &"farm")

	print("건설 성공: ", buildSuccess)

	_PrintSettlement(settlement)
	_PrintFarm(settlement)
	_PrintStats(settlement)

	# =====================================================
	# Turn 1
	# =====================================================
	print("")
	print("========== Turn 1 ==========")

	_ProcessOneTurn(settlement)

	_PrintSettlement(settlement)
	_PrintFarm(settlement)
	_PrintStats(settlement)

	# =====================================================
	# Turn 2
	# =====================================================
	print("")
	print("========== Turn 2 ==========")

	_ProcessOneTurn(settlement)

	_PrintSettlement(settlement)
	_PrintFarm(settlement)
	_PrintStats(settlement)

	# =====================================================
	# 농지 Lv2 업그레이드
	# =====================================================
	print("")
	print("========== 농지 Lv2 업그레이드 ==========")

	var upgradeSuccess: bool = _facilitySystem.RequestUpgrade(settlement, &"farm")

	print("업그레이드 시작 성공: ", upgradeSuccess)

	_PrintSettlement(settlement)
	_PrintFarm(settlement)
	_PrintStats(settlement)

	# =====================================================
	# Lv2 업그레이드 진행
	# 이전에 Lv2 Construction Turns를 3으로 설정했다면
	# 3턴 후 완공됨
	# =====================================================
	for i in range(3):
		print("")
		print("========== Upgrade Turn ", i + 1, " ==========")

		_ProcessOneTurn(settlement)

		_PrintSettlement(settlement)
		_PrintFarm(settlement)
		_PrintStats(settlement)

	print("")
	print("====================================")
	print("       타이쿤 시스템 테스트 종료")
	print("====================================")

# =========================================================
# 턴 하나 진행
# =========================================================


func _ProcessOneTurn(settlement: SettlementState) -> void:
	var success := _turnSystem.AdvanceTurn(settlement)

	if not success:
		print("턴을 진행할 수 없습니다.")
		return

	# 새 턴 시작 시 건설 / 업그레이드 진행
	_constructionSystem.ProcessTurnStart(settlement)

# =========================================================
# 영지 상태 출력
# =========================================================


func _PrintSettlement(settlement: SettlementState) -> void:
	print("--- Settlement ---")
	print(
		"Cycle: ",
		settlement.cycle,
		" / Turn: ",
		settlement.currentTurn,
		" / ",
		settlement.cycleTurnLimit,
	)

	print("Gold: ", settlement.gold)
	print("Food: ", settlement.food)
	print("Wood: ", settlement.wood)

# =========================================================
# 농지 상태 출력
# =========================================================


func _PrintFarm(settlement: SettlementState) -> void:
	var farm := settlement.GetFacility(&"farm")

	print("--- Farm ---")

	if farm == null:
		print("농지 없음")
		return

	print("Level: ", farm.level)
	print("Status: ", farm.status)

	var task := settlement.GetConstructionTask(&"farm")

	if task != null:
		print("Target Level: ", task.targetLevel)
		print("Remaining Turns: ", task.remainingTurns)
	else:
		print("Construction Task: 없음")

# =========================================================
# 계산된 능력치 출력
# =========================================================


func _PrintStats(settlement: SettlementState) -> void:
	var stats := _statSystem.Calculate(settlement)

	print("--- Derived Stats ---")
	print("Gold Income: ", stats.goldIncome)
	print("Food Delta: ", stats.foodDelta)
	print("Wood Income: ", stats.woodIncome)
	print("Technology: ", stats.technology)
	print("Development: ", stats.development)
	print("Max Population: ", stats.maxPopulation)
