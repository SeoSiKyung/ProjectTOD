class_name DefenseSceneManager
extends SceneManager

const TARGET_ACQUISITION_INTERVAL: float = 0.1
const ATTACK_BUFFER_CAPACITY_MULTIPLIER: int = 2

signal DefenseFinished(result: DefenseResult)

enum DefensePhase {
	DEPLOYMENT,
	BATTLE,
	FINISHED,
}

@export_group("Scene")
@export var _pools: Node
@export var _cp: DefenseCP

@export_group("Navigation")
@export var navigationData: NavigationData
@export_range(8, 256, 8) var navigationLocalSearchMarginCells: int = 64
@export_range(8, 256, 8) var navigationAnchorConnectionCacheCapacity: int = 64

var _startData: DefenseStartData

@export_group("Simulation")
@export_range(0, 100000, 1)
var initialUnitCapacity: int = StageSnapshot.DEFAULT_SLOT_CAPACITY

var _navigationService: NavigationService

var _deploymentManager: DefenseDeploymentManager
var _unitGroupManager: DefenseUnitGroupManager
var _monsterManager: DefenseMonsterManager
var _cpManager: DefenseCPManager
var _spawnManager: DefenseSpawnManager
var _timeManager: DefenseTimeManager
var _targetingManager: DefenseTargetingManager
var _combatManager: DefenseCombatManager

var _monsterPoolManager: DefensePoolManager.MonsterPoolManager
var _unitPoolManager: DefensePoolManager.UnitPoolManager
# var _trapPoolManager: DefenseTrapPoolManager

var _deploymentUnitsByCell: Dictionary[Vector2i, Unit] = { }

var _nextUnitId: int = 1

var _monsterTargetAcquisitionCursor: int = 0
var _unitTargetAcquisitionCursor: int = 0

var _pendingDefeat: bool = false
var _pendingCPDestroyed: bool = false

var _phase: DefensePhase = DefensePhase.DEPLOYMENT


func _ready() -> void:
	set_process(false)
	set_physics_process(false)

	if not _InitializeNavigation():
		return

	if not _InitializeUnitRuntime(_navigationService, initialUnitCapacity):
		return

	_InitializeManagers()


func Initialize(startData: DefenseStartData) -> bool:
	if startData == null:
		push_error("DefenseSceneManager: DefenseStartData가 없습니다.")
		return false

	if _navigationService == null or not _navigationService.IsReady():
		push_error("DefenseSceneManager: NavigationService가 준비되지 않았습니다.")
		return false

	_startData = startData

	var initialAttackCapacity: int = _CalculateAttackBufferCapacity()
	if not _combatManager.Initialize(initialAttackCapacity):
		push_error("DefenseSceneManager: CombatManager 초기화에 실패했습니다.")
		return false

	return true


func _process(_delta: float) -> void:
	if _phase != DefensePhase.BATTLE:
		return

	_timeManager.Update()

	var elapsedTimeMs: int = _timeManager.GetElapsedTimeMs()
	_spawnManager.Update(elapsedTimeMs)

	_CheckVictory()


func _physics_process(fixedDelta: float) -> void:
	if _phase != DefensePhase.BATTLE:
		return

	_SimulateUnitRuntime(fixedDelta)

	_UpdateTargeting(CharacterData.CharacterType.MONSTER)
	_UpdateTargeting(CharacterData.CharacterType.UNIT)

	_monsterTargetAcquisitionCursor = _UpdateTargetAcquisition(
		CharacterData.CharacterType.MONSTER,
		_monsterTargetAcquisitionCursor,
		fixedDelta,
	)
	_unitTargetAcquisitionCursor = _UpdateTargetAcquisition(
		CharacterData.CharacterType.UNIT,
		_unitTargetAcquisitionCursor,
		fixedDelta,
	)

	_UpdateCombat()


func _InitializeNavigation() -> bool:
	if navigationData == null:
		push_error("DefenseSceneManager: NavigationData가 지정되지 않았습니다.")
		return false

	_navigationService = NavigationService.new()
	_navigationService.navigationData = navigationData
	_navigationService.localSearchMarginCells = navigationLocalSearchMarginCells
	_navigationService.anchorConnectionCacheCapacity = navigationAnchorConnectionCacheCapacity
	_navigationService.Reload()

	if not _navigationService.IsReady():
		push_error("DefenseSceneManager: NavigationService 초기화에 실패했습니다.")
		_navigationService = null
		return false

	return true


