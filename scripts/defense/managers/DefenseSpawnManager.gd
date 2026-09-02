class_name DefenseSpawnManager
extends RefCounted

var _spawnDataList: Array[DefenseSpawnData] = []
var _nextSpawnIndex: int = 0

var _monsterPoolManager: DefenseMonsterPoolManager
# var _unitPoolManager: DefenseUnitPoolManager
# var _trapPoolManager: DefenseTrapPoolManager


func Initialize(cycle: int, monsterPoolManager: DefenseMonsterPoolManager) -> void:
	_spawnDataList.assign(GameDataManager.GetDefenseSpawnData(cycle))
	_nextSpawnIndex = 0

	_monsterPoolManager = monsterPoolManager


func Update(elapsedTimeMs: int) -> void:
	while _nextSpawnIndex < _spawnDataList.size():
		var spawnData: DefenseSpawnData = _spawnDataList[_nextSpawnIndex]
		if spawnData.spawnTimeMs > elapsedTimeMs:
			break

		_Spawn(spawnData)
		_nextSpawnIndex += 1


func IsSpawnFinished() -> bool:
	return _nextSpawnIndex >= _spawnDataList.size()


func _Spawn(spawnData: DefenseSpawnData) -> void:
	for i: int in range(spawnData.count):
		_monsterPoolManager.Spawn(spawnData.characterKey, Vector2.ZERO)
