class_name DefenseSceneManager
extends Node

const ATTACK_BUFFER_CAPACITY_MULTIPLIER: int = 2

signal DefenseFinished(result: DefenseResult)

enum DefensePhase {
	DEPLOYMENT,
	BATTLE,
	FINISHED,
}


@export_group("Scene")
@export var _spawnPoints: Node2D
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
var _unitRuntime: UnitRuntime
var _battleContext: DefenseBattleFacade

var _spawnDataList: Array[DefenseSpawnData] = []

var _deploymentManager: DefenseDeploymentManager
var _unitGroupManager: DefenseUnitGroupManager
var _monsterManager: DefenseMonsterManager
var _cpManager: DefenseCPManager
var _spawnManager: DefenseSpawnManager
var _spawnPositionManager: DefenseSpawnPositionManager
var _timeManager: DefenseTimeManager
var _targetingManager: DefenseTargetingManager
var _combatManager: DefenseCombatManager
var _unitLifecycle: DefenseUnitLifecycle
var _deploymentController: DefenseDeploymentController
var _spawnController: DefenseSpawnController

var _monsterPoolManager: DefensePoolManager.MonsterPoolManager
var _unitPoolManager: DefensePoolManager.UnitPoolManager
# var _trapPoolManager: DefenseTrapPoolManager

var _pendingDefeat: bool = false
var _pendingCPDestroyed: bool = false

var _phase: DefensePhase = DefensePhase.DEPLOYMENT


#region Lifecycle

func _ready() -> void:
	set_process(false)
	set_physics_process(false)

	if not _InitializeNavigation():
		return

	_unitRuntime = UnitRuntime.new()
	if not _unitRuntime.Initialize(_navigationService, initialUnitCapacity):
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
	_spawnDataList = GameDataManager.GetDefenseSpawnData(_startData.cycle)

	if not _deploymentController.Initialize(_startData.population):
		push_error("DefenseSceneManager: DeploymentController 초기화에 실패했습니다.")
		return false

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

	_unitRuntime.Simulate(fixedDelta)

	_targetingManager.Update()
	_combatManager.Update()
	_combatManager.FlushAttacks()

	_ResolvePendingBattleEnd()


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
	_spawnManager.MonsterSpawnBatchRequested.connect(_OnMonsterSpawnBatchRequested)

	_spawnPositionManager = DefenseSpawnPositionManager.new(
		_spawnPoints,
		_navigationService,
		_unitRuntime.GetStageSnapshot(),
	)

	_timeManager = DefenseTimeManager.new()

	var monsterPool: Node2D = _pools.get_node("MonsterPool")
	_monsterPoolManager = DefensePoolManager.MonsterPoolManager.new(monsterPool)

	var unitPool: Node2D = _pools.get_node("UnitPool")
	_unitPoolManager = DefensePoolManager.UnitPoolManager.new(unitPool)

	_unitLifecycle = DefenseUnitLifecycle.new(_unitRuntime)

	_battleContext = DefenseBattleFacade.new(
		_unitRuntime,
		_unitGroupManager,
		_monsterManager,
		_cpManager,
	)
	_targetingManager = DefenseTargetingManager.new(_battleContext, _unitRuntime)
	_unitLifecycle.UnitUnregistered.connect(_targetingManager.RemoveUnit)
	_combatManager = DefenseCombatManager.new(_battleContext)

	_deploymentController = DefenseDeploymentController.new(
		_deploymentManager,
		_unitGroupManager,
		_unitPoolManager,
		_navigationService,
		_unitLifecycle,
	)
	_spawnController = DefenseSpawnController.new(
		_spawnPositionManager,
		_monsterPoolManager,
		_monsterManager,
		_unitLifecycle,
	)
	_spawnController.MonstersSpawned.connect(_targetingManager.IssueChaseGroupsToCP)

	# var trapPool: Node2D = _pools.get_node("TrapPool")
	# _trapPoolManager = DefensePoolManager.TrapPoolManager.new(trapPool)


func _StartBattle() -> void:
	_deploymentController.CompleteDeployment()

	_targetingManager.Reset()

	_pendingDefeat = false
	_pendingCPDestroyed = false

	_spawnManager.Initialize(_spawnDataList)
	_timeManager.Initialize()

	_phase = DefensePhase.BATTLE
	set_process(true)
	set_physics_process(true)


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

	if _unitLifecycle.IsManagedUnit(_cp):
		_unitLifecycle.UnregisterUnit(_cp)

	_unitGroupManager.Clear()
	_monsterManager.Clear()
	_cpManager.Clear()

#endregion


#region Public API

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
	return _deploymentController.GetDeploymentByCell(cell)


func GetTotalRecruitRatio() -> int:
	return _deploymentController.GetTotalRecruitRatio()


