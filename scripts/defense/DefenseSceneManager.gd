class_name DefenseSceneManager
extends Node

const ATTACK_BUFFER_CAPACITY_MULTIPLIER: int = 2

signal DefenseFinished(result: DefenseResult)

enum DefensePhase {
	UNIT_DEPLOYMENT,
	INSTALLABLE_DEPLOYMENT,
	MERCENARY_ASSIGNMENT,
	BATTLE,
	FINISHED,
}


@export_group("Scene")
@export var _spawnPoints: Node2D
@export var _pools: Node
@export var _friendlyUnits: Node2D
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
var _installableDeploymentManager: DefenseInstallableDeploymentManager
var _mercenaryAssignmentManager: DefenseMercenaryAssignmentManager

var _unitGroupManager: DefenseUnitGroupManager
var _machineManager: DefenseMachineManager
var _trapManager: DefenseTrapManager
var _monsterManager: DefenseMonsterManager
var _cpManager: DefenseCPManager
var _spawnManager: DefenseSpawnManager
var _spawnPositionManager: DefenseSpawnPositionManager
var _timeManager: DefenseTimeManager
var _targetingManager: DefenseTargetingManager
var _combatManager: DefenseCombatManager
var _unitLifecycle: DefenseUnitLifecycle
var _deploymentController: DefenseDeploymentController
var _installableDeploymentController: DefenseInstallableDeploymentController
var _spawnController: DefenseSpawnController

var _monsterPoolManager: DefensePoolManager.MonsterPoolManager
var _unitFactory: DefenseUnitFactory

var _pendingDefeat: bool = false
var _pendingCPDestroyed: bool = false

var _phase: DefensePhase = DefensePhase.UNIT_DEPLOYMENT


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
	if not _installableDeploymentController.Initialize(_startData.installableCountByCharacterKey):
		push_error("DefenseSceneManager: InstallableDeploymentController 초기화에 실패했습니다.")
		return false
	if not _mercenaryAssignmentManager.Initialize(_startData.availableMercenaryKeys):
		push_error("DefenseSceneManager: MercenaryAssignmentManager 초기화에 실패했습니다.")
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
	_installableDeploymentManager = DefenseInstallableDeploymentManager.new()
	_mercenaryAssignmentManager = DefenseMercenaryAssignmentManager.new(_deploymentManager)

	_unitGroupManager = DefenseUnitGroupManager.new()
	_unitGroupManager.CharacterDied.connect(_OnCharacterDied)

	_machineManager = DefenseMachineManager.new()
	_machineManager.CharacterDied.connect(_OnCharacterDied)

	_trapManager = DefenseTrapManager.new()
	_trapManager.CharacterDied.connect(_OnCharacterDied)

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

	_unitFactory = DefenseUnitFactory.new(_friendlyUnits)

	_unitLifecycle = DefenseUnitLifecycle.new(_unitRuntime)

	_battleContext = DefenseBattleFacade.new(
		_unitRuntime,
		_unitGroupManager,
		_machineManager,
		_trapManager,
		_monsterManager,
		_cpManager,
	)
	_targetingManager = DefenseTargetingManager.new(_battleContext, _unitRuntime)
	_unitLifecycle.UnitUnregistered.connect(_targetingManager.RemoveUnit)
	_combatManager = DefenseCombatManager.new(_battleContext)

	_deploymentController = DefenseDeploymentController.new(
		_deploymentManager,
		_unitGroupManager,
		_unitFactory,
		_navigationService,
		_unitLifecycle,
	)
	_installableDeploymentController = DefenseInstallableDeploymentController.new(
		_installableDeploymentManager,
		_deploymentManager,
		_machineManager,
		_trapManager,
		_unitFactory,
		_navigationService,
		_unitLifecycle,
		_unitRuntime.GetStageSnapshot(),
	)

	_spawnController = DefenseSpawnController.new(
		_spawnPositionManager,
		_monsterPoolManager,
		_monsterManager,
		_unitLifecycle,
	)
	_spawnController.MonstersSpawned.connect(_targetingManager.IssueChaseGroupsToCP)


