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
var _movementSimulator: MovementSimulator
var _cp: DefenseCP

var _deploymentManager: DefenseDeploymentManager
var _unitGroupManager: DefenseUnitGroupManager
var _monsterManager: DefenseMonsterManager
var _cpManager: DefenseCPManager
var _spawnManager: DefenseSpawnManager
var _timeManager: DefenseTimeManager

var _monsterPoolManager: DefensePoolManager.MonsterPoolManager
var _unitPoolManager: DefensePoolManager.UnitPoolManager
# var _trapPoolManager: DefenseTrapPoolManager

var _deploymentUnitsByCell: Dictionary = { }

var _phase: DefensePhase = DefensePhase.DEPLOYMENT

var _nextUnitId: int = 1


func _init(
	startData: DefenseStartData,
	pools: Node,
	navigationService: NavigationService,
	movementSimulator: MovementSimulator,
	cp: DefenseCP,
) -> void:
	_startData = startData
	_navigationService = navigationService
	_movementSimulator = movementSimulator
	_cp = cp

	_deploymentManager = DefenseDeploymentManager.new()
	_unitGroupManager = DefenseUnitGroupManager.new()
	_unitGroupManager.CharacterDied.connect(_OnCharacterDied)
	_monsterManager = DefenseMonsterManager.new()
	_monsterManager.CharacterDied.connect(_OnCharacterDied)
	_cpManager = DefenseCPManager.new()
	_cpManager.CPDestroyed.connect(_OnCPDestroyed)
	_spawnManager = DefenseSpawnManager.new()
	_spawnManager.MonsterSpawnRequested.connect(_OnMonsterSpawnRequested)
	_timeManager = DefenseTimeManager.new()

	var monsterPool: Node2D = pools.get_node("MonsterPool")
	_monsterPoolManager = DefensePoolManager.MonsterPoolManager.new(monsterPool)

	var unitPool: Node2D = pools.get_node("UnitPool")
	_unitPoolManager = DefensePoolManager.UnitPoolManager.new(unitPool)

	# var trapPool: Node2D = pools.get_node("TrapPool")
	# _trapPoolManager = DefensePoolManager.TrapPoolManager.new(trapPool)


func GetPhase() -> DefensePhase:
	return _phase


func GetDeploymentByCell(cell: Vector2i) -> DefenseDeploymentManager.DefenseDeployment:
	return _deploymentManager.GetDeploymentByCell(cell)


func GetTotalRecruitRatio() -> int:
	return _deploymentManager.GetTotalRecruitRatio()


func GetMaxRecruitRatio() -> int:
	return DefenseDeploymentManager.MAX_RECRUIT_RATIO


func GetMaxRecruitRatioForCell(cell: Vector2i) -> int:
	return _deploymentManager.GetMaxRecruitRatioForCell(cell)


func GetTotalRecruitedPopulation() -> int:
	return _deploymentManager.CalculateTotalRecruitedPopulation(_startData.population)


func GetElapsedTimeMs() -> int:
	return _timeManager.GetElapsedTimeMs()


func GetCPPosition() -> Vector2:
	return _cpManager.GetPosition()


func GetCPMaxHp() -> int:
	var status: DefenseCPStatus = _cpManager.GetStatus()
	if status == null:
		return 0

	return status.maxHp


func GetCPCurrentHp() -> int:
	var status: DefenseCPStatus = _cpManager.GetStatus()
	if status == null:
		return 0

	return status.currentHp


func GetCPMaxMp() -> int:
	var status: DefenseCPStatus = _cpManager.GetStatus()
	if status == null:
		return 0

	return status.maxMp


func GetCPCurrentMp() -> int:
	var status: DefenseCPStatus = _cpManager.GetStatus()
	if status == null:
		return 0

	return status.currentMp


func GetRecruitedPopulation() -> int:
	return _unitGroupManager.GetRecruitedPopulation()


func GetSurvivingPopulation() -> int:
	return _unitGroupManager.GetSurvivingPopulation()


func GetDeadPopulation() -> int:
	return _unitGroupManager.GetDeadPopulation()