func GetMaxRecruitRatio() -> int:
	return DefenseDeploymentManager.MAX_RECRUIT_RATIO


func GetMaxRecruitRatioForCell(cell: Vector2i) -> int:
	return _deploymentController.GetMaxRecruitRatioForCell(cell)


func GetTotalRecruitedPopulation() -> int:
	return _deploymentController.GetTotalRecruitedPopulation()


func GetElapsedTimeMs() -> int:
	return _timeManager.GetElapsedTimeMs()


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


func CalculateRecruitedPopulation(recruitRatio: int) -> int:
	return _deploymentController.CalculateRecruitedPopulation(recruitRatio)

#endregion


#region Deployment

func AddDeployment(cell: Vector2i, characterKey: int, recruitRatio: int, position: Vector2) -> bool:
	if _phase != DefensePhase.DEPLOYMENT:
		return false

	var characterData: CharacterData = GameDataManager.GetCharacterData(characterKey)
	if characterData == null:
		return false

	return _deploymentController.AddDeployment(cell, characterData, recruitRatio, position)


func RemoveDeployment(cell: Vector2i) -> bool:
	if _phase != DefensePhase.DEPLOYMENT:
		return false

	return _deploymentController.RemoveDeployment(cell)


func UpdateDeployment(cell: Vector2i, characterKey: int, recruitRatio: int) -> bool:
	if _phase != DefensePhase.DEPLOYMENT:
		return false

	var characterData: CharacterData = GameDataManager.GetCharacterData(characterKey)
	if characterData == null:
		return false

	return _deploymentController.UpdateDeployment(cell, characterData, recruitRatio)


func ConfirmDeployment() -> bool:
	if _phase != DefensePhase.DEPLOYMENT:
		return false

	if not _deploymentController.HasDeployment():
		push_error("DefenseSceneManager: 배치된 병력이 없습니다.")
		return false

	if not _deploymentController.PrepareUnitGroups():
		return false

	if not _cpManager.Initialize(_cp, _startData.cpMaxHp):
		push_error("DefenseSceneManager: 지휘소 초기화에 실패했습니다.")
		_RollbackDeploymentConfirmation()
		return false

	if not _unitLifecycle.RegisterUnit(_cp):
		push_error("DefenseSceneManager: CP Runtime 등록에 실패했습니다.")
		_RollbackDeploymentConfirmation()
		return false

	if not _deploymentController.BindPreparedUnits():
		_RollbackDeploymentConfirmation()
		return false

	_StartBattle()
	return true


func _RollbackDeploymentConfirmation() -> void:
	if _unitLifecycle.IsManagedUnit(_cp):
		_unitLifecycle.UnregisterUnit(_cp)

	_deploymentController.RollbackBattlePreparation()
	_cpManager.Clear()

#endregion


#region Spawn

func _OnMonsterSpawnBatchRequested(spawnPointKey: int, characterKey: int, count: int) -> void:
	if _phase != DefensePhase.BATTLE:
		return

	var characterData: CharacterData = GameDataManager.GetCharacterData(characterKey)
	if characterData == null:
		push_error("DefenseSceneManager: CharacterData를 찾을 수 없습니다. key: " + str(characterKey))
		return

	_spawnController.SpawnBatch(spawnPointKey, characterData, count)

#endregion


#region Character Lifecycle

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


func _OnCPDestroyed() -> void:
	if _phase != DefensePhase.BATTLE:
		return

	_pendingDefeat = true
	_pendingCPDestroyed = true


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
	if not _unitLifecycle.ReturnToPool(character, poolManager):
		push_error("DefenseSceneManager: Character 반환에 실패했습니다. unitId: " + str(character.unitId))
		return false

	return true


func _CleanupCharacters(
	characterManager: DefenseCharacterManager,
	poolManager: DefensePoolManager,
) -> void:
	while characterManager.GetCharacterCount() > 0:
		var lastIndex: int = characterManager.GetCharacterCount() - 1
		var character: Unit = characterManager.GetCharacterByIndex(lastIndex)

		if not _RemoveCharacter(character, characterManager, poolManager):
			push_error(
				"DefenseSceneManager: Character 정리 중 제거에 실패했습니다. unitId: " + str(character.unitId)
			)
			break

#endregion


#region Helper

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


func _CalculateAttackBufferCapacity() -> int:
	if _startData == null:
		return 0

	var maxFriendlyCount: int = Math.ApplyRatio(
		_startData.population,
		DefenseDeploymentManager.MAX_RECRUIT_RATIO,
	)

	var totalMonsterCount: int = 0
	for spawnData: DefenseSpawnData in _spawnDataList:
		totalMonsterCount += spawnData.count

	return (maxFriendlyCount + totalMonsterCount) * ATTACK_BUFFER_CAPACITY_MULTIPLIER

#endregion
