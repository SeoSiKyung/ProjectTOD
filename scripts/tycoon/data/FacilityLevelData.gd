class_name FacilityLevelData
extends Resource


@export_group("Construction")

# 해당 레벨을 건설/업그레이드하는 데 필요한 턴
@export_range(0, 100, 1)
var construction_turns: int = 1


@export_group("Cost")

@export var gold_cost: int = 0
@export var food_cost: int = 0
@export var wood_cost: int = 0
@export var stone_cost: int = 0
@export var iron_cost: int = 0
@export var magic_stone_cost: int = 0


@export_group("Effects")

@export var effects: Array[FacilityEffectData] = []
