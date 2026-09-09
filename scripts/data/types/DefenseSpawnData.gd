class_name DefenseSpawnData
extends RefCounted

var spawnTimeMs: int
var characterKey: int
var count: int


func _init(pSpawnTimeMs: int, pCharacterKey: int, pCount: int) -> void:
	spawnTimeMs = pSpawnTimeMs
	characterKey = pCharacterKey
	count = pCount