func _StartBattle() -> void:
	_deploymentController.CompleteDeployment()
	_installableDeploymentController.CompleteDeployment()

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
	_CleanupCharacters(_unitGroupManager)
	_CleanupCharacters(_machineManager)
	_CleanupCharacters(_trapManager)
	_CleanupCharacters(_monsterManager, _monsterPoolManager)

	if _unitLifecycle.IsManagedUnit(_cp):
		_unitLifecycle.UnregisterUnit(_cp)

	_unitGroupManager.Clear()
	_machineManager.Clear()
	_trapManager.Clear()
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
	if _phase != DefensePhase.UNIT_DEPLOYMENT:
		return false

	var characterData: CharacterData = GameDataManager.GetCharacterData(characterKey)
	if characterData == null:
		return false

	return _deploymentController.AddDeployment(cell, characterData, recruitRatio, position)


func RemoveDeployment(cell: Vector2i) -> bool:
	if _phase != DefensePhase.UNIT_DEPLOYMENT:
		return false

	return _deploymentController.RemoveDeployment(cell)


func UpdateDeployment(cell: Vector2i, characterKey: int, recruitRatio: int) -> bool:
	if _phase != DefensePhase.UNIT_DEPLOYMENT:
		return false

	var characterData: CharacterData = GameDataManager.GetCharacterData(characterKey)
	if characterData == null:
		return false

	return _deploymentController.UpdateDeployment(cell, characterData, recruitRatio)


func ConfirmDeployment() -> bool:
	if _phase != DefensePhase.UNIT_DEPLOYMENT:
		return false

	if not _deploymentController.HasDeployment():
		push_error("DefenseSceneManager: 배치된 병력이 없습니다.")
		return false

	_phase = DefensePhase.INSTALLABLE_DEPLOYMENT
	return true

#endregion


#region Installable Deployment

func GetInstallableDeploymentByCell(
	cell: Vector2i,
) -> DefenseInstallableDeploymentManager.DefenseInstallableDeployment:
	return _installableDeploymentController.GetDeploymentByCell(cell)


func GetInstallableAvailableCount(characterKey: int) -> int:
	return _installableDeploymentController.GetAvailableCount(characterKey)


func GetInstallableDeployedCount(characterKey: int) -> int:
	return _installableDeploymentController.GetDeployedCount(characterKey)


func GetInstallableRemainingCount(characterKey: int) -> int:
	return _installableDeploymentController.GetRemainingCount(characterKey)


func AddInstallableDeployment(cell: Vector2i, characterKey: int, position: Vector2) -> bool:
	if _phase != DefensePhase.INSTALLABLE_DEPLOYMENT:
		return false

	var characterData: CharacterData = GameDataManager.GetCharacterData(characterKey)
	if characterData == null:
		return false

	return _installableDeploymentController.AddDeployment(cell, characterData, position)


func RemoveInstallableDeployment(cell: Vector2i) -> bool:
	if _phase != DefensePhase.INSTALLABLE_DEPLOYMENT:
		return false

	return _installableDeploymentController.RemoveDeployment(cell)


func UpdateInstallableDeployment(cell: Vector2i, characterKey: int) -> bool:
	if _phase != DefensePhase.INSTALLABLE_DEPLOYMENT:
		return false

	var characterData: CharacterData = GameDataManager.GetCharacterData(characterKey)
	if characterData == null:
		return false

	return _installableDeploymentController.UpdateDeployment(cell, characterData)


func ConfirmInstallableDeployment() -> bool:
	if _phase != DefensePhase.INSTALLABLE_DEPLOYMENT:
		return false

	_phase = DefensePhase.MERCENARY_ASSIGNMENT
	return true