func AddDeployment(cell: Vector2i, characterKey: int, recruitRatio: int, position: Vector2) -> bool:
	if _phase != DefensePhase.DEPLOYMENT:
		return false

	if not _CanRecruitPopulation(recruitRatio):
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
		_deploymentManager.GetDeploymentByCell(cell)
	)
	if deployment == null:
		return false

	var unit: Unit = _deploymentUnitsByCell.get(cell)
	if unit == null:
		push_error("DefenseManager: 배치 데이터에 대응하는 Unit이 없습니다. cell: " + str(cell))
		return false

	if not _ReturnToPool(unit, _unitPoolManager):
		push_error("DefenseManager: 배치 Unit 반환에 실패했습니다. cell: " + str(cell))
		return false

	_deploymentManager.RemoveDeployment(cell)
	_deploymentUnitsByCell.erase(cell)

	return true


# 이미 배치된 격자의 배치 정보를 수정
func UpdateDeployment(cell: Vector2i, characterKey: int, recruitRatio: int) -> bool:
	if _phase != DefensePhase.DEPLOYMENT:
		return false

	if not _CanRecruitPopulation(recruitRatio):
		return false

	var deployment := _deploymentManager.GetDeploymentByCell(cell)
	if deployment == null:
		return false

	if deployment.characterKey == characterKey:
		return _deploymentManager.UpdateDeployment(cell, characterKey, recruitRatio)

	return _ReplaceDeploymentUnit(cell, deployment, characterKey, recruitRatio)


# 배치 확정
func ConfirmDeployment() -> bool:
	if _phase != DefensePhase.DEPLOYMENT:
		return false

	if _deploymentManager.GetTotalRecruitRatio() <= 0:
		push_error("DefenseManager: 배치된 병력이 없습니다.")
		return false

	if not _InitializeUnitGroups():
		return false

	var cells: Array[Vector2i] = _deploymentManager.GetDeploymentCells()
	if not _ValidateDeploymentUnits(cells):
		_RollbackDeploymentConfirmation()
		return false

	if not _cpManager.Initialize(_cp, _startData.cpMaxHp):
		push_error("DefenseManager: 지휘소 초기화에 실패했습니다.")
		_RollbackDeploymentConfirmation()
		return false

	if not _BindDeploymentUnits(cells):
		_RollbackDeploymentConfirmation()
		return false

	_StartBattle()
	return true


func Update() -> void:
	if _phase != DefensePhase.BATTLE:
		return

	_timeManager.Update()

	var elapsedTimeMs: int = _timeManager.GetElapsedTimeMs()
	_spawnManager.Update(elapsedTimeMs)

	_CheckVictory()


func Attack(attacker: Unit, target: Unit) -> bool:
	if _phase != DefensePhase.BATTLE:
		return false

	var attackerStatus: DefenseCharacterStatus = _GetCharacterStatus(attacker)
	var targetStatus: DefenseCharacterStatus = _GetCharacterStatus(target)
	if attackerStatus == null or targetStatus == null:
		return false

	if attackerStatus.IsDead() or targetStatus.IsDead():
		return false

	if attackerStatus.characterType == targetStatus.characterType:
		return false

	var targetManager: DefenseCharacterManager = _GetCharacterManager(targetStatus.characterType)
	if targetManager == null:
		return false

	var damage: int = attackerStatus.CalculateDamage(targetStatus)
	return targetManager.TakeDamage(target, damage)


func CalculateRecruitedPopulation(recruitRatio: int) -> int:
	return Math.ApplyRatio(_startData.population, recruitRatio)


func PauseBattle() -> void:
	if _phase != DefensePhase.BATTLE:
		return

	_timeManager.Pause()


func ResumeBattle() -> void:
	if _phase != DefensePhase.BATTLE:
		return

	_timeManager.Resume()


func FinishDefense(isVictory: bool, cpDestroyed: bool = false) -> DefenseResult:
	if _phase != DefensePhase.BATTLE:
		return null

	_timeManager.Pause()

	var result: DefenseResult = _CreateResult(isVictory, cpDestroyed)

	_phase = DefensePhase.FINISHED

	_CleanupBattle()

	DefenseFinished.emit(result)

	return result


