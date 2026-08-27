class_name SettlementSaveData
extends RefCounted

# =========================================================
# 자원
# =========================================================

var gold: int = 0

var food: int = 0

var wood: int = 0

var stone: int = 0

var iron: int = 0

var magicStone: int = 0

# =========================================================
# 영지 상태
# =========================================================

var population: int = 0

var stability: int = 100

# =========================================================
# 시설
# =========================================================

var facilities: Array[FacilitySaveData] = []

var constructionTasks: Array[ConstructionTaskSaveData] = []
