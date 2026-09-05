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

	DEFENSE_PHYSICAL_ATTACK_BONUS,
	STABILITY_MINIMUM
}


@export var type: EffectType = EffectType.GOLD_INCOME
@export var value: float = 0.0
