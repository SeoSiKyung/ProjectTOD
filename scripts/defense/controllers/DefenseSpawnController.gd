class_name DefenseSpawnController
extends RefCounted

signal EnemiesSpawned(enemies: Array[Unit])

var _spawnPositionManager: DefenseSpawnPositionManager
var _enemyPoolManager: DefensePoolManager.EnemyPoolManager
var _enemyManager: DefenseEnemyManager
var _unitLifecycle: DefenseUnitLifecycle


func _init(
	spawnPositionManager: DefenseSpawnPositionManager,
	enemyPoolManager: DefensePoolManager.EnemyPoolManager,
	enemyManager: DefenseEnemyManager,
	unitLifecycle: DefenseUnitLifecycle,
) -> void:
	_spawnPositionManager = spawnPositionManager
	_enemyPoolManager = enemyPoolManager
	_enemyManager = enemyManager
	_unitLifecycle = unitLifecycle


func SpawnBatch(spawnPointKey: int, characterData: CharacterData, count: int) -> void:
	if count <= 0:
		return

	var spawnPoint: Marker2D = _spawnPositionManager.GetSpawnPoint(spawnPointKey)
	if spawnPoint == null:
		push_error("DefenseSpawnController: SpawnPoint를 찾을 수 없습니다. key: " + str(spawnPointKey))
		return

	if characterData == null:
		return

	var spawnedEnemies: Array[Unit] = []
	var nextCandidateIndex: int = 0

	for i: int in range(count):
		var enemy: Enemy = _enemyPoolManager.SpawnEnemy(characterData, spawnPoint.global_position)
		if enemy == null:
			push_error(
				"DefenseSpawnController: Enemy 생성에 실패했습니다. characterKey: "
				+ str(characterData.characterKey)
			)
			break

		var halfSize: int = enemy.GetHalfSize()
		var candidateIndex: int = _spawnPositionManager.FindNextCandidateIndex(
			spawnPoint.global_position,
			halfSize,
			nextCandidateIndex,
		)

		if candidateIndex < 0:
			_enemyPoolManager.Return(enemy)
			push_error(
				"DefenseSpawnController: Enemy Spawn 위치를 찾지 못했습니다. spawnPointKey: "
				+ str(spawnPointKey)
			)
			break

		nextCandidateIndex = candidateIndex + 1
		enemy.global_position = _spawnPositionManager.GetSpawnPosition(
			spawnPoint.global_position,
			halfSize,
			candidateIndex,
		)

		if not _unitLifecycle.RegisterUnit(enemy):
			_enemyPoolManager.Return(enemy)
			continue

		if not _enemyManager.AddEnemy(enemy, characterData):
			_unitLifecycle.ReturnToPool(enemy, _enemyPoolManager)
			continue

		spawnedEnemies.append(enemy)

	if not spawnedEnemies.is_empty():
		EnemiesSpawned.emit(spawnedEnemies)
