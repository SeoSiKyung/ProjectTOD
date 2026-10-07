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
var prefabPath: String
var stats: CharacterStats


func _init(
	pCharacterKey: int,
	pCharacterName: String,
	pCharacterType: CharacterType,
	pIconPath: String,
	pParchmentIconPath: String,
	pPrefabPath: String,
	pStats: CharacterStats,
) -> void:
	characterKey = pCharacterKey
	characterName = pCharacterName
	characterType = pCharacterType
	iconPath = pIconPath
	parchmentIconPath = pParchmentIconPath
	prefabPath = pPrefabPath
	stats = pStats