func _InitializeManagers() -> void:
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

	_targetingManager = DefenseTargetingManager.new(
		_unitManager,
		_stageSnapshot,
		_unitGroupManager,
		_monsterManager,
		_cpManager,
	)

	_combatManager = DefenseCombatManager.new(
		_unitManager,
		_unitGroupManager,
		_monsterManager,
		_cpManager,
	)

	var monsterPool: Node2D = _pools.get_node("MonsterPool")
	_monsterPoolManager = DefensePoolManager.MonsterPoolManager.new(monsterPool)

	var unitPool: Node2D = _pools.get_node("UnitPool")
	_unitPoolManager = DefensePoolManager.UnitPoolManager.new(unitPool)

	# var trapPool: Node2D = _pools.get_node("TrapPool")
	# _trapPoolManager = DefensePoolManager.TrapPoolManager.new(trapPool)


func GetPhase() -> DefensePhase:
	return _phase


func GetNavigationWorldRect() -> Rect2:
	if navigationData == null:
		return Rect2()

	return navigationData.GetWorldRect()


func CanPlaceStatic(position: Vector2, halfSize: int) -> bool:
	if _navigationService == null or not _navigationService.IsReady():
		return false

	return _navigationService.CanPlaceStatic(position, halfSize)


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
		push_error("DefenseSceneManager: 배치 데이터에 대응하는 Unit이 없습니다. cell: " + str(cell))
		return false

	if not _ReturnToPool(unit, _unitPoolManager):
		push_error("DefenseSceneManager: 배치 Unit 반환에 실패했습니다. cell: " + str(cell))
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

	var deployment: DefenseDeploymentManager.DefenseDeployment = (
		_deploymentManager.GetDeploymentByCell(cell)
	)
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
		push_error("DefenseSceneManager: 배치된 병력이 없습니다.")
		return false

	if not _InitializeUnitGroups():
		return false

	var cells: Array[Vector2i] = _deploymentManager.GetDeploymentCells()
	if not _ValidateDeploymentUnits(cells):
		_RollbackDeploymentConfirmation()
		return false

	if not _cpManager.Initialize(_cp, _startData.cpMaxHp):
		push_error("DefenseSceneManager: 지휘소 초기화에 실패했습니다.")
		_RollbackDeploymentConfirmation()
		return false

	if not _RegisterUnit(_cp):
		push_error("DefenseSceneManager: CP Runtime 등록에 실패했습니다.")
		_RollbackDeploymentConfirmation()
		return false

	if not _BindDeploymentUnits(cells):
		_RollbackDeploymentConfirmation()
		return false

	_StartBattle()
	return true


func CalculateRecruitedPopulation(recruitRatio: int) -> int:
	return Math.ApplyRatio(_startData.population, recruitRatio)


func PauseBattle() -> void:
	if _phase != DefensePhase.BATTLE:
		return

	_timeManager.Pause()

	set_process(false)
	set_physics_process(false)


func ResumeBattle() -> void:
	if _phase != DefensePhase.BATTLE:
		return

	_timeManager.Resume()

	set_process(true)
	set_physics_process(true)


func _FinishDefense(isVictory: bool, cpDestroyed: bool = false) -> DefenseResult:
	if _phase != DefensePhase.BATTLE:
		return null

	_timeManager.Pause()

	var result: DefenseResult = _CreateResult(isVictory, cpDestroyed)

	_phase = DefensePhase.FINISHED
	set_process(false)
	set_physics_process(false)

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

	if not _RemoveCharacter(character, characterManager, poolManager):
		return

	if (
		status.characterType == CharacterData.CharacterType.UNIT
		and not _unitGroupManager.HasAliveUnitGroup()
	):
		_pendingDefeat = true


func _RemoveCharacter(
	character: Unit,
	characterManager: DefenseCharacterManager,
	poolManager: DefensePoolManager,
) -> bool:
	if character == null:
		return false

	# 먼저 전투 데이터에서 제거한다. 실패하면 Pool로 보내면 안 된다.
	if not characterManager.UnbindCharacter(character):
		push_error(
			"DefenseSceneManager: Character Status 연결 해제에 실패했습니다. unitId: " + str(character.unitId)
		)
		return false

	# 그 다음 Runtime 제거 + Pool 반환.
	if not _ReturnToPool(character, poolManager):
		push_error("DefenseSceneManager: Character 반환에 실패했습니다. unitId: " + str(character.unitId))
		return false

	return true


