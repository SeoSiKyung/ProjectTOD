class_name CampaignState
extends RefCounted

enum Phase {
	TYCOON,
	OFFENSE,
	DEFENSE,
}

# =========================================================
# 게임 진행
# =========================================================

var cycle: int = 1

var currentTurn: int = 0

var cycleTurnLimit: int = 0

var currentPhase: Phase = Phase.TYCOON

# =========================================================
# 지역 진행
# =========================================================

var unlockedRegions: Array[StringName] = []

# =========================================================
# 턴
# =========================================================


func GetRemainingTurns() -> int:
	return max(cycleTurnLimit - currentTurn, 0)


func IsLastTurn() -> bool:
	return currentTurn >= cycleTurnLimit

# =========================================================
# 지역
# =========================================================


func IsRegionUnlocked(regionId: StringName) -> bool:
	return unlockedRegions.has(regionId)


func UnlockRegion(regionId: StringName) -> void:
	if not unlockedRegions.has(regionId):
		unlockedRegions.append(regionId)
