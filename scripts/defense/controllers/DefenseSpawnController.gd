class_name DefenseSpawnController
extends RefCounted

signal MonstersSpawned(monsters: Array[Unit])

var _spawnPositionManager: DefenseSpawnPositionManager
var _monsterPoolManager: DefensePoolManager.MonsterPoolManager
var _monsterManager: DefenseMonsterManager
var _unitLifecycle: DefenseUnitLifecycle


func _init(
	spawnPositionManager: DefenseSpawnPositionManager,
	monsterPoolManager: DefensePoolManager.MonsterPoolManager,
	monsterManager: DefenseMonsterManager,
	unitLifecycle: DefenseUnitLifecycle,
) -> void:
	_spawnPositionManager = spawnPositionManager
	_monsterPoolManager = monsterPoolManager
	_monsterManager = monsterManager
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

	var spawnedMonsters: Array[Unit] = []
	var nextCandidateIndex: int = 0

	for i: int in range(count):
		var monster: Unit = _monsterPoolManager.SpawnMonster(
			characterData,
			spawnPoint.global_position,
		)
		if monster == null:
			push_error(
				"DefenseSpawnController: Monster 생성에 실패했습니다. characterKey: " + str(characterData.characterKey)
			)
			break

		var halfSize: int = monster.GetHalfSize()
		var candidateIndex: int = _spawnPositionManager.FindNextCandidateIndex(
			spawnPoint.global_position,
			halfSize,
			nextCandidateIndex,
		)

		if candidateIndex < 0:
			_monsterPoolManager.Return(monster)
			push_error(
				"DefenseSpawnController: Monster Spawn 위치를 찾지 못했습니다. spawnPointKey: "
				+ str(spawnPointKey)
			)
			break

		nextCandidateIndex = candidateIndex + 1
		monster.global_position = _spawnPositionManager.GetSpawnPosition(
			spawnPoint.global_position,
			halfSize,
			candidateIndex,
		)

		if not _unitLifecycle.RegisterUnit(monster):
			_monsterPoolManager.Return(monster)
			continue

		if not _monsterManager.AddMonster(monster, characterData):
			_unitLifecycle.ReturnToPool(monster, _monsterPoolManager)
			continue

		spawnedMonsters.append(monster)

	if not spawnedMonsters.is_empty():
		MonstersSpawned.emit(spawnedMonsters)
