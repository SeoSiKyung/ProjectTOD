class_name TurnContext
extends RefCounted

# =========================================================
# 턴 시작 시 계산된 스탯
# =========================================================

var stats: DerivedStats

# =========================================================
# 생산 결과
# =========================================================

var producedGold: int = 0
var producedFood: int = 0
var producedWood: int = 0
var producedStone: int = 0
var producedIron: int = 0
var producedMagicStone: int = 0

# =========================================================
# 식량
# =========================================================

var foodConsumption: int = 0
var foodShortage: int = 0

# =========================================================
# 안정도 / 인구
# =========================================================

var stabilityChange: int = 0
var populationChange: int = 0

# =========================================================
# 이벤트
# =========================================================

var triggeredEvents: Array[StringName] = []
