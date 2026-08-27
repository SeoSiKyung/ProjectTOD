class_name CampaignSaveData
extends RefCounted

var cycle: int = 1

var currentTurn: int = 0

var cycleTurnLimit: int = 0

var currentPhase: int = CampaignState.Phase.TYCOON

var unlockedRegions: Array[String] = []
