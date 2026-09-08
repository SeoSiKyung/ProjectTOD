class_name DefenseSpawnManager
extends RefCounted

signal MonsterSpawnRequested(characterKey: int, spawnPosition: Vector2)

# TODO: 실제 Spawn Point 시스템 연결 후 제거
const TEMP_SPAWN_POSITION: Vector2 = Vector2(640, 640)
const TEMP_SPAWN_SPACING: float = 64.0
const TEMP_SPAWN_COLUMNS: int = 5

var _spawnDataList: Array[DefenseSpawnData] = []
var _nextSpawnIndex: int = 0
var _nextSpawnPositionIndex: int = 0


func Initialize(cycle: int) -> void:
	_spawnDataList = GameDataManager.GetDefenseSpawnData(cycle)
	_spawnDataList.sort_custom(_CompareSpawnTime)

	_nextSpawnIndex = 0
	_nextSpawnPositionIndex = 0


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
	for i: int in range(spawnData.count):
		var spawnPosition: Vector2 = _GetNextSpawnPosition()

		MonsterSpawnRequested.emit(spawnData.characterKey, spawnPosition)


func _GetNextSpawnPosition() -> Vector2:
	var spawnIndex: int = _nextSpawnPositionIndex
	_nextSpawnPositionIndex += 1

	var column: int = spawnIndex % TEMP_SPAWN_COLUMNS
	var row: int = floori(float(spawnIndex) / TEMP_SPAWN_COLUMNS)
	return TEMP_SPAWN_POSITION + Vector2(column, row) * TEMP_SPAWN_SPACING
	# TODO: 실제 Spawn Point 시스템 연결
	# return _spawnPointManager.GetSpawnPosition()


func _CompareSpawnTime(a: DefenseSpawnData, b: DefenseSpawnData) -> bool:
	return a.spawnTimeMs < b.spawnTimeMs
