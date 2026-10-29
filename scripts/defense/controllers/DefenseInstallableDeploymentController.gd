class_name DefenseInstallableDeploymentController
extends RefCounted

var _deploymentManager: DefenseInstallableDeploymentManager
var _unitDeploymentManager: DefenseDeploymentManager

var _machineManager: DefenseMachineManager
var _trapManager: DefenseTrapManager

var _unitFactory: DefenseUnitFactory
var _navigationService: NavigationService
var _unitLifecycle: DefenseUnitLifecycle
var _stageSnapshot: StageSnapshot

var _deploymentUnitsByCell: Dictionary[Vector2i, Unit] = { }
var _nearbyUnitIdBuffer: PackedInt32Array = []


func _init(
	deploymentManager: DefenseInstallableDeploymentManager,
	unitDeploymentManager: DefenseDeploymentManager,
	machineManager: DefenseMachineManager,
	trapManager: DefenseTrapManager,
	unitFactory: DefenseUnitFactory,
	navigationService: NavigationService,
	unitLifecycle: DefenseUnitLifecycle,
	stageSnapshot: StageSnapshot,
) -> void:
	_deploymentManager = deploymentManager
	_unitDeploymentManager = unitDeploymentManager

	_machineManager = machineManager
	_trapManager = trapManager

	_unitFactory = unitFactory
	_navigationService = navigationService
	_unitLifecycle = unitLifecycle
	_stageSnapshot = stageSnapshot


func Initialize(availableCountByCharacterKey: Dictionary[int, int]) -> bool:
	_deploymentUnitsByCell.clear()

	return _deploymentManager.Initialize(availableCountByCharacterKey)


func GetDeploymentByCell(
	cell: Vector2i,
) -> DefenseInstallableDeploymentManager.DefenseInstallableDeployment:
	return _deploymentManager.GetDeploymentByCell(cell)


func GetAvailableCount(characterKey: int) -> int:
	return _deploymentManager.GetAvailableCount(characterKey)


func GetDeployedCount(characterKey: int) -> int:
	return _deploymentManager.GetDeployedCount(characterKey)


func GetRemainingCount(characterKey: int) -> int:
	return _deploymentManager.GetRemainingCount(characterKey)


func HasDeployment() -> bool:
	return _deploymentManager.HasDeployment()


func AddDeployment(cell: Vector2i, characterData: CharacterData, position: Vector2) -> bool:
	if not _IsValidInstallable(characterData):
		return false

	# 병력이 이미 점유한 Cell
	if _unitDeploymentManager.GetDeploymentByCell(cell) != null:
		return false

	if not _deploymentManager.AddDeployment(cell, characterData.characterKey):
		return false

	var unit: Unit = _SpawnDeploymentUnit(characterData, position)
	if unit == null:
		_deploymentManager.RemoveDeployment(cell)
		return false

	_deploymentUnitsByCell[cell] = unit
	return true


func RemoveDeployment(cell: Vector2i) -> bool:
	var deployment: DefenseInstallableDeploymentManager.DefenseInstallableDeployment = _deploymentManager.GetDeploymentByCell(
		cell
	)
	if deployment == null:
		return false

	var unit: Unit = _deploymentUnitsByCell.get(cell)
	if unit == null:
		push_error(
			"DefenseInstallableDeploymentController: "
			+ "배치 데이터에 대응하는 Unit이 없습니다. cell: " + str(cell)
		)
		return false

	if not _unitLifecycle.DestroyUnit(unit):
		push_error(
			"DefenseInstallableDeploymentController: " + "배치 Unit 제거에 실패했습니다. cell: " + str(cell)
		)
		return false

	if not _deploymentManager.RemoveDeployment(cell):
		return false

	_deploymentUnitsByCell.erase(cell)

	return true


func UpdateDeployment(cell: Vector2i, characterData: CharacterData) -> bool:
	if not _IsValidInstallable(characterData):
		return false

	var deployment: DefenseInstallableDeploymentManager.DefenseInstallableDeployment = _deploymentManager.GetDeploymentByCell(
		cell
	)
	if deployment == null:
		return false

	if deployment.characterKey == characterData.characterKey:
		return true

	return _ReplaceDeploymentUnit(cell, deployment, characterData)


