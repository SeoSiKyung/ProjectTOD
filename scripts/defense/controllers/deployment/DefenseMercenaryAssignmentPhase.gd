class_name DefenseMercenaryAssignmentPhase
extends DefenseDeploymentPhaseHandler

var _selectedMercenaryKey: int = -1


func Enter() -> bool:
	_deploymentView.StopDrag()
	_deploymentView.ShowView()

	_selectedMercenaryKey = _deploymentView.SetMercenaryButtons(
		_startData.availableMercenaryKeys,
		_selectedMercenaryKey,
	)
	if _selectedMercenaryKey < 0:
		return false

	_deploymentView.ConfigureMercenaryPhase()

	_RefreshAssignmentUI()
	RefreshPlacementPreview()
	_deploymentGridView.queue_redraw()

	return true


func Confirm() -> bool:
	return _defenseSceneManager.ConfirmMercenaryAssignment()


func Place(cell: Vector2i) -> bool:
	if _selectedMercenaryKey < 0:
		return false

	var success: bool
	if cell == _cpCell:
		success = _defenseSceneManager.AssignMercenaryToCP(_selectedMercenaryKey)
	else:
		success = _defenseSceneManager.AssignMercenaryToUnit(_selectedMercenaryKey, cell)

	if not success:
		_deploymentView.SetStatusText("선택한 대상에 용병을 배치할 수 없습니다.")
		return false

	_RefreshAssignmentUI()
	return true


func Remove(cell: Vector2i) -> void:
	var mercenaryKey: int

	if cell == _cpCell:
		mercenaryKey = _defenseSceneManager.GetCPMercenaryKey()
	else:
		mercenaryKey = _defenseSceneManager.GetMercenaryKeyByUnitCell(cell)

	if mercenaryKey < 0:
		return

	if not _defenseSceneManager.UnassignMercenary(mercenaryKey):
		return

	_RefreshAssignmentUI()


func CanInteract(cell: Vector2i) -> bool:
	if cell == _cpCell:
		return true

	return _defenseSceneManager.GetDeploymentByCell(cell) != null


func CanPlace(cell: Vector2i) -> bool:
	return _selectedMercenaryKey >= 0 and CanInteract(cell)


func OnMercenarySelected(mercenaryKey: int) -> void:
	_selectedMercenaryKey = mercenaryKey

	_UpdateSelectedTargetFocus()
	RefreshPlacementPreview()


func RefreshPlacementPreview() -> void:
	var previewTexture: Texture2D
	if _selectedMercenaryKey >= 0:
		previewTexture = _deploymentView.GetMercenaryIconTexture(_selectedMercenaryKey)

	_deploymentGridView.SetPlacementPreview(previewTexture)


func _RefreshAssignmentUI() -> void:
	_RefreshAssignmentLabels()
	_UpdateButtonStates()
	_UpdateSummary()
	_UpdateSelectedTargetFocus()


func _RefreshAssignmentLabels() -> void:
	_deploymentInfoView.ClearMercenaries()

	for mercenaryKey: int in _startData.availableMercenaryKeys:
		var assignment: DefenseMercenaryAssignmentManager.DefenseMercenaryAssignment = _defenseSceneManager.GetMercenaryAssignment(
			mercenaryKey
		)
		if assignment == null:
			continue

		var mercenaryData: MercenaryData = GameDataManager.GetMercenaryData(mercenaryKey)
		if mercenaryData == null:
			continue

		var cell: Vector2i
		match assignment.targetType:
			DefenseMercenaryAssignmentManager.TargetType.UNIT_GROUP:
				cell = assignment.unitCell
			DefenseMercenaryAssignmentManager.TargetType.CP:
				cell = _cpCell
			_:
				continue

		_deploymentInfoView.SetMercenary(cell, mercenaryData)


func _UpdateSelectedTargetFocus() -> void:
	_deploymentInfoView.ClearMercenaryHighlights()

	if _selectedMercenaryKey < 0:
		_deploymentGridView.ClearFocusedCell()
		return

	var assignment: DefenseMercenaryAssignmentManager.DefenseMercenaryAssignment = _defenseSceneManager.GetMercenaryAssignment(
		_selectedMercenaryKey
	)
	if assignment == null:
		_deploymentGridView.ClearFocusedCell()
		return

	var targetCell: Vector2i
	match assignment.targetType:
		DefenseMercenaryAssignmentManager.TargetType.UNIT_GROUP:
			targetCell = assignment.unitCell
		DefenseMercenaryAssignmentManager.TargetType.CP:
			targetCell = _cpCell
		_:
			_deploymentGridView.ClearFocusedCell()
			return

	_deploymentGridView.SetFocusedCell(targetCell)
	_deploymentInfoView.SetMercenaryHighlight(targetCell, true)


func _UpdateButtonStates() -> void:
	for mercenaryKey: int in _startData.availableMercenaryKeys:
		_deploymentView.SetMercenaryAssigned(
			mercenaryKey,
			_defenseSceneManager.IsMercenaryAssigned(mercenaryKey),
		)


func _UpdateSummary() -> void:
	var heroAssigned: bool = false
	for mercenaryKey: int in _startData.availableMercenaryKeys:
		var data: MercenaryData = GameDataManager.GetMercenaryData(mercenaryKey)
		if data == null or not data.isHero:
			continue

		heroAssigned = _defenseSceneManager.IsMercenaryAssigned(mercenaryKey)
		break

	var cpAssigned: bool = _defenseSceneManager.GetCPMercenaryKey() >= 0
	_deploymentView.UpdateMercenaryInfo(
		heroAssigned,
		cpAssigned,
		_defenseSceneManager.CanConfirmMercenaryAssignment(),
	)
