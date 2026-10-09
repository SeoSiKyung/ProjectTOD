class_name CharacterData
extends RefCounted

enum CharacterType {
	UNIT,
	MACHINE,
	TRAP,
	MONSTER,
	COMMAND_POST,
	COUNT,
}

var characterKey: int
var characterName: String
var characterType: CharacterType
var iconPath: String
var parchmentIconPath: String
var stats: CharacterStats
var targetPolicyId: String
var movementPolicyId: String


func _init(
	pCharacterKey: int,
	pCharacterName: String,
	pCharacterType: CharacterType,
	pIconPath: String,
	pParchmentIconPath: String,
	pStats: CharacterStats,
	pTargetPolicyId: String,
	pMovementPolicyId: String,
) -> void:
	characterKey = pCharacterKey
	characterName = pCharacterName
	characterType = pCharacterType
	iconPath = pIconPath
	parchmentIconPath = pParchmentIconPath
	stats = pStats
	targetPolicyId = pTargetPolicyId
	movementPolicyId = pMovementPolicyId