func BindPreparedInstallables() -> bool:
	_machineManager.Clear()
	_trapManager.Clear()

	var cells: Array[Vector2i] = _deploymentManager.GetDeploymentCells()
	for cell: Vector2i in cells:
		var deployment: DefenseInstallableDeploymentManager.DefenseInstallableDeployment = _deploymentManager.GetDeploymentByCell(
			cell
		)
		var unit: Unit = _deploymentUnitsByCell.get(cell)
		if deployment == null or unit == null:
			_RollbackBindings()
			return false

		var characterData: CharacterData = GameDataManager.GetCharacterData(deployment.characterKey)
		if characterData == null:
			_RollbackBindings()
			return false

		var bindSuccess: bool = false
		match characterData.characterType:
			CharacterType.MACHINE:
				bindSuccess = _machineManager.AddMachine(unit as Machine, characterData)
			CharacterType.TRAP:
				bindSuccess = _trapManager.AddTrap(unit as Trap, characterData)

		if not bindSuccess:
			_RollbackBindings()
			return false

	return true


func RollbackBattlePreparation() -> void:
	_RollbackBindings()


func CompleteDeployment() -> void:
	_deploymentUnitsByCell.clear()


func _SpawnDeploymentUnit(
	characterData: CharacterData,
	position: Vector2,
	ignoredUnitId: int = -1,
) -> Unit:
	var unit: Unit = _unitFactory.Create(characterData, position)
	if unit == null:
		return null

	if not _CanPlaceUnit(unit, position, ignoredUnitId):
		unit.queue_free()
		return null

	if not _unitLifecycle.RegisterUnit(unit):
		unit.queue_free()
		return null

	return unit


func _CanPlaceUnit(unit: Unit, position: Vector2, ignoredUnitId: int = -1) -> bool:
	var halfSize: int = unit.GetHalfSize()
	if not _navigationService.CanPlaceStatic(position, halfSize):
		return false

	var nearbyCount: int = _stageSnapshot.FindUnitIdsInRect(
		position,
		Vector2(halfSize, halfSize),
		_nearbyUnitIdBuffer,
	)

	for index: int in range(nearbyCount):
		var nearbyUnitId: int = _nearbyUnitIdBuffer[index]
		if nearbyUnitId != ignoredUnitId:
			return false

	return true


func _ReplaceDeploymentUnit(
	cell: Vector2i,
	deployment: DefenseInstallableDeploymentManager.DefenseInstallableDeployment,
	characterData: CharacterData,
) -> bool:
	var previousUnit: Unit = _deploymentUnitsByCell.get(cell)
	if previousUnit == null:
		return false

	var previousCharacterKey: int = deployment.characterKey
	var position: Vector2 = previousUnit.position

	var newUnit: Unit = _SpawnDeploymentUnit(characterData, position, previousUnit.unitId)
	if newUnit == null:
		return false

	if not _deploymentManager.UpdateDeployment(cell, characterData.characterKey):
		if not _unitLifecycle.DestroyUnit(newUnit):
			push_error(
				"DefenseInstallableDeploymentController: "
				+ "새 배치 Unit 롤백 제거에 실패했습니다. cell: " + str(cell)
			)
		return false

	if not _unitLifecycle.DestroyUnit(previousUnit):
		if not _deploymentManager.UpdateDeployment(cell, previousCharacterKey):
			push_error(
				"DefenseInstallableDeploymentController: " + "배치 데이터 롤백에 실패했습니다. cell: " + str(cell)
			)

		if not _unitLifecycle.DestroyUnit(newUnit):
			push_error(
				"DefenseInstallableDeploymentController: "
				+ "새 배치 Unit 롤백 제거에 실패했습니다. cell: " + str(cell)
			)

		push_error(
			"DefenseInstallableDeploymentController: " + "기존 배치 Unit 제거에 실패했습니다. cell: " + str(cell)
		)
		return false

	_deploymentUnitsByCell[cell] = newUnit
	return true


func _RollbackBindings() -> void:
	_machineManager.Clear()
	_trapManager.Clear()


func _IsValidInstallable(characterData: CharacterData) -> bool:
	if characterData == null:
		return false

	return (
		characterData.characterType == CharacterType.MACHINE
		or characterData.characterType == CharacterType.TRAP
	)
