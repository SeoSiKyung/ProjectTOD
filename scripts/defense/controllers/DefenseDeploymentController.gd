class_name DefenseDeploymentController
extends RefCounted

var _deploymentManager: DefenseDeploymentManager
var _unitGroupManager: DefenseUnitGroupManager
var _unitPoolManager: DefensePoolManager.UnitPoolManager
var _navigationService: NavigationService
var _unitLifecycle: DefenseUnitLifecycle

var _deploymentUnitsByCell: Dictionary[Vector2i, Unit] = { }
var _totalPopulation: int = 0


func _init(
	deploymentManager: DefenseDeploymentManager,
	unitGroupManager: DefenseUnitGroupManager,
	unitPoolManager: DefensePoolManager.UnitPoolManager,
	navigationService: NavigationService,
	unitLifecycle: DefenseUnitLifecycle,
) -> void:
	_deploymentManager = deploymentManager
	_unitGroupManager = unitGroupManager
	_unitPoolManager = unitPoolManager
	_navigationService = navigationService
	_unitLifecycle = unitLifecycle


func Initialize(totalPopulation: int) -> bool:
	if totalPopulation < 0:
		return false

	_totalPopulation = totalPopulation
	return true


func GetDeploymentByCell(cell: Vector2i) -> DefenseDeploymentManager.DefenseDeployment:
	return _deploymentManager.GetDeploymentByCell(cell)


func GetTotalRecruitRatio() -> int:
	return _deploymentManager.GetTotalRecruitRatio()


func GetMaxRecruitRatioForCell(cell: Vector2i) -> int:
	return _deploymentManager.GetMaxRecruitRatioForCell(cell)


func GetTotalRecruitedPopulation() -> int:
	return _deploymentManager.CalculateTotalRecruitedPopulation(_totalPopulation)


func CalculateRecruitedPopulation(recruitRatio: int) -> int:
	return Math.ApplyRatio(_totalPopulation, recruitRatio)


func AddDeployment(
	cell: Vector2i,
	characterData: CharacterData,
	recruitRatio: int,
	position: Vector2,
) -> bool:
	if not _CanRecruitPopulation(recruitRatio):
		return false

	if characterData == null:
		return false

	if not _deploymentManager.AddDeployment(cell, characterData.characterKey, recruitRatio):
		return false

	var unit: Unit = _SpawnDeploymentUnit(characterData, position)
	if unit == null:
		_deploymentManager.RemoveDeployment(cell)
		return false

	_deploymentUnitsByCell[cell] = unit
	return true


func RemoveDeployment(cell: Vector2i) -> bool:
	var deployment: DefenseDeploymentManager.DefenseDeployment = _deploymentManager.GetDeploymentByCell(
		cell
	)
	if deployment == null:
		return false

	var unit: Unit = _deploymentUnitsByCell.get(cell)
	if unit == null:
		push_error("DefenseDeploymentController: 배치 데이터에 대응하는 Unit이 없습니다. cell: " + str(cell))
		return false

	if not _unitLifecycle.ReturnToPool(unit, _unitPoolManager):
		push_error("DefenseDeploymentController: 배치 Unit 반환에 실패했습니다. cell: " + str(cell))
		return false

	_deploymentManager.RemoveDeployment(cell)
	_deploymentUnitsByCell.erase(cell)
	return true


func UpdateDeployment(cell: Vector2i, characterData: CharacterData, recruitRatio: int) -> bool:
	if characterData == null or not _CanRecruitPopulation(recruitRatio):
		return false

	var deployment: DefenseDeploymentManager.DefenseDeployment = _deploymentManager.GetDeploymentByCell(
		cell
	)
	if deployment == null:
		return false

	if deployment.characterKey == characterData.characterKey:
		return _deploymentManager.UpdateDeployment(cell, characterData.characterKey, recruitRatio)

	return _ReplaceDeploymentUnit(cell, deployment, characterData, recruitRatio)


