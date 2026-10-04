class_name DefenseRuntimeFactory
extends RefCounted


static func Create(
	spawnPoints: Node2D,
	pools: Node,
	friendlyUnits: Node2D,
	navigationService: NavigationService,
	unitRuntime: UnitRuntime,
) -> DefenseRuntime:
	var runtime: DefenseRuntime = DefenseRuntime.new()
	var stageSnapshot: StageSnapshot = unitRuntime.GetStageSnapshot()

	# Deployment / entity state
	var deploymentManager: DefenseDeploymentManager = DefenseDeploymentManager.new()

	var installableDeploymentManager: DefenseInstallableDeploymentManager = DefenseInstallableDeploymentManager.new()

	runtime.mercenaryAssignmentManager = DefenseMercenaryAssignmentManager.new(deploymentManager)

	runtime.unitGroupManager = DefenseUnitGroupManager.new()
	runtime.machineManager = DefenseMachineManager.new()
	runtime.trapManager = DefenseTrapManager.new()
	runtime.monsterManager = DefenseMonsterManager.new()

	# Battle runtime
	runtime.cpManager = DefenseCPManager.new()
	runtime.spawnManager = DefenseSpawnManager.new()
	runtime.timeManager = DefenseTimeManager.new()

	var spawnPositionManager: DefenseSpawnPositionManager = DefenseSpawnPositionManager.new(
		spawnPoints,
		navigationService,
		stageSnapshot,
	)

	var monsterPool: Node2D = pools.get_node("MonsterPool")

	var monsterPoolManager: DefensePoolManager.MonsterPoolManager = (
		DefensePoolManager.MonsterPoolManager.new(monsterPool)
	)

	var unitFactory: DefenseUnitFactory = DefenseUnitFactory.new(friendlyUnits)

	runtime.unitLifecycle = DefenseUnitLifecycle.new(unitRuntime)

	runtime.mercenaryBuffService = DefenseMercenaryBuffService.new(
		deploymentManager,
		runtime.mercenaryAssignmentManager,
		runtime.unitGroupManager,
	)

	runtime.characterRemovalService = DefenseCharacterRemovalService.new(
		runtime.unitGroupManager,
		runtime.machineManager,
		runtime.trapManager,
		runtime.monsterManager,
		monsterPoolManager,
		runtime.unitLifecycle,
	)

	var battleContext: DefenseBattleFacade = DefenseBattleFacade.new(
		unitRuntime,
		runtime.unitGroupManager,
		runtime.machineManager,
		runtime.trapManager,
		runtime.monsterManager,
		runtime.cpManager,
	)

	runtime.targetingManager = DefenseTargetingManager.new(battleContext, unitRuntime)

	runtime.combatManager = DefenseCombatManager.new(battleContext)

	# Controllers
	runtime.deploymentController = DefenseDeploymentController.new(
		deploymentManager,
		runtime.unitGroupManager,
		unitFactory,
		navigationService,
		runtime.unitLifecycle,
	)

	runtime.installableDeploymentController = DefenseInstallableDeploymentController.new(
		installableDeploymentManager,
		deploymentManager,
		runtime.machineManager,
		runtime.trapManager,
		unitFactory,
		navigationService,
		runtime.unitLifecycle,
		stageSnapshot,
	)

	runtime.spawnController = DefenseSpawnController.new(
		spawnPositionManager,
		monsterPoolManager,
		runtime.monsterManager,
		runtime.unitLifecycle,
	)

	_ConnectInternalSignals(runtime)

	return runtime


static func _ConnectInternalSignals(runtime: DefenseRuntime) -> void:
	runtime.unitLifecycle.UnitUnregistered.connect(runtime.targetingManager.RemoveUnit)
	runtime.spawnController.MonstersSpawned.connect(
		runtime.targetingManager.IssueDefaultChaseTargets
	)