func _PrepareBattle() -> bool:
	if not _deploymentController.PrepareUnitGroups():
		return false

	if not _cpManager.Initialize(_cp, _startData.cpMaxHp, _startData.cpDef, _startData.cpMagicDef):
		push_error("DefenseSceneManager: 지휘소 초기화에 실패했습니다.")
		_RollbackBattlePreparation()
		return false

	if not _unitLifecycle.RegisterUnit(_cp):
		push_error("DefenseSceneManager: CP Runtime 등록에 실패했습니다.")
		_RollbackBattlePreparation()
		return false

	if not _ApplyUnitGroupMercenaryBuffs():
		push_error("DefenseSceneManager: 부대 용병 버프 적용에 실패했습니다.")
		_RollbackBattlePreparation()
		return false

	if not _ApplyCPMercenaryBuffs():
		push_error("DefenseSceneManager: 지휘소 용병 버프 적용에 실패했습니다.")
		_RollbackBattlePreparation()
		return false

	if not _deploymentController.BindPreparedUnits():
		_RollbackBattlePreparation()
		return false

	if not _installableDeploymentController.BindPreparedInstallables():
		_RollbackBattlePreparation()
		return false

	return true


func _RollbackBattlePreparation() -> void:
	if _unitLifecycle.IsManagedUnit(_cp):
		_unitLifecycle.UnregisterUnit(_cp)

	_deploymentController.ClearUnitBonuses()
	_deploymentController.RollbackBattlePreparation()
	_installableDeploymentController.RollbackBattlePreparation()

	_cpManager.Clear()

#endregion


#region Mercenary Assignment

func AssignMercenaryToUnit(mercenaryKey: int, cell: Vector2i) -> bool:
	if _phase != DefensePhase.MERCENARY_ASSIGNMENT:
		return false

	return _mercenaryAssignmentManager.AssignToUnit(mercenaryKey, cell)


func AssignMercenaryToCP(mercenaryKey: int) -> bool:
	if _phase != DefensePhase.MERCENARY_ASSIGNMENT:
		return false

	return _mercenaryAssignmentManager.AssignToCP(mercenaryKey)


func UnassignMercenary(mercenaryKey: int) -> bool:
	if _phase != DefensePhase.MERCENARY_ASSIGNMENT:
		return false

	return _mercenaryAssignmentManager.Unassign(mercenaryKey)


func GetMercenaryKeyByUnitCell(cell: Vector2i) -> int:
	return _mercenaryAssignmentManager.GetMercenaryKeyByUnitCell(cell)


func GetCPMercenaryKey() -> int:
	return _mercenaryAssignmentManager.GetCPMercenaryKey()


func GetMercenaryAssignment(
	mercenaryKey: int,
) -> DefenseMercenaryAssignmentManager.DefenseMercenaryAssignment:
	return _mercenaryAssignmentManager.GetAssignment(mercenaryKey)


func CanConfirmMercenaryAssignment() -> bool:
	return _mercenaryAssignmentManager.CanConfirmAssignment()


func IsMercenaryAssigned(mercenaryKey: int) -> bool:
	return _mercenaryAssignmentManager.IsAssigned(mercenaryKey)


func ConfirmMercenaryAssignment() -> bool:
	if _phase != DefensePhase.MERCENARY_ASSIGNMENT:
		return false

	if not _mercenaryAssignmentManager.CanConfirmAssignment():
		push_error("DefenseSceneManager: 주인공 부대 배치와 지휘소 용병 배치가 필요합니다.")
		return false

	if not _PrepareBattle():
		return false

	_StartBattle()
	return true

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


func _ApplyUnitGroupMercenaryBuffs() -> bool:
	_deploymentController.ClearUnitBonuses()

	var cells: Array[Vector2i] = _deploymentManager.GetDeploymentCells()
	for cell: Vector2i in cells:
		var mercenaryKey: int = _mercenaryAssignmentManager.GetMercenaryKeyByUnitCell(cell)
		if mercenaryKey < 0:
			continue

		var buffDataList: Array[MercenaryBuffData] = GameDataManager.GetMercenaryBuffData(
			mercenaryKey
		)
		for buffData: MercenaryBuffData in buffDataList:
			if not _deploymentController.ApplyUnitBonus(cell, buffData):
				return false

	return true


