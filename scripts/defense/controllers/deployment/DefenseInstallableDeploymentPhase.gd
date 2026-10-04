class_name DefenseInstallableDeploymentPhase
extends DefenseDeploymentPhaseHandler

var _selectedCharacterKey: int = -1
var _installableCharacterKeys: Array[int] = []


func Enter() -> bool:
	_deploymentView.StopDrag()
	_deploymentView.ShowView()
	_deploymentInfoView.ClearMercenaries()

	var installableDataList: Array[CharacterData] = []
	var sourceDataList: Array[CharacterData] = []

	sourceDataList.append_array(
		GameDataManager.GetCharacterDataByType(CharacterData.CharacterType.MACHINE)
	)
	sourceDataList.append_array(
		GameDataManager.GetCharacterDataByType(CharacterData.CharacterType.TRAP)
	)

	_installableCharacterKeys.clear()

	for characterData: CharacterData in sourceDataList:
		if _defenseSceneManager.GetInstallableAvailableCount(characterData.characterKey) <= 0:
			continue

		installableDataList.append(characterData)
		_installableCharacterKeys.append(characterData.characterKey)

	_selectedCharacterKey = _deploymentView.SetCharacterButtons(
		installableDataList,
		_selectedCharacterKey,
	)

	_deploymentView.ConfigureInstallablePhase()

	_UpdateButtonStates()
	_RefreshInfo()
	RefreshPlacementPreview()
	_deploymentGridView.queue_redraw()

	return true


func Confirm() -> bool:
	return _defenseSceneManager.ConfirmInstallableDeployment()


func Place(cell: Vector2i) -> bool:
	if _selectedCharacterKey < 0:
		_deploymentView.SetStatusText("배치 가능한 병기/함정이 없습니다.")
		return false

	if _defenseSceneManager.GetInstallableRemainingCount(_selectedCharacterKey) <= 0:
		_UpdateButtonStates()
		RefreshPlacementPreview()
		return false

	var success: bool

	var deployment: DefenseInstallableDeploymentManager.DefenseInstallableDeployment = _defenseSceneManager.GetInstallableDeploymentByCell(
		cell
	)
	if deployment == null:
		var position: Vector2 = _deploymentGrid.CellToWorldCenter(cell)
		success = _defenseSceneManager.AddInstallableDeployment(
			cell,
			_selectedCharacterKey,
			position,
		)
	else:
		success = _defenseSceneManager.UpdateInstallableDeployment(cell, _selectedCharacterKey)

	if not success:
		_deploymentView.SetStatusText("해당 셀에 병기/함정을 배치할 수 없습니다.")
		return false

	_UpdateButtonStates()
	_RefreshInfo()
	RefreshPlacementPreview()

	return true


func Remove(cell: Vector2i) -> void:
	if not _defenseSceneManager.RemoveInstallableDeployment(cell):
		return

	_UpdateButtonStates()
	_RefreshInfo()
	RefreshPlacementPreview()


func CanInteract(cell: Vector2i) -> bool:
	if cell == _cpCell:
		return false

	if _defenseSceneManager.GetInstallableDeploymentByCell(cell) != null:
		return true

	if _defenseSceneManager.GetDeploymentByCell(cell) != null:
		return false

	return _CanPlaceStaticAtCell(cell)


func CanPlace(cell: Vector2i) -> bool:
	if not CanInteract(cell):
		return false

	return (
		_selectedCharacterKey >= 0
		and _defenseSceneManager.GetInstallableRemainingCount(_selectedCharacterKey) > 0
	)


func OnCharacterSelected(characterKey: int) -> void:
	_selectedCharacterKey = characterKey
	RefreshPlacementPreview()


func RefreshPlacementPreview() -> void:
	var previewTexture: Texture2D

	if (
		_selectedCharacterKey >= 0
		and _defenseSceneManager.GetInstallableRemainingCount(_selectedCharacterKey) > 0
	):
		previewTexture = _deploymentView.GetCharacterIconTexture(_selectedCharacterKey)

	_deploymentGridView.SetPlacementPreview(previewTexture)


func _UpdateButtonStates() -> void:
	var remainingCountByCharacterKey: Dictionary[int, int] = { }
	for characterKey: int in _installableCharacterKeys:
		remainingCountByCharacterKey[characterKey] = _defenseSceneManager.GetInstallableRemainingCount(
			characterKey
		)

	_selectedCharacterKey = _deploymentView.UpdateInstallableButtonStates(
		remainingCountByCharacterKey,
		_selectedCharacterKey,
	)


func _RefreshInfo() -> void:
	var machineCount: int = 0
	var trapCount: int = 0

	for characterData: CharacterData in (
		GameDataManager.GetCharacterDataByType(CharacterData.CharacterType.MACHINE)
	):
		machineCount += _defenseSceneManager.GetInstallableDeployedCount(characterData.characterKey)

	for characterData: CharacterData in (
		GameDataManager.GetCharacterDataByType(CharacterData.CharacterType.TRAP)
	):
		trapCount += _defenseSceneManager.GetInstallableDeployedCount(characterData.characterKey)

	_deploymentView.UpdateInstallableInfo(machineCount, trapCount)