func _OnCharacterDied(character: Unit, status: DefenseCharacterStatus) -> void:
	if _phase != DefensePhase.BATTLE:
		return

	var characterManager: DefenseCharacterManager = _GetCharacterManager(status.characterType)
	if characterManager == null:
		return

	var poolManager: DefensePoolManager = _GetPoolManager(status.characterType)
	if poolManager == null:
		return

	if not _ReturnToPool(character, poolManager):
		push_error("DefenseManager: Character 반환에 실패했습니다. unitId: " + str(character.unitId))
		return

	if not characterManager.UnbindCharacter(character):
		push_error(
			"DefenseManager: Character Status 연결 해제에 실패했습니다. unitId: " + str(character.unitId)
		)
		return

	if (
		status.characterType == CharacterData.CharacterType.UNIT
		and not _unitGroupManager.HasAliveUnitGroup()
	):
		FinishDefense(false)


func _OnCPDestroyed() -> void:
	if _phase != DefensePhase.BATTLE:
		return

	FinishDefense(false, true)


func _OnMonsterSpawnRequested(characterKey: int, spawnPosition: Vector2) -> void:
	if _phase != DefensePhase.BATTLE:
		return

	var monster: Unit = _monsterPoolManager.SpawnMonster(characterKey, spawnPosition)
	if monster == null:
		return

	if not _RegisterUnit(monster):
		_monsterPoolManager.Return(monster)
		return

	if not _monsterManager.AddMonster(monster, characterKey):
		if not _ReturnToPool(monster, _monsterPoolManager):
			push_error("DefenseManager: Monster 등록 실패 후 반환에 실패했습니다. unitId: " + str(monster.unitId))


func _ReplaceDeploymentUnit(
	cell: Vector2i,
	deployment: DefenseDeploymentManager.DefenseDeployment,
	characterKey: int,
	recruitRatio: int,
) -> bool:
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

	if not _ReturnToPool(unit, _unitPoolManager):
		if not _ReturnToPool(newUnit, _unitPoolManager):
			push_error("DefenseManager: 새 배치 Unit 롤백 반환에 실패했습니다. cell: " + str(cell))

		_deploymentManager.UpdateDeployment(cell, previousCharacterKey, previousRecruitRatio)

		push_error("DefenseManager: 기존 배치 Unit 반환에 실패했습니다. cell: " + str(cell))
		return false

	_deploymentUnitsByCell[cell] = newUnit
	return true


func _InitializeUnitGroups() -> bool:
	if not _unitGroupManager.Initialize(_deploymentManager, _startData.population):
		push_error("DefenseManager: UnitGroupStatus 초기화에 실패했습니다.")
		return false

	if not _unitGroupManager.HasAliveUnitGroup():
		push_error("DefenseManager: 배치된 병력이 없습니다.")
		_unitGroupManager.Clear()
		return false

	return true


func _ValidateDeploymentUnits(cells: Array[Vector2i]) -> bool:
	for cell: Vector2i in cells:
		var unit: Unit = _deploymentUnitsByCell.get(cell)
		if unit == null or _unitGroupManager.GetUnitGroupStatusByCell(cell) == null:
			push_error("DefenseManager: 배치 데이터와 UnitGroupStatus가 일치하지 않습니다. cell: " + str(cell))
			return false

	return true


func _BindDeploymentUnits(cells: Array[Vector2i]) -> bool:
	for cell: Vector2i in cells:
		var unit: Unit = _deploymentUnitsByCell[cell]
		if not _unitGroupManager.BindUnit(cell, unit):
			push_error("DefenseManager: UnitGroupStatus 연결에 실패했습니다. cell: " + str(cell))
			return false

	return true


func _RollbackDeploymentConfirmation() -> void:
	_unitGroupManager.Clear()
	_cpManager.Clear()


func _StartBattle() -> void:
	_deploymentUnitsByCell.clear()

	_spawnManager.Initialize(_startData.cycle)
	_timeManager.Initialize()

	_phase = DefensePhase.BATTLE


