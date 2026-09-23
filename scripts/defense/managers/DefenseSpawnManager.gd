class_name DefenseSpawnManager
extends RefCounted

signal MonsterSpawnBatchRequested(spawnPointKey: int, characterKey: int, count: int)

var _spawnDataList: Array[DefenseSpawnData] = []
var _nextSpawnIndex: int = 0


func Initialize(cycle: int) -> void:
	_spawnDataList = GameDataManager.GetDefenseSpawnData(cycle)
	_nextSpawnIndex = 0


func Update(elapsedTimeMs: int) -> void:
	while _nextSpawnIndex < _spawnDataList.size():
		var spawnData: DefenseSpawnData = _spawnDataList[_nextSpawnIndex]
		if spawnData.spawnTimeMs > elapsedTimeMs:
			break

		_SpawnGroup(spawnData)
		_nextSpawnIndex += 1


func IsSpawnFinished() -> bool:
	return _nextSpawnIndex >= _spawnDataList.size()


func _SpawnGroup(spawnData: DefenseSpawnData) -> void:
	MonsterSpawnBatchRequested.emit(
		spawnData.spawnPointKey,
		spawnData.characterKey,
		spawnData.count,
	)
