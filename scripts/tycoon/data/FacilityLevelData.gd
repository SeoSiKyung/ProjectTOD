class_name FacilityLevelData
extends Resource

@export_group("Construction")

# 해당 레벨을 건설/업그레이드하는 데 필요한 턴
@export_range(0, 100, 1)
var constructionTurns: int = 1

@export_group("Cost")

@export var goldCost: int = 0
@export var foodCost: int = 0
@export var woodCost: int = 0
@export var stoneCost: int = 0
@export var ironCost: int = 0
@export var magicStoneCost: int = 0

@export_group("Effects")

@export var effects: Array[FacilityEffectData] = []