func _OnCPDestroyed() -> void:
	if _phase != DefensePhase.BATTLE:
		return

	_pendingDefeat = true
	_pendingCPDestroyed = true


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
			push_error(
				"DefenseSceneManager: Monster 등록 실패 후 반환에 실패했습니다. unitId: " + str(monster.unitId)
			)
		return

	if not _IssueChaseTarget(monster, _cp):
		_monsterManager.UnbindCharacter(monster)

		if not _ReturnToPool(monster, _monsterPoolManager):
			push_error(
				"DefenseSceneManager: Monster 이동 명령 실패 후 반환에 실패했습니다. unitId: " + str(monster.unitId)
			)


func _ReplaceDeploymentUnit(
	cell: Vector2i,
	deployment: DefenseDeploymentManager.DefenseDeployment,
	characterKey: int,
	recruitRatio: int,
) -> bool:
	var unit: Unit = _deploymentUnitsByCell.get(cell)
	if unit == null:
		push_error("DefenseSceneManager: 배치 데이터에 대응하는 Unit이 없습니다. cell: " + str(cell))
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
			push_error("DefenseSceneManager: 새 배치 Unit 롤백 반환에 실패했습니다. cell: " + str(cell))

		_deploymentManager.UpdateDeployment(cell, previousCharacterKey, previousRecruitRatio)

		push_error("DefenseSceneManager: 기존 배치 Unit 반환에 실패했습니다. cell: " + str(cell))
		return false

	_deploymentUnitsByCell[cell] = newUnit
	return true


func _InitializeUnitGroups() -> bool:
	if not _unitGroupManager.Initialize(_deploymentManager, _startData.population):
		push_error("DefenseSceneManager: UnitGroupStatus 초기화에 실패했습니다.")
		return false

	if not _unitGroupManager.HasAliveUnitGroup():
		push_error("DefenseSceneManager: 배치된 병력이 없습니다.")
		_unitGroupManager.Clear()
		return false

	return true


func _ValidateDeploymentUnits(cells: Array[Vector2i]) -> bool:
	for cell: Vector2i in cells:
		var unit: Unit = _deploymentUnitsByCell.get(cell)
		if unit == null or _unitGroupManager.GetUnitGroupStatusByCell(cell) == null:
			push_error(
				"DefenseSceneManager: 배치 데이터와 UnitGroupStatus가 일치하지 않습니다. cell: " + str(cell)
			)
			return false

	return true


func _BindDeploymentUnits(cells: Array[Vector2i]) -> bool:
	for cell: Vector2i in cells:
		var unit: Unit = _deploymentUnitsByCell[cell]
		if not _unitGroupManager.BindUnit(cell, unit):
			push_error("DefenseSceneManager: UnitGroupStatus 연결에 실패했습니다. cell: " + str(cell))
			return false

	return true


func _RollbackDeploymentConfirmation() -> void:
	if _IsManagedUnit(_cp):
		_UnregisterUnit(_cp)

	_unitGroupManager.Clear()
	_cpManager.Clear()


func _StartBattle() -> void:
	_deploymentUnitsByCell.clear()

	_monsterTargetAcquisitionCursor = 0
	_unitTargetAcquisitionCursor = 0

	_pendingDefeat = false
	_pendingCPDestroyed = false

	_spawnManager.Initialize(_startData.cycle)
	_timeManager.Initialize()

	_phase = DefensePhase.BATTLE
	set_process(true)
	set_physics_process(true)


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


func _IssueChaseTarget(attacker: Unit, target: Unit) -> bool:
	if not _IsManagedUnit(attacker):
		return false

	if not _targetingManager.IsValidTarget(attacker, target):
		return false

	var units: Array[Unit] = [attacker]

	var commandId: int = IssueMoveCommand(units, target.global_position)
	if commandId < 0:
		return false

	if attacker.fsm == null:
		StopUnit(attacker.unitId)
		return false

	if not attacker.fsm.RequestChase(target):
		StopUnit(attacker.unitId)
		return false

	if not _targetingManager.SetTarget(attacker, target):
		StopUnit(attacker.unitId)
		attacker.fsm.RequestIdle()
		return false

	return true


func _ReturnToPool(character: Unit, poolManager: DefensePoolManager) -> bool:
	if character == null:
		return false

	if _IsManagedUnit(character):
		_UnregisterUnit(character)

	return poolManager.Return(character)


