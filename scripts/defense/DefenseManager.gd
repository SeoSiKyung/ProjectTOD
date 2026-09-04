class_name DefenseManager
extends RefCounted

signal DefenseFinished(result: DefenseResult)

enum DefensePhase {
	DEPLOYMENT,
	BATTLE,
	FINISHED,
}

var _startData: DefenseStartData
var _navigationService: NavigationService

var _deploymentManager: DefenseDeploymentManager
var _unitGroupManager: DefenseUnitGroupManager
var _spawnManager: DefenseSpawnManager
var _timeManager: DefenseTimeManager

var _monsterPoolManager: DefensePoolManager.MonsterPoolManager
var _unitPoolManager: DefensePoolManager.UnitPoolManager
# var _trapPoolManager: DefenseTrapPoolManager

var _phase: DefensePhase = DefensePhase.DEPLOYMENT
var _result: DefenseResult


func _init(startData: DefenseStartData, pools: Node, navigationService: NavigationService) -> void:
	_startData = startData
	_navigationService = navigationService

	_deploymentManager = DefenseDeploymentManager.new()
	_unitGroupManager = DefenseUnitGroupManager.new()
	_spawnManager = DefenseSpawnManager.new()
	_timeManager = DefenseTimeManager.new()

	var monsterPool: Node2D = pools.get_node("MonsterPool")
	_monsterPoolManager = DefensePoolManager.MonsterPoolManager.new(monsterPool)

	var unitPool: Node2D = pools.get_node("UnitPool")
	_unitPoolManager = DefensePoolManager.UnitPoolManager.new(unitPool)

	# var trapPool: Node2D = pools.get_node("TrapPool")
	# _trapPoolManager = DefensePoolManager.TrapPoolManager.new(trapPool)
	_phase = DefensePhase.DEPLOYMENT
	_result = null


func GetPhase() -> DefensePhase:
	return _phase


func GetResult() -> DefenseResult:
	return _result


func GetUnitGroupCells() -> Array[Vector2i]:
	return _unitGroupManager.GetUnitGroupCells()


func GetUnitGroupState(cell: Vector2i) -> DefenseUnitGroupManager.DefenseUnitGroupState:
	return _unitGroupManager.GetUnitGroupState(cell)


func GetElapsedTimeMs() -> int:
	return _timeManager.GetElapsedTimeMs()


func ReturnMonster(monster: Node2D) -> bool:
	return _monsterPoolManager.Return(monster)


func ReturnUnit(unit: Unit) -> bool:
	return _unitPoolManager.Return(unit)


func SpawnDeploymentUnit(characterKey: int, position: Vector2) -> Unit:
	if _phase != DefensePhase.DEPLOYMENT:
		return null

	var unit: Unit = _unitPoolManager.SpawnUnit(characterKey, position)
	if unit == null:
		return null

	if not _navigationService.CanPlaceStatic(position, unit.GetHalfSize()):
		_unitPoolManager.Return(unit)
		return null

	return unit


func AddDeployment(cell: Vector2i, characterKey: int, recruitRatio: int) -> bool:
	if _phase != DefensePhase.DEPLOYMENT:
		return false

	return _deploymentManager.AddDeployment(cell, characterKey, recruitRatio)


func RemoveDeployment(cell: Vector2i) -> bool:
	if _phase != DefensePhase.DEPLOYMENT:
		return false

	return _deploymentManager.RemoveDeployment(cell)


# 이미 배치된 격자의 배치 정보를 수정
func UpdateDeployment(cell: Vector2i, characterKey: int, recruitRatio: int) -> bool:
	if _phase != DefensePhase.DEPLOYMENT:
		return false

	return _deploymentManager.UpdateDeployment(cell, characterKey, recruitRatio)


# 배치 확정
func ConfirmDeployment() -> bool:
	if _phase != DefensePhase.DEPLOYMENT:
		return false

	_unitGroupManager.Initialize(_deploymentManager, _startData.population)

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
	_result.deadPopulation = _unitGroupManager.GetTotalDeadSoldierCount()

	_phase = DefensePhase.FINISHED

	DefenseFinished.emit(_result)

	return _result


func _CheckVictory() -> void:
	if not _spawnManager.IsSpawnFinished():
		return

	if _monsterPoolManager.GetActiveCount() > 0:
		return

	FinishDefense(true)
