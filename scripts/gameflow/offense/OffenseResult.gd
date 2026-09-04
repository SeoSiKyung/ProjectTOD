class_name OffenseResult
extends RefCounted

var isVictory: bool = false

# =========================================================
# 획득 자원
# =========================================================

var goldReward: int = 0
var foodReward: int = 0
var woodReward: int = 0
var stoneReward: int = 0
var ironReward: int = 0
var magicStoneReward: int = 0

# =========================================================
# 진행 결과
# =========================================================

var acquiredIntel: Array[StringName] = []

var unlockedRegions: Array[StringName] = []
