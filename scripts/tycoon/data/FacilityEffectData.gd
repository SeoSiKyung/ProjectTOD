class_name FacilityEffectData
extends Resource

enum EffectType {
	GOLD_INCOME,
	FOOD_DELTA,
	WOOD_INCOME,
	STONE_INCOME,
	IRON_INCOME,
	MAGIC_STONE_INCOME,
	TECHNOLOGY,
	MAX_POPULATION,
	DEVELOPMENT,
	STABILITY_MINIMUM,
}

@export var type: EffectType = EffectType.GOLD_INCOME
@export var value: float = 0.0