func _CanRecruitPopulation(recruitRatio: int) -> bool:
	return CalculateRecruitedPopulation(recruitRatio) > 0


func _SpawnDeploymentUnit(characterKey: int, position: Vector2) -> Unit:
	var unit: Unit = _unitPoolManager.SpawnUnit(characterKey, position)
	if unit == null:
		return null

	if not _navigationService.CanPlaceStatic(position, unit.GetHalfSize()):
		_unitPoolManager.Return(unit)
		return null

	if not _RegisterUnit(unit):
		_unitPoolManager.Return(unit)
		return null

	return unit


func _ReturnToPool(character: Unit, poolManager: DefensePoolManager) -> bool:
	if not poolManager.Return(character):
		return false

	_UnregisterUnit(character)
	return true


func _RegisterUnit(unit: Unit) -> bool:
	if unit == null:
		return false

	var unitId: int = _GetNextUnitId()
	unit.unitId = unitId

	_movementSimulator.RegisterUnit(unit)

	if _movementSimulator.GetUnit(unitId) != unit:
		push_error("DefenseManager: MovementSimulator Unit 등록에 실패했습니다. unitId: " + str(unitId))
		return false

	return true


func _UnregisterUnit(unit: Unit) -> void:
	if unit == null:
		return

	if unit.movement != null:
		unit.movement.Stop()

	_movementSimulator.UnregisterUnit(unit)


func _GetNextUnitId() -> int:
	while _movementSimulator.GetUnit(_nextUnitId) != null:
		_nextUnitId += 1

	var unitId: int = _nextUnitId
	_nextUnitId += 1

	return unitId


func _GetCharacterStatus(character: Unit) -> DefenseCharacterStatus:
	var status: DefenseCharacterStatus = _unitGroupManager.GetStatusByCharacter(character)
	if status != null:
		return status

	return _monsterManager.GetStatusByCharacter(character)


func _GetCharacterManager(characterType: CharacterData.CharacterType) -> DefenseCharacterManager:
	match characterType:
		CharacterData.CharacterType.UNIT:
			return _unitGroupManager

		CharacterData.CharacterType.MONSTER:
			return _monsterManager

	return null


func _GetPoolManager(characterType: CharacterData.CharacterType) -> DefensePoolManager:
	match characterType:
		CharacterData.CharacterType.UNIT:
			return _unitPoolManager

		CharacterData.CharacterType.MONSTER:
			return _monsterPoolManager

	return null


func _CheckVictory() -> void:
	if not _spawnManager.IsSpawnFinished():
		return

	if _monsterManager.GetActiveCount() > 0:
		return

	FinishDefense(true)


func _CreateResult(isVictory: bool, cpDestroyed: bool) -> DefenseResult:
	var result: DefenseResult = DefenseResult.new()
	result.isVictory = isVictory
	result.cpDestroyed = cpDestroyed
	result.elapsedTimeMs = _timeManager.GetElapsedTimeMs()

	result.recruitedPopulation = _unitGroupManager.GetRecruitedPopulation()
	result.survivingPopulation = _unitGroupManager.GetSurvivingPopulation()
	result.deadPopulation = _unitGroupManager.GetDeadPopulation()

	return result


func _CleanupBattle() -> void:
	_CleanupCharacters(_unitGroupManager, _unitPoolManager)
	_CleanupCharacters(_monsterManager, _monsterPoolManager)

	_unitGroupManager.Clear()
	_monsterManager.Clear()
	_cpManager.Clear()


func _CleanupCharacters(
	characterManager: DefenseCharacterManager,
	poolManager: DefensePoolManager,
) -> void:
	var characters: Array[Unit] = characterManager.GetCharacters()
	for character: Unit in characters:
		if not _ReturnToPool(character, poolManager):
			push_error(
				"DefenseManager: 전투 종료 중 Character 반환에 실패했습니다. unitId: " + str(character.unitId)
			)
			continue

		if not characterManager.UnbindCharacter(character):
			push_error(
				"DefenseManager: 전투 종료 중 Character Status 연결 해제에 실패했습니다. unitId: "
				+ str(character.unitId)
			)
