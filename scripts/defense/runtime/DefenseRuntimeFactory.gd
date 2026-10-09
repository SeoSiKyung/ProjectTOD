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

	runtime.towerManager = DefenseTowerManager.new()
	runtime.machineManager = DefenseMachineManager.new()
	runtime.trapManager = DefenseTrapManager.new()
	runtime.enemyManager = DefenseEnemyManager.new()

	# Battle runtime
	runtime.cpManager = DefenseCPManager.new()
	runtime.spawnManager = DefenseSpawnManager.new()
	runtime.timeManager = DefenseTimeManager.new()

	var spawnPositionManager: DefenseSpawnPositionManager = DefenseSpawnPositionManager.new(
		spawnPoints,
		navigationService,
		stageSnapshot,
	)

	var enemyPool: Node2D = pools.get_node("EnemyPool")

	var enemyPoolManager: DefensePoolManager.EnemyPoolManager = (
		DefensePoolManager.EnemyPoolManager.new(enemyPool)
	)

	var unitFactory: DefenseUnitFactory = DefenseUnitFactory.new(friendlyUnits)

	runtime.unitLifecycle = DefenseUnitLifecycle.new(unitRuntime)

	runtime.mercenaryBuffService = DefenseMercenaryBuffService.new(
		deploymentManager,
		runtime.mercenaryAssignmentManager,
		runtime.towerManager,
	)

	runtime.characterRemovalService = DefenseCharacterRemovalService.new(
		runtime.towerManager,
		runtime.machineManager,
		runtime.trapManager,
		runtime.enemyManager,
		enemyPoolManager,
		runtime.unitLifecycle,
	)

	var battleContext: DefenseBattleFacade = DefenseBattleFacade.new(
		unitRuntime,
		runtime.towerManager,
		runtime.machineManager,
		runtime.trapManager,
		runtime.enemyManager,
		runtime.cpManager,
	)

	runtime.targetingManager = DefenseTargetingManager.new(battleContext, unitRuntime)

	runtime.combatManager = DefenseCombatManager.new(battleContext)

	# Controllers
	runtime.deploymentController = DefenseDeploymentController.new(
		deploymentManager,
		runtime.towerManager,
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
		enemyPoolManager,
		runtime.enemyManager,
		runtime.unitLifecycle,
	)

	_ConnectInternalSignals(runtime)

	return runtime


static func _ConnectInternalSignals(runtime: DefenseRuntime) -> void:
	runtime.unitLifecycle.UnitUnregistered.connect(runtime.targetingManager.RemoveUnit)
	runtime.spawnController.EnemiesSpawned.connect(runtime.targetingManager.IssueInitialEnemyChases)
