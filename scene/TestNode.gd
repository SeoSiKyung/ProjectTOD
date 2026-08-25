extends Node

@export var facility_catalog: FacilityCatalog

var facility_system: FacilitySystem
var stat_system: StatSystem
var turn_system: TurnSystem
var construction_system: ConstructionSystem


func _ready() -> void:
	# =====================================================
	# 시스템 생성
	# =====================================================
	facility_system = FacilitySystem.new()
	stat_system = StatSystem.new()
	turn_system = TurnSystem.new()
	construction_system = ConstructionSystem.new()

	add_child(facility_system)
	add_child(stat_system)
	add_child(turn_system)
	add_child(construction_system)

	facility_system.Setup(facility_catalog)
	stat_system.Setup(facility_catalog)

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

	print_settlement(settlement)

	# =====================================================
	# 농지 Lv1 건설
	# =====================================================
	print("")
	print("========== 농지 건설 요청 ==========")

	var build_success: bool = facility_system.RequestBuild(settlement, &"farm")

	print("건설 성공: ", build_success)

	print_settlement(settlement)
	print_farm(settlement)
	print_stats(settlement)

	# =====================================================
	# Turn 1
	# =====================================================
	print("")
	print("========== Turn 1 ==========")

	process_one_turn(settlement)

	print_settlement(settlement)
	print_farm(settlement)
	print_stats(settlement)

	# =====================================================
	# Turn 2
	# =====================================================
	print("")
	print("========== Turn 2 ==========")

	process_one_turn(settlement)

	print_settlement(settlement)
	print_farm(settlement)
	print_stats(settlement)

	# =====================================================
	# 농지 Lv2 업그레이드
	# =====================================================
	print("")
	print("========== 농지 Lv2 업그레이드 ==========")

	var upgrade_success: bool = facility_system.RequestUpgrade(settlement, &"farm")

	print("업그레이드 시작 성공: ", upgrade_success)

	print_settlement(settlement)
	print_farm(settlement)
	print_stats(settlement)

	# =====================================================
	# Lv2 업그레이드 진행
	# 이전에 Lv2 Construction Turns를 3으로 설정했다면
	# 3턴 후 완공됨
	# =====================================================
	for i in range(3):
		print("")
		print("========== Upgrade Turn ", i + 1, " ==========")

		process_one_turn(settlement)

		print_settlement(settlement)
		print_farm(settlement)
		print_stats(settlement)

	print("")
	print("====================================")
	print("       타이쿤 시스템 테스트 종료")
	print("====================================")

# =========================================================
# 턴 하나 진행
# =========================================================


func process_one_turn(settlement: SettlementState) -> void:
	var success := turn_system.AdvanceTurn(settlement)

	if not success:
		print("턴을 진행할 수 없습니다.")
		return

	# 새 턴 시작 시 건설 / 업그레이드 진행
	construction_system.ProcessTurnStart(settlement)

# =========================================================
# 영지 상태 출력
# =========================================================


func print_settlement(settlement: SettlementState) -> void:
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


func print_farm(settlement: SettlementState) -> void:
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


func print_stats(settlement: SettlementState) -> void:
	var stats := stat_system.Calculate(settlement)

	print("--- Derived Stats ---")
	print("Gold Income: ", stats.goldIncome)
	print("Food Delta: ", stats.foodDelta)
	print("Wood Income: ", stats.woodIncome)
	print("Technology: ", stats.technology)
	print("Development: ", stats.development)
	print("Max Population: ", stats.maxPopulation)
