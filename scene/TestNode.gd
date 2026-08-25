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

	facility_system.setup(facility_catalog)
	stat_system.setup(facility_catalog)


	# =====================================================
	# 테스트용 영지 생성
	# =====================================================

	var settlement := SettlementState.new()

	settlement.cycle = 1
	settlement.current_turn = 0
	settlement.cycle_turn_limit = 10

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

	var build_success: bool = facility_system.request_build(
		settlement,
		&"farm"
	)

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

	var upgrade_success: bool = facility_system.request_upgrade(
		settlement,
		&"farm"
	)

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
	var success := turn_system.advance_turn(settlement)

	if not success:
		print("턴을 진행할 수 없습니다.")
		return

	# 새 턴 시작 시 건설 / 업그레이드 진행
	construction_system.process_turn_start(settlement)


# =========================================================
# 영지 상태 출력
# =========================================================

func print_settlement(settlement: SettlementState) -> void:
	print("--- Settlement ---")
	print(
		"Cycle: ",
		settlement.cycle,
		" / Turn: ",
		settlement.current_turn,
		" / ",
		settlement.cycle_turn_limit
	)

	print("Gold: ", settlement.gold)
	print("Food: ", settlement.food)
	print("Wood: ", settlement.wood)


# =========================================================
# 농지 상태 출력
# =========================================================

func print_farm(settlement: SettlementState) -> void:
	var farm := settlement.get_facility(&"farm")

	print("--- Farm ---")

	if farm == null:
		print("농지 없음")
		return

	print("Level: ", farm.level)
	print("Status: ", farm.status)

	var task := settlement.get_construction_task(&"farm")

	if task != null:
		print("Target Level: ", task.target_level)
		print("Remaining Turns: ", task.remaining_turns)
	else:
		print("Construction Task: 없음")


# =========================================================
# 계산된 능력치 출력
# =========================================================

func print_stats(settlement: SettlementState) -> void:
	var stats := stat_system.calculate(settlement)

	print("--- Derived Stats ---")
	print("Gold Income: ", stats.gold_income)
	print("Food Delta: ", stats.food_delta)
	print("Wood Income: ", stats.wood_income)
	print("Technology: ", stats.technology)
	print("Development: ", stats.development)
	print("Max Population: ", stats.max_population)
