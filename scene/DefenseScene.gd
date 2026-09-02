extends Node2D

signal DefenseFinished(result: DefenseResult)

var _defenseManager: DefenseManager
var _startData: DefenseStartData


func Initialize(startData: DefenseStartData) -> void:
	_startData = startData


func _ready() -> void:
	var startData: DefenseStartData = DefenseStartData.new()
	startData.cycle = 1
	startData.population = 100

	_defenseManager = DefenseManager.new(startData, $Pools)

	# TODO:
	# if _startData == null:
	# 	return

	# _defenseManager = DefenseManager.new(_startData, $Pools)
	_defenseManager.DefenseFinished.connect(_OnDefenseFinished)

	_defenseManager.ConfirmDeployment()

	_TestSpawn()


func _process(_delta: float) -> void:
	_defenseManager.Update()


func _OnDefenseFinished(result: DefenseResult) -> void:
	print("Defense Finished")
	print("Victory: ", result.isVictory)
	print("Dead Population: ", result.deadPopulation)
	DefenseFinished.emit(result)


func _ReturnAllActiveMonsters() -> void:
	for monster: Node2D in $Pools/MonsterPool.get_children():
		if monster.visible:
			_defenseManager.ReturnMonster(monster)


func _TestSpawn() -> void:
	while not _defenseManager.IsSpawnFinished():
		await get_tree().process_frame

	print("Elapsed Time: ", _defenseManager.GetElapsedTimeMs())

	print("Spawn Finished: ", _defenseManager.IsSpawnFinished())

	print("Active Monster Count: ", _defenseManager.GetActiveMonsterCount())

	print("Return 전 Phase: ", _defenseManager.GetPhase())

	_ReturnAllActiveMonsters()

	print("Return 이후 Active Monster Count: ", _defenseManager.GetActiveMonsterCount())

	await get_tree().process_frame

	print("Return 이후 Phase: ", _defenseManager.GetPhase())