func _ApplyCPMercenaryBuffs() -> bool:
	var mercenaryKey: int = _mercenaryAssignmentManager.GetCPMercenaryKey()
	if mercenaryKey < 0:
		return true

	var buffDataList: Array[MercenaryBuffData] = GameDataManager.GetMercenaryBuffData(mercenaryKey)
	for buffData: MercenaryBuffData in buffDataList:
		if not _IsCPStatType(buffData.statType):
			continue

		if not _cpManager.ApplyStatBonus(buffData.statType, buffData.flatValue, buffData.ratioValue):
			return false

	return true


# 임시 방어용.. 추후 CP 스텟 개선 필요
func _IsCPStatType(type: CharacterStats.Type) -> bool:
	return (
		type == CharacterStats.Type.MAX_HP or type == CharacterStats.Type.DEF
		or type == CharacterStats.Type.MAGIC_DEF
	)


#region Character Lifecycle

func _OnCharacterDied(character: Unit) -> void:
	if _phase != DefensePhase.BATTLE or character == null:
		return

	var characterType: CharacterData.CharacterType = character.characterType
	var characterManager: DefenseCharacterManager = _GetCharacterManager(characterType)
	if characterManager == null:
		return

	if characterType == CharacterData.CharacterType.MONSTER:
		if not _RemoveCharacter(character, characterManager, _monsterPoolManager):
			return
	else:
		if not _RemoveCharacter(character, characterManager):
			return

	if (
		characterType == CharacterData.CharacterType.UNIT
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
	poolManager: DefensePoolManager = null,
) -> bool:
	if character == null:
		return false

	# 먼저 전투 데이터에서 제거한다. 실패하면 Pool로 보내면 안 된다.
	if not characterManager.UnregisterCharacter(character):
		push_error("DefenseSceneManager: Character 연결 해제에 실패했습니다. unitId: " + str(character.unitId))
		return false

	# 그 다음 Runtime 제거 + Pool 반환.
	if poolManager != null:
		if not _unitLifecycle.ReturnToPool(character, poolManager):
			push_error(
				"DefenseSceneManager: Character Pool 반환에 실패했습니다. unitId: " + str(character.unitId)
			)
			return false
	else:
		if not _unitLifecycle.DestroyUnit(character):
			push_error(
				"DefenseSceneManager: Character 제거에 실패했습니다. unitId: " + str(character.unitId)
			)
			return false

	return true


func _CleanupCharacters(
	characterManager: DefenseCharacterManager,
	poolManager: DefensePoolManager = null,
) -> void:
	while characterManager.GetCharacterCount() > 0:
		var lastIndex: int = characterManager.GetCharacterCount() - 1
		var character: Unit = characterManager.GetCharacterByIndex(lastIndex)

		if not characterManager.UnregisterCharacter(character):
			push_error(
				"DefenseSceneManager: Character 연결 해제에 실패했습니다. unitId: " + str(character.unitId)
			)
			break

		var removed: bool
		if poolManager != null:
			removed = _unitLifecycle.ReturnToPool(character, poolManager)
		else:
			removed = _unitLifecycle.DestroyUnit(character)

		if not removed:
			push_error(
				"DefenseSceneManager: Character 정리에 실패했습니다. unitId: " + str(character.unitId)
			)
			break
#endregion


#region Helper

func _GetCharacterManager(characterType: CharacterData.CharacterType) -> DefenseCharacterManager:
	match characterType:
		CharacterData.CharacterType.UNIT:
			return _unitGroupManager

		CharacterData.CharacterType.MACHINE:
			return _machineManager

		CharacterData.CharacterType.TRAP:
			return _trapManager

		CharacterData.CharacterType.MONSTER:
			return _monsterManager

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
