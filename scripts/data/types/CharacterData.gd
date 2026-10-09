class_name CharacterData
extends RefCounted

enum CharacterType {
	ALLY,
	COMMAND_POST,
	TOWER,
	MACHINE,
	TRAP,
	ENEMY,
	COUNT,
}

enum TargetPolicyId {
	DEFAULT,
	CP_RUSH,
}

enum TriggerId {
	RANGE,
}

var characterKey: int
var characterName: String
var characterType: CharacterType
var iconPath: String
var parchmentIconPath: String
var stats: CharacterStats
var targetPolicyId = null
var triggerId = null


func _init(
	pCharacterKey: int,
	pCharacterName: String,
	pCharacterType: CharacterType,
	pIconPath: String,
	pParchmentIconPath: String,
	pStats: CharacterStats,
	pTargetPolicyId,
	pTriggerId,
) -> void:
	characterKey = pCharacterKey
	characterName = pCharacterName
	characterType = pCharacterType
	iconPath = pIconPath
	parchmentIconPath = pParchmentIconPath
	stats = pStats
	targetPolicyId = pTargetPolicyId
	triggerId = pTriggerId