func _RegisterUnit(unit: Unit) -> bool:
	if unit == null:
		return false

	var unitId: int = _GetNextUnitId()
	var worldPosition: Vector2 = unit.global_position
	var previousUnitId: int = unit.unitId

	var movementAgent: MovementAgent = MovementAgent.new(
		unitId,
		worldPosition,
		unit.moveSpeed,
		unit.GetHalfSize(),
	)

	if not _movementSimulator.RegisterAgent(movementAgent):
		push_error("DefenseSceneManager: MovementAgent 등록에 실패했습니다. unitId: " + str(unitId))
		return false

	_stageSnapshot.RegisterUnit(unitId, worldPosition, unit.GetHalfSize())

	if not _stageSnapshot.HasUnit(unitId):
		_movementSimulator.UnregisterAgent(unitId)

		push_error("DefenseSceneManager: StageSnapshot 등록에 실패했습니다. unitId: " + str(unitId))
		return false

	if not _unitManager.RegisterUnit(unitId, unit):
		_stageSnapshot.UnregisterUnit(unitId)
		_movementSimulator.UnregisterAgent(unitId)

		push_error("DefenseSceneManager: UnitManager 등록에 실패했습니다. unitId: " + str(unitId))
		return false

	if _unitManager.GetUnit(unitId) != unit:
		unit.unitId = previousUnitId

		_unitManager.UnregisterUnit(unitId)
		_stageSnapshot.UnregisterUnit(unitId)
		_movementSimulator.UnregisterAgent(unitId)

		return false

	unit.unitId = unitId
	_BindUnitRuntime(unit)

	return true


func _UnregisterUnit(unit: Unit) -> void:
	if unit == null:
		return

	var unitId: int = unit.unitId
	if not _unitManager.HasUnit(unitId) or _unitManager.GetUnit(unitId) != unit:
		return

	if _targetingManager != null:
		_targetingManager.RemoveUnit(unit)

	_UnbindUnitRuntime(unit)

	_movementSimulator.UnregisterAgent(unitId)
	_stageSnapshot.UnregisterUnit(unitId)
	_unitManager.UnregisterUnit(unitId)


func _GetNextUnitId() -> int:
	while _unitManager.HasUnit(_nextUnitId):
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


func _UpdateTargeting(characterType: CharacterData.CharacterType) -> void:
	var characterManager: DefenseCharacterManager = _GetCharacterManager(characterType)
	if characterManager == null:
		return

	var characters: Array[Unit] = characterManager.GetCharacters()
	for character: Unit in characters:
		if not _IsManagedUnit(character):
			continue

		if character.fsm == null or not character.fsm.CanReceiveCommands():
			continue

		_UpdateCharacterTargeting(character, characterType)


func _UpdateCharacterTargeting(character: Unit, characterType: CharacterData.CharacterType) -> void:
	var target: Unit = _targetingManager.GetTarget(character)

	if target == null:
		_HandleMissingTarget(character, characterType)
		return

	if (
		characterType == CharacterData.CharacterType.UNIT
		and not _targetingManager.IsInAcquisitionRange(character, target)
	):
		_targetingManager.ClearTarget(character)
		_ReturnUnitToIdle(character)
		return

	if _targetingManager.IsInAttackRange(character, target):
		_EnterAttack(character, target, characterType)
		return

	if character.fsm.currentState != UnitFSM.State.ATTACK:
		return

	match characterType:
		CharacterData.CharacterType.MONSTER:
			_IssueChaseTarget(character, target)

		CharacterData.CharacterType.UNIT:
			character.fsm.ReturnFromAttackOutOfRange()


func _HandleMissingTarget(character: Unit, characterType: CharacterData.CharacterType) -> void:
	match characterType:
		CharacterData.CharacterType.MONSTER:
			_IssueChaseTarget(character, _cp)

		CharacterData.CharacterType.UNIT:
			_ReturnUnitToIdle(character)


func _ReturnUnitToIdle(unit: Unit) -> void:
	if unit.fsm.currentState == UnitFSM.State.ATTACK:
		unit.fsm.RequestIdle()


func _EnterAttack(attacker: Unit, target: Unit, characterType: CharacterData.CharacterType) -> void:
	if attacker.fsm.currentState == UnitFSM.State.ATTACK:
		return

	var returnState: UnitFSM.State = UnitFSM.State.IDLE

	if characterType == CharacterData.CharacterType.MONSTER:
		if not StopUnit(attacker.unitId):
			return

		returnState = UnitFSM.State.CHASE

	attacker.fsm.RequestAttack(target, returnState)


