class_name DefenseTowerDeploymentPhase
extends DefenseDeploymentPhaseHandler

var _selectedCharacterKey: int = -1
var _selectedRecruitRatio: int = 0


func Enter() -> bool:
	_deploymentView.StopDrag()
	_deploymentView.ShowView()
	_deploymentInfoView.ClearMercenaries()

	var unitDataList: Array[CharacterData] = GameDataManager.GetCharacterDataByType(
		CharacterData.CharacterType.TOWER
	)
	if unitDataList.is_empty():
		push_error("DefenseTowerDeploymentPhase: 배치 가능한 TOWER 데이터가 없습니다.")
		return false

	_selectedCharacterKey = _deploymentView.SetCharacterButtons(unitDataList, _selectedCharacterKey)

	_deploymentView.ConfigureUnitPhase(
		Math.RatioToPercent(_defenseSceneManager.GetMaxRecruitRatio()),
		Math.RatioToPercent(_selectedRecruitRatio),
	)

	_RefreshDeploymentInfo()
	RefreshPlacementPreview()
	_deploymentGridView.queue_redraw()

	return true


func Confirm() -> bool:
	return _defenseSceneManager.ConfirmDeployment()


func Place(cell: Vector2i) -> bool:
	if _selectedCharacterKey < 0:
		return false

	if _selectedRecruitRatio <= 0:
		_deploymentView.SetStatusText("배치 병력을 1% 이상 설정하세요.")
		return false

	var maxRecruitRatio: int = _defenseSceneManager.GetMaxRecruitRatioForCell(cell)
	if _selectedRecruitRatio > maxRecruitRatio:
		_deploymentView.SetStatusText(
			"남은 징집률이 부족합니다.\n"
			+ "이 셀에는 최대 %d%%까지 배치할 수 있습니다." % Math.RatioToPercent(maxRecruitRatio)
		)
		return false

	var success: bool

	var deployment: DefenseDeploymentManager.DefenseDeployment = _defenseSceneManager.GetDeploymentByCell(
		cell
	)
	if deployment == null:
		var spawnPosition: Vector2 = _deploymentGrid.CellToWorldCenter(cell)
		success = _defenseSceneManager.AddDeployment(
			cell,
			_selectedCharacterKey,
			_selectedRecruitRatio,
			spawnPosition,
		)
	else:
		success = _defenseSceneManager.UpdateDeployment(
			cell,
			_selectedCharacterKey,
			_selectedRecruitRatio,
		)

	if not success:
		_deploymentView.SetStatusText("해당 셀에 병력을 배치할 수 없습니다.")
		return false

	_deploymentInfoView.SetRecruitRatio(cell, _selectedRecruitRatio)

	_RefreshDeploymentInfo()

	return true


func Remove(cell: Vector2i) -> void:
	if not _defenseSceneManager.RemoveDeployment(cell):
		return

	_deploymentInfoView.RemoveRecruitRatio(cell)
	_RefreshDeploymentInfo()


func CanInteract(cell: Vector2i) -> bool:
	if cell == _cpCell:
		return false

	if _defenseSceneManager.GetInstallableDeploymentByCell(cell) != null:
		return false

	if _defenseSceneManager.GetDeploymentByCell(cell) != null:
		return true

	return _CanPlaceStaticAtCell(cell)


func CanPlace(cell: Vector2i) -> bool:
	if not CanInteract(cell):
		return false

	return (
		_selectedCharacterKey >= 0 and _selectedRecruitRatio > 0
		and _selectedRecruitRatio <= _defenseSceneManager.GetMaxRecruitRatioForCell(cell)
	)


func OnCharacterSelected(characterKey: int) -> void:
	_selectedCharacterKey = characterKey

	RefreshPlacementPreview()


func OnRecruitRatioChanged(value: float) -> void:
	_selectedRecruitRatio = Math.PercentToRatio(int(value))

	_RefreshDeploymentInfo()
	RefreshPlacementPreview()


func RefreshPlacementPreview() -> void:
	var previewTexture: Texture2D
	if _selectedCharacterKey >= 0 and _selectedRecruitRatio > 0:
		previewTexture = _deploymentView.GetCharacterIconTexture(_selectedCharacterKey)

	_deploymentGridView.SetPlacementPreview(previewTexture)


func _RefreshDeploymentInfo() -> void:
	var totalRecruitRatio: int = _defenseSceneManager.GetTotalRecruitRatio()
	var maxRecruitRatio: int = _defenseSceneManager.GetMaxRecruitRatio()

	var recruitedPopulation: int = _defenseSceneManager.GetTotalRecruitedPopulation()

	var selectedPopulation: int = _defenseSceneManager.CalculateRecruitedPopulation(
		_selectedRecruitRatio
	)

	var remainingRatio: int = maxRecruitRatio - totalRecruitRatio

	_deploymentView.UpdateUnitInfo(
		Math.RatioToPercent(totalRecruitRatio),
		Math.RatioToPercent(maxRecruitRatio),
		recruitedPopulation,
		_startData.population,
		Math.RatioToPercent(_selectedRecruitRatio),
		selectedPopulation,
		Math.RatioToPercent(remainingRatio),
	)
