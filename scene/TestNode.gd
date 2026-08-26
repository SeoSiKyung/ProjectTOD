extends Node

@export var facilityCatalog: FacilityCatalog

var _facilitySystem: FacilitySystem
var _statSystem: StatSystem
var _turnSystem: TurnSystem
var _constructionSystem: ConstructionSystem
var _productionSystem: ProductionSystem


func _ready() -> void:
	# =====================================================
	# 시스템 생성
	# =====================================================
	_facilitySystem = FacilitySystem.new()
	_statSystem = StatSystem.new()
	_turnSystem = TurnSystem.new()
	_constructionSystem = ConstructionSystem.new()
	_productionSystem = ProductionSystem.new()

	add_child(_facilitySystem)
	add_child(_statSystem)
	add_child(_turnSystem)
	add_child(_constructionSystem)
	add_child(_productionSystem)

	# =====================================================
	# 시스템 초기 설정
	# =====================================================
	_facilitySystem.Setup(facilityCatalog)
	_statSystem.Setup(facilityCatalog)
	_productionSystem.Setup(_statSystem)

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
	settlement.stone = 0
	settlement.iron = 0
	settlement.magicStone = 0

	settlement.population = 10
	settlement.stability = 100

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
	# 농지 건설 2 → 1
	# 아직 생산 없음
	# =====================================================
	print("")
	print("========== Turn 1 ==========")

	_ProcessOneTurn(settlement)

	_PrintSettlement(settlement)
	_PrintFarm(settlement)
	_PrintStats(settlement)

	# =====================================================
	# Turn 2
	# 생산 먼저 처리
	# 이후 농지 완공
	# 따라서 아직 농지 생산 없음
	# =====================================================
	print("")
	print("========== Turn 2 ==========")

	_ProcessOneTurn(settlement)

	_PrintSettlement(settlement)
	_PrintFarm(settlement)
	_PrintStats(settlement)

	# =====================================================
	# Turn 3
	# 완공된 농지 Lv1이 처음으로 생산
	# Food +10 예상
	# =====================================================
	print("")
	print("========== Turn 3 - 농지 생산 시작 ==========")

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
	#
	# 업그레이드가 3턴이라면:
	# Turn 4 : 3 → 2
	# Turn 5 : 2 → 1
	# Turn 6 : 1 → 0 / Lv2 완공
	#
	# 이 기간에도 기존 Lv1 효과인 Food +10 유지
	# =====================================================
	for i in range(3):
		print("")
		print("========== Upgrade Turn ", i + 1, " ==========")

		_ProcessOneTurn(settlement)

		_PrintSettlement(settlement)
		_PrintFarm(settlement)
		_PrintStats(settlement)

	# =====================================================
	# Lv2 완공 다음 턴
	#
	# 여기부터 Lv2 효과인 Food +18 적용 예상
	# =====================================================
	print("")
	print("========== Lv2 완공 후 첫 생산 ==========")

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
	var success: bool = _turnSystem.AdvanceTurn(settlement)

	if not success:
		print("턴을 진행할 수 없습니다.")
		return

	# -----------------------------------------------------
	# 1. 턴 시작 시 현재 완공된 시설 기준 생산
	# -----------------------------------------------------
	_productionSystem.ProcessTurnStart(settlement)

	# -----------------------------------------------------
	# 2. 생산 처리 이후 건설 / 업그레이드 진행
	#
	# 이렇게 해야 해당 턴에 완공된 시설은
	# 다음 턴부터 생산에 참여함.
	# -----------------------------------------------------
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
	print("Stone: ", settlement.stone)
	print("Iron: ", settlement.iron)
	print("Magic Stone: ", settlement.magicStone)

	print("Population: ", settlement.population)
	print("Stability: ", settlement.stability)

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
# 계산된 영지 수치 출력
# =========================================================


func _PrintStats(settlement: SettlementState) -> void:
	var stats := _statSystem.Calculate(settlement)

	print("--- Derived Stats ---")

	print("Gold Income: ", stats.goldIncome)
	print("Food Delta: ", stats.foodDelta)
	print("Wood Income: ", stats.woodIncome)
	print("Stone Income: ", stats.stoneIncome)
	print("Iron Income: ", stats.ironIncome)
	print("Magic Stone Income: ", stats.magicStoneIncome)

	print("Technology: ", stats.technology)
	print("Development: ", stats.development)
	print("Max Population: ", stats.maxPopulation)

	print("Defense Physical Attack Bonus: ", stats.defensePhysicalAttackBonus)

	print("Stability Minimum: ", stats.stabilityMinimum)
