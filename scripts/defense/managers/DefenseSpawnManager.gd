class_name DefenseSpawnManager
extends RefCounted

# TODO: 실제 Spawn Point 시스템 연결 후 제거
const TEMP_SPAWN_POSITION: Vector2 = Vector2(640, 640)
const TEMP_SPAWN_SPACING: float = 64.0
const TEMP_SPAWN_COLUMNS: int = 5

var _spawnDataList: Array[DefenseSpawnData] = []
var _nextSpawnIndex: int = 0

var _monsterPoolManager: DefensePoolManager.MonsterPoolManager


func Initialize(cycle: int, monsterPoolManager: DefensePoolManager.MonsterPoolManager) -> void:
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
		var spawnIndex: int = _monsterPoolManager.GetActiveCount()

		var column: int = spawnIndex % TEMP_SPAWN_COLUMNS
		var row: int = floori(float(spawnIndex) / TEMP_SPAWN_COLUMNS)

		var spawnPosition: Vector2 = (
			TEMP_SPAWN_POSITION + Vector2(column, row) * TEMP_SPAWN_SPACING
		)
		_monsterPoolManager.SpawnMonster(spawnData.characterKey, spawnPosition)
