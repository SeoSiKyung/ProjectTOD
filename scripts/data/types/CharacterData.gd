class_name CharacterData
extends RefCounted

enum CharacterType {
	UNIT,
	MACHINE,
	TRAP,
	MONSTER,
	COUNT,
}

var characterKey: int
var characterName: String
var characterType: CharacterType
var iconPath: String
var prefabPath: String
var stats: CharacterStats


func _init(
	pCharacterKey: int,
	pCharacterName: String,
	pCharacterType: CharacterType,
	pIconPath: String,
	pPrefabPath: String,
	pStats: CharacterStats,
) -> void:
	characterKey = pCharacterKey
	characterName = pCharacterName
	characterType = pCharacterType
	iconPath = pIconPath
	prefabPath = pPrefabPath
	stats = pStats
