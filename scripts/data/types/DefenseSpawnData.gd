class_name DefenseSpawnData
extends RefCounted

var spawnTimeMs: int
var spawnPointKey: int
var characterKey: int
var count: int


func _init(pSpawnTimeMs: int, pSpawnPointKey: int, pCharacterKey: int, pCount: int) -> void:
	spawnTimeMs = pSpawnTimeMs
	spawnPointKey = pSpawnPointKey
	characterKey = pCharacterKey
	count = pCount
