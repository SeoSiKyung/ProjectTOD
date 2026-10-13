class_name CharacterData
extends RefCounted

enum TargetPolicyId {
	DEFAULT,
	CP_RUSH,
}

enum TriggerId {
	RANGE,
}

var characterKey: int
var characterName: String
var characterType: CharacterType.Type
var faction: Faction.Type
var iconPath: String
var parchmentIconPath: String
var stats: CharacterStats
var targetPolicyId = null
var triggerId = null


func _init(
	pCharacterKey: int,
	pCharacterName: String,
	pCharacterType: CharacterType.Type,
	pIconPath: String,
	pParchmentIconPath: String,
	pStats: CharacterStats,
	pTargetPolicyId,
	pTriggerId,
) -> void:
	characterKey = pCharacterKey
	characterName = pCharacterName
	characterType = pCharacterType
	faction = CharacterType.GetFaction(characterType)
	iconPath = pIconPath
	parchmentIconPath = pParchmentIconPath
	stats = pStats
	targetPolicyId = pTargetPolicyId
	triggerId = pTriggerId
