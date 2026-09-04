class_name EventResultData
extends Resource

# =========================================================
# 자원 변화
# =========================================================

@export var goldChange: int = 0
@export var foodChange: int = 0
@export var woodChange: int = 0
@export var stoneChange: int = 0
@export var ironChange: int = 0
@export var magicStoneChange: int = 0

# =========================================================
# 영지 변화
# =========================================================

@export var stabilityChange: int = 0

# =========================================================
# 스토리 변화
# =========================================================

@export var setStoryFlags: Array[StringName] = []
@export var clearStoryFlags: Array[StringName] = []

@export var intelToAdd: Array[StringName] = []

@export var regionsToUnlock: Array[StringName] = []
