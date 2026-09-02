class_name DefenseSpawnData
extends RefCounted

var cycle: int
var spawnTimeMs: int
var characterKey: int
var count: int


func _init(pCycle: int, pSpawnTimeMs: int, pCharacterKey: int, pCount: int):
	cycle = pCycle
	spawnTimeMs = pSpawnTimeMs
	characterKey = pCharacterKey
	count = pCount
