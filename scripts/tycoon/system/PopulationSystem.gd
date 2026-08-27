class_name PopulationSystem
extends Node

const FOOD_CONSUMPTION_PER_POPULATION: int = 1

const BASE_MAX_POPULATION: int = 20

const POPULATION_GROWTH_STABILITY: int = 80
const POPULATION_DECLINE_STABILITY: int = 40
const POPULATION_SEVERE_DECLINE_STABILITY: int = 20

const BASE_POPULATION_GROWTH: int = 1
const DEVELOPMENT_PER_GROWTH_BONUS: int = 10

# =========================================================
# 식량 소비
# =========================================================


func ProcessFoodConsumption(settlement: SettlementState, context: TurnContext) -> void:
	var requiredFood: int = (settlement.population * FOOD_CONSUMPTION_PER_POPULATION)

	var availableFood: int = maxi(settlement.food, 0)

	var consumedFood: int = mini(availableFood, requiredFood)

	var foodShortage: int = maxi(requiredFood - consumedFood, 0)

	settlement.food -= consumedFood

	context.foodConsumption = consumedFood
	context.foodShortage = foodShortage

# =========================================================
# 인구 증감
# =========================================================


func ProcessPopulationChange(settlement: SettlementState, context: TurnContext) -> void:
	if context.stats == null:
		push_error("PopulationSystem: TurnContext에 DerivedStats가 없습니다.")
		return

	var previousPopulation: int = settlement.population

	var populationChange: int = _CalculatePopulationChange(settlement, context.stats)

	var maxPopulation: int = GetMaxPopulation(context.stats)

	# =====================================================
	# 인구 변화 적용
	# =====================================================
	if populationChange > 0:
		settlement.population = mini(settlement.population + populationChange, maxPopulation)
	else:
		settlement.population = maxi(settlement.population + populationChange, 0)

	# =====================================================
	# 실제 적용된 변화량
	# =====================================================
	context.populationChange = (settlement.population - previousPopulation)

# =========================================================
# 인구 변화량 계산
# =========================================================


func _CalculatePopulationChange(settlement: SettlementState, stats: DerivedStats) -> int:
	var stability: int = settlement.stability

	if stability < POPULATION_SEVERE_DECLINE_STABILITY:
		return -2

	if stability < POPULATION_DECLINE_STABILITY:
		return -1

	if stability < POPULATION_GROWTH_STABILITY:
		return 0

	var developmentBonus: int = int(stats.development / float(DEVELOPMENT_PER_GROWTH_BONUS))

	return (BASE_POPULATION_GROWTH + developmentBonus)

# =========================================================
# 인구 상한
# =========================================================


func GetMaxPopulation(stats: DerivedStats) -> int:
	return (BASE_MAX_POPULATION + stats.maxPopulation)