func _UpdateTargetAcquisition(
	characterType: CharacterData.CharacterType,
	cursor: int,
	fixedDelta: float,
) -> int:
	var characterManager: DefenseCharacterManager = _GetCharacterManager(characterType)
	if characterManager == null:
		return 0

	var characters: Array[Unit] = characterManager.GetCharacters()
	var characterCount: int = characters.size()
	if characterCount == 0:
		return 0

	var acquisitionCount: int = mini(
		ceili(float(characterCount) * fixedDelta / TARGET_ACQUISITION_INTERVAL),
		characterCount,
	)

	for i: int in range(acquisitionCount):
		if cursor >= characterCount:
			cursor = 0

		var character: Unit = characters[cursor]
		cursor += 1

		if not _IsManagedUnit(character):
			continue

		if character.fsm == null or not character.fsm.CanReceiveCommands():
			continue

		var currentTarget: Unit = _targetingManager.GetTarget(character)
		if not _ShouldAcquireTarget(characterType, currentTarget):
			continue

		var newTarget: Unit = (_targetingManager.FindNearestEnemyInAcquisitionRange(character))
		if newTarget == null:
			continue

		_SetAcquiredTarget(character, newTarget, characterType)

	return cursor


func _ShouldAcquireTarget(characterType: CharacterData.CharacterType, currentTarget: Unit) -> bool:
	match characterType:
		CharacterData.CharacterType.MONSTER:
			# CP를 향하고 있을 때만 주변 Unit을 새로 탐색한다.
			return currentTarget == _cp

		CharacterData.CharacterType.UNIT:
			# 기존 타겟이 없을 때만 새 Monster를 탐색한다.
			return currentTarget == null

	return false


func _SetAcquiredTarget(
	character: Unit,
	target: Unit,
	characterType: CharacterData.CharacterType,
) -> void:
	match characterType:
		CharacterData.CharacterType.MONSTER:
			if _IssueChaseTarget(character, target):
				return

			if not _IssueChaseTarget(character, _cp):
				push_warning(
					"DefenseSceneManager: Monster 타겟 전환 및 CP 복귀에 실패했습니다. unitId: "
					+ str(character.unitId)
				)

		CharacterData.CharacterType.UNIT:
			_targetingManager.SetTarget(character, target)


func _UpdateCombat() -> void:
	_UpdateCharacterCombat(_unitGroupManager)
	_UpdateCharacterCombat(_monsterManager)

	_combatManager.FlushAttacks()

	_ResolvePendingBattleEnd()


func _UpdateCharacterCombat(characterManager: DefenseCharacterManager) -> void:
	var characters: Array[Unit] = characterManager.GetCharacters()
	for attacker: Unit in characters:
		if not _IsManagedUnit(attacker):
			continue

		var target: Unit = _targetingManager.GetTarget(attacker)
		_combatManager.UpdateAttacker(attacker, target)


func _CalculateAttackBufferCapacity() -> int:
	if _startData == null:
		return 0

	var maxFriendlyCount: int = Math.ApplyRatio(
		_startData.population,
		DefenseDeploymentManager.MAX_RECRUIT_RATIO,
	)

	var spawnDataList: Array[DefenseSpawnData] = GameDataManager.GetDefenseSpawnData(
		_startData.cycle
	)
	var totalMonsterCount: int = 0
	for spawnData: DefenseSpawnData in spawnDataList:
		totalMonsterCount += spawnData.count

	return (maxFriendlyCount + totalMonsterCount) * ATTACK_BUFFER_CAPACITY_MULTIPLIER


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

	_FinishDefense(true)


func _ResolvePendingBattleEnd() -> void:
	if _phase != DefensePhase.BATTLE:
		return

	if not _pendingDefeat:
		return

	var cpDestroyed: bool = _pendingCPDestroyed

	_pendingDefeat = false
	_pendingCPDestroyed = false

	_FinishDefense(false, cpDestroyed)


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

	if _IsManagedUnit(_cp):
		_UnregisterUnit(_cp)

	_unitGroupManager.Clear()
	_monsterManager.Clear()
	_cpManager.Clear()


func _CleanupCharacters(
	characterManager: DefenseCharacterManager,
	poolManager: DefensePoolManager,
) -> void:
	var characters: Array[Unit] = characterManager.GetCharacters()
	for character: Unit in characters:
		_RemoveCharacter(character, characterManager, poolManager)
