class_name DefenseManager
extends RefCounted

signal DefenseFinished(result: DefenseResult)

enum DefensePhase {
	DEPLOYMENT,
	BATTLE,
	FINISHED,
}

var _startData: DefenseStartData

var _deploymentManager: DefenseDeploymentManager
var _unitGroupManager: DefenseUnitGroupManager
var _spawnManager: DefenseSpawnManager
var _timeManager: DefenseTimeManager

var _monsterPoolManager: DefenseMonsterPoolManager
# var _unitPoolManager: DefenseUnitPoolManager
# var _trapPoolManager: DefenseTrapPoolManager

var _phase: DefensePhase = DefensePhase.DEPLOYMENT
var _result: DefenseResult


func _init(startData: DefenseStartData, pools: Node) -> void:
	_startData = startData

	_deploymentManager = DefenseDeploymentManager.new()
	_unitGroupManager = DefenseUnitGroupManager.new()
	_spawnManager = DefenseSpawnManager.new()
	_timeManager = DefenseTimeManager.new()

	var monsterPool: Node2D = pools.get_node("MonsterPool")
	_monsterPoolManager = DefenseMonsterPoolManager.new(monsterPool)
	# var unitPool: Node2D = pools.get_node("UnitPool")
	# _unitPoolManager = DefenseUnitPoolManager.new(unitPool)
	# var trapPool: Node2D = pools.get_node("TrapPool")
	# _trapPoolManager = DefenseTrapPoolManager.new(trapPool)
	_phase = DefensePhase.DEPLOYMENT

	_result = null


func GetPhase() -> DefensePhase:
	return _phase


func GetResult() -> DefenseResult:
	return _result


func GetElapsedTimeMs() -> int:
	return _timeManager.GetElapsedTimeMs()


func ReturnMonster(monster: Node2D) -> bool:
	return _monsterPoolManager.Return(monster)


func GetActiveMonsterCount() -> int:
	return _monsterPoolManager.GetActiveMonsterCount()


func AddDeployment(cell: Vector2i, unitType: int, recruitRatio: int) -> bool:
	if _phase != DefensePhase.DEPLOYMENT:
		return false

	return _deploymentManager.AddDeployment(cell, unitType, recruitRatio)


func RemoveDeployment(cell: Vector2i) -> bool:
	if _phase != DefensePhase.DEPLOYMENT:
		return false

	return _deploymentManager.RemoveDeployment(cell)


# 이미 배치된 격자의 배치 정보를 수정
func UpdateDeployment(cell: Vector2i, unitType: int, recruitRatio: int) -> bool:
	if _phase != DefensePhase.DEPLOYMENT:
		return false

	return _deploymentManager.UpdateDeployment(cell, unitType, recruitRatio)


# 배치 확정
func ConfirmDeployment() -> bool:
	if _phase != DefensePhase.DEPLOYMENT:
		return false

	# _unitGroupManager.Initialize(_deploymentManager, _startData.population)
	_spawnManager.Initialize(_startData.cycle, _monsterPoolManager)
	_timeManager.Initialize()

	_phase = DefensePhase.BATTLE

	return true


func Update() -> void:
	if _phase != DefensePhase.BATTLE:
		return

	_timeManager.Update()

	var elapsedTimeMs: int = _timeManager.GetElapsedTimeMs()
	_spawnManager.Update(elapsedTimeMs)

	_CheckVictory()


func PauseBattle() -> void:
	if _phase != DefensePhase.BATTLE:
		return

	_timeManager.PauseBattle()


func ResumeBattle() -> void:
	if _phase != DefensePhase.BATTLE:
		return

	_timeManager.ResumeBattle()


func IsSpawnFinished() -> bool:
	if _phase != DefensePhase.BATTLE:
		return false

	return _spawnManager.IsSpawnFinished()


func FinishDefense(isVictory: bool) -> DefenseResult:
	if _phase != DefensePhase.BATTLE:
		return null

	_timeManager.PauseBattle()

	_result = DefenseResult.new()
	_result.isVictory = isVictory
	# _result.deadPopulation = _unitGroupManager.GetTotalDeadSoldierCount()
	_result.deadPopulation = 0

	_phase = DefensePhase.FINISHED

	DefenseFinished.emit(_result)

	return _result


func _CheckVictory() -> void:
	if not _spawnManager.IsSpawnFinished():
		return

	if _monsterPoolManager.GetActiveMonsterCount() > 0:
		return

	FinishDefense(true)
