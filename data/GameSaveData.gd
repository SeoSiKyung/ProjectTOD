class_name GameSaveData
extends RefCounted

# =========================================================
# Save Version
# =========================================================

var saveVersion: int = 1

# =========================================================
# Game State
# =========================================================

var campaign: CampaignSaveData

var settlement: SettlementSaveData

var story: StorySaveData