func PrepareUnitGroups() -> bool:
	_unitGroupManager.Clear()

	var cells: Array[Vector2i] = _deploymentManager.GetDeploymentCells()
	for cell: Vector2i in cells:
		var deployment: DefenseDeploymentManager.DefenseDeployment = _deploymentManager.GetDeploymentByCell(
			cell
		)
		if deployment == null:
			_RollbackUnitGroups()
			push_error("DefenseDeploymentController: 배치 정보를 찾을 수 없습니다. cell: " + str(cell))
			return false

		var characterData: CharacterData = GameDataManager.GetCharacterData(deployment.characterKey)
		if characterData == null:
			_RollbackUnitGroups()
			push_error(
				"DefenseDeploymentController: 존재하지 않는 characterKey입니다. key: "
				+ str(deployment.characterKey)
			)
			return false

		if not _unitGroupManager.AddUnitGroup(
			cell,
			characterData,
			deployment.recruitRatio,
			_totalPopulation,
		):
			_RollbackUnitGroups()
			push_error(
				"DefenseDeploymentController: UnitGroupStatus 생성에 실패했습니다. cell: " + str(cell)
			)
			return false

	if not _unitGroupManager.HasAliveUnitGroup():
		_RollbackUnitGroups()
		push_error("DefenseDeploymentController: 배치된 병력이 없습니다.")
		return false

	if not _ValidateDeploymentUnits(cells):
		_RollbackUnitGroups()
		return false

	return true


func BindPreparedUnits() -> bool:
	var cells: Array[Vector2i] = _deploymentManager.GetDeploymentCells()
	for cell: Vector2i in cells:
		var unit: Unit = _deploymentUnitsByCell.get(cell)
		if unit == null or not _unitGroupManager.BindUnit(cell, unit):
			push_error(
				"DefenseDeploymentController: UnitGroupStatus 연결에 실패했습니다. cell: " + str(cell)
			)
			return false

	return true


func RollbackBattlePreparation() -> void:
	_RollbackUnitGroups()


func CompleteDeployment() -> void:
	_deploymentUnitsByCell.clear()


func HasDeployment() -> bool:
	return _deploymentManager.GetTotalRecruitRatio() > 0


func _ReplaceDeploymentUnit(
	cell: Vector2i,
	deployment: DefenseDeploymentManager.DefenseDeployment,
	characterData: CharacterData,
	recruitRatio: int,
) -> bool:
	var unit: Unit = _deploymentUnitsByCell.get(cell)
	if unit == null:
		push_error("DefenseDeploymentController: 배치 데이터에 대응하는 Unit이 없습니다. cell: " + str(cell))
		return false

	var previousCharacterKey: int = deployment.characterKey
	var previousRecruitRatio: int = deployment.recruitRatio

	if not _deploymentManager.UpdateDeployment(cell, characterData.characterKey, recruitRatio):
		return false

	var newUnit: Unit = _SpawnDeploymentUnit(characterData, unit.position)
	if newUnit == null:
		_deploymentManager.UpdateDeployment(cell, previousCharacterKey, previousRecruitRatio)
		return false

	if not _unitLifecycle.ReturnToPool(unit, _unitPoolManager):
		if not _unitLifecycle.ReturnToPool(newUnit, _unitPoolManager):
			push_error("DefenseDeploymentController: 새 배치 Unit 롤백 반환에 실패했습니다. cell: " + str(cell))

		_deploymentManager.UpdateDeployment(cell, previousCharacterKey, previousRecruitRatio)
		push_error("DefenseDeploymentController: 기존 배치 Unit 반환에 실패했습니다. cell: " + str(cell))
		return false

	_deploymentUnitsByCell[cell] = newUnit
	return true


func _ValidateDeploymentUnits(cells: Array[Vector2i]) -> bool:
	for cell: Vector2i in cells:
		var unit: Unit = _deploymentUnitsByCell.get(cell)
		if unit == null or _unitGroupManager.GetUnitGroupStatusByCell(cell) == null:
			push_error(
				"DefenseDeploymentController: 배치 데이터와 UnitGroupStatus가 일치하지 않습니다. cell: "
				+ str(cell)
			)
			return false

	return true


func _RollbackUnitGroups() -> void:
	_unitGroupManager.Clear()


func _CanRecruitPopulation(recruitRatio: int) -> bool:
	return CalculateRecruitedPopulation(recruitRatio) > 0


func _SpawnDeploymentUnit(characterData: CharacterData, position: Vector2) -> Unit:
	if characterData == null:
		return null

	var unit: Unit = _unitPoolManager.SpawnUnit(characterData, position)
	if unit == null:
		return null

	if not _navigationService.CanPlaceStatic(position, unit.GetHalfSize()):
		_unitPoolManager.Return(unit)
		return null

	if not _unitLifecycle.RegisterUnit(unit):
		_unitPoolManager.Return(unit)
		return null

	return unit
