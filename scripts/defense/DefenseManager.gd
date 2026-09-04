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
var _deploymentUnitsByCell: Dictionary = { }

var _unitGroupManager: DefenseUnitGroupManager
var _spawnManager: DefenseSpawnManager
var _timeManager: DefenseTimeManager

var _monsterPoolManager: DefensePoolManager.MonsterPoolManager
var _unitPoolManager: DefensePoolManager.UnitPoolManager
# var _trapPoolManager: DefenseTrapPoolManager

var _phase: DefensePhase = DefensePhase.DEPLOYMENT


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


func GetPhase() -> DefensePhase:
	return _phase


func AddDeployment(cell: Vector2i, characterKey: int, recruitRatio: int, position: Vector2) -> bool:
	if _phase != DefensePhase.DEPLOYMENT:
		return false

	if not _deploymentManager.AddDeployment(cell, characterKey, recruitRatio):
		return false

	var unit: Unit = _SpawnDeploymentUnit(characterKey, position)
	if unit == null:
		_deploymentManager.RemoveDeployment(cell)
		return false

	_deploymentUnitsByCell[cell] = unit

	return true


func RemoveDeployment(cell: Vector2i) -> bool:
	if _phase != DefensePhase.DEPLOYMENT:
		return false

	var deployment: DefenseDeploymentManager.DefenseDeployment = (
		_deploymentManager.GetDeployment(cell)
	)
	if deployment == null:
		return false

	var unit: Unit = _deploymentUnitsByCell.get(cell)
	if unit == null:
		push_error("DefenseManager: 배치 데이터에 대응하는 Unit이 없습니다. cell: " + str(cell))
		return false

	if not _unitPoolManager.Return(unit):
		push_error("DefenseManager: 배치 Unit 반환에 실패했습니다. cell: " + str(cell))
		return false

	_deploymentManager.RemoveDeployment(cell)
	_deploymentUnitsByCell.erase(cell)

	return true


# 이미 배치된 격자의 배치 정보를 수정
func UpdateDeployment(cell: Vector2i, characterKey: int, recruitRatio: int) -> bool:
	if _phase != DefensePhase.DEPLOYMENT:
		return false

	var deployment := _deploymentManager.GetDeployment(cell)
	if deployment == null:
		return false

	if deployment.characterKey == characterKey:
		return _deploymentManager.UpdateDeployment(cell, characterKey, recruitRatio)

	var unit: Unit = _deploymentUnitsByCell.get(cell)
	if unit == null:
		push_error("DefenseManager: 배치 데이터에 대응하는 Unit이 없습니다. cell: " + str(cell))
		return false

	var previousCharacterKey: int = deployment.characterKey
	var previousRecruitRatio: int = deployment.recruitRatio

	if not _deploymentManager.UpdateDeployment(cell, characterKey, recruitRatio):
		return false

	var newUnit: Unit = _SpawnDeploymentUnit(characterKey, unit.position)
	if newUnit == null:
		_deploymentManager.UpdateDeployment(cell, previousCharacterKey, previousRecruitRatio)
		return false

	if not _unitPoolManager.Return(unit):
		_unitPoolManager.Return(newUnit)

		_deploymentManager.UpdateDeployment(cell, previousCharacterKey, previousRecruitRatio)

		push_error("DefenseManager: 기존 배치 Unit 반환에 실패했습니다. cell: " + str(cell))
		return false

	_deploymentUnitsByCell[cell] = newUnit

	return true


# 배치 확정
func ConfirmDeployment() -> bool:
	if _phase != DefensePhase.DEPLOYMENT:
		return false

	_unitGroupManager.Initialize(_deploymentManager, _startData.population)

	var cells: Array[Vector2i] = _deploymentManager.GetDeploymentCells()
	for cell: Vector2i in cells:
		var unit: Unit = _deploymentUnitsByCell.get(cell)
		var unitGroupState := _unitGroupManager.GetUnitGroupState(cell)
		if unit == null or unitGroupState == null:
			push_error("DefenseManager: 배치 Unit과 UnitGroupState 연결에 실패했습니다. cell: " + str(cell))
			return false

		if not _unitPoolManager.SetUnitGroupState(unit, unitGroupState):
			push_error("DefenseManager: UnitGroupState 등록에 실패했습니다. cell: " + str(cell))
			return false

	_deploymentUnitsByCell.clear()

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


func ReturnMonster(monster: Node2D) -> bool:
	if _phase != DefensePhase.BATTLE:
		return false

	return _monsterPoolManager.Return(monster)


func ReturnUnit(unit: Unit) -> bool:
	if _phase != DefensePhase.BATTLE:
		return false

	return _unitPoolManager.Return(unit)


func PauseBattle() -> void:
	if _phase != DefensePhase.BATTLE:
		return

	_timeManager.Pause()


func ResumeBattle() -> void:
	if _phase != DefensePhase.BATTLE:
		return

	_timeManager.Resume()


func FinishDefense(isVictory: bool) -> DefenseResult:
	if _phase != DefensePhase.BATTLE:
		return null

	_timeManager.Pause()

	var result: DefenseResult = _CreateResult(isVictory)
	_phase = DefensePhase.FINISHED

	DefenseFinished.emit(result)

	return result


func _SpawnDeploymentUnit(characterKey: int, position: Vector2) -> Unit:
	var unit: Unit = _unitPoolManager.SpawnUnit(characterKey, position)
	if unit == null:
		return null

	if not _navigationService.CanPlaceStatic(position, unit.GetHalfSize()):
		_unitPoolManager.Return(unit)
		return null

	return unit


func _CheckVictory() -> void:
	if not _spawnManager.IsSpawnFinished():
		return

	if _monsterPoolManager.GetActiveCount() > 0:
		return

	FinishDefense(true)


func _CreateResult(isVictory: bool) -> DefenseResult:
	var result: DefenseResult = DefenseResult.new()
	result.isVictory = isVictory
	result.deadPopulation = _unitGroupManager.GetTotalDeadSoldierCount()

	return result
