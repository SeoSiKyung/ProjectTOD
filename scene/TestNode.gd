extends Node

const FACILITY_CATALOG: FacilityCatalog = preload("res://data/facility/facility_catalog.tres")

var _tycoonController: TycoonController


func _ready() -> void:
	print("")
	print("====================================")
	print("      Development 연동 테스트")
	print("====================================")

	_RunTest("주거시설 없음", 0)

	_RunTest("주거시설 Lv1", 1)

	_RunTest("주거시설 Lv2", 2)

	_RunTest("주거시설 Lv3", 3)


func _RunTest(title: String, residenceLevel: int) -> void:
	# =====================================================
	# 새 게임
	# =====================================================
	GameState.StartNewGame()

	# =====================================================
	# 테스트 상태
	# =====================================================
	GameState.settlement.population = 10
	GameState.settlement.stability = 100

	# 식량 부족 방지
	GameState.settlement.food = 999

	# =====================================================
	# Residence 직접 배치
	# =====================================================
	if residenceLevel > 0:
		var residence := FacilityState.new()

		residence.facilityId = &"residence"
		residence.level = residenceLevel
		residence.status = FacilityState.Status.BUILT

		GameState.settlement.facilities.append(residence)

	# =====================================================
	# Controller
	# =====================================================
	_tycoonController = TycoonController.new()

	add_child(_tycoonController)

	_tycoonController.Setup(
		GameState.campaign,
		GameState.settlement,
		GameState.story,
		FACILITY_CATALOG,
	)

	# =====================================================
	# Turn 1 정산
	# =====================================================
	_tycoonController.StartCycle(1)

	var settlement := (_tycoonController.GetSettlement())

	var stats := (_tycoonController.GetCurrentStats())

	var context := (_tycoonController.GetCurrentTurnContext())

	print("")
	print("------------------------------------")
	print(title)
	print("------------------------------------")

	print("Residence Level: ", residenceLevel)

	print("Development: ", stats.development)

	print("Max Population Bonus: ", stats.maxPopulation)

	print("Actual Max Population: ", 20 + stats.maxPopulation)

	print("Population: ", settlement.population)

	print("Population Change: ", context.populationChange)

	print("Food Consumption: ", context.foodConsumption)

	print("Food Shortage: ", context.foodShortage)

	_tycoonController.queue_free()
	_tycoonController = null
