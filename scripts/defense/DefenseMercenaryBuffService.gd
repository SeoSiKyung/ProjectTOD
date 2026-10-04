class_name DefenseMercenaryBuffService
extends RefCounted

var _deploymentManager: DefenseDeploymentManager
var _mercenaryAssignmentManager: DefenseMercenaryAssignmentManager
var _unitGroupManager: DefenseUnitGroupManager


func _init(
	deploymentManager: DefenseDeploymentManager,
	mercenaryAssignmentManager: DefenseMercenaryAssignmentManager,
	unitGroupManager: DefenseUnitGroupManager,
) -> void:
	_deploymentManager = deploymentManager
	_mercenaryAssignmentManager = mercenaryAssignmentManager
	_unitGroupManager = unitGroupManager


func Apply() -> bool:
	_unitGroupManager.ClearStatBonuses()

	if not _ApplyUnitGroupBuffs():
		return false

	return _ApplyCPBuffs()


func Clear() -> void:
	_unitGroupManager.ClearStatBonuses()


func RemoveCPBuffs() -> bool:
	var mercenaryKey: int = _mercenaryAssignmentManager.GetCPMercenaryKey()
	if mercenaryKey < 0:
		return true

	var buffDataList: Array[MercenaryBuffData] = GameDataManager.GetMercenaryBuffData(mercenaryKey)
	for buffData: MercenaryBuffData in buffDataList:
		if not _unitGroupManager.RemoveStatBonusFromAllUnitGroups(
			buffData.statType,
			buffData.flatValue,
			buffData.ratioValue,
		):
			return false

	return true


func _ApplyUnitGroupBuffs() -> bool:
	var cells: Array[Vector2i] = _deploymentManager.GetDeploymentCells()
	for cell: Vector2i in cells:
		var mercenaryKey: int = _mercenaryAssignmentManager.GetMercenaryKeyByUnitCell(cell)
		if mercenaryKey < 0:
			continue

		var buffDataList: Array[MercenaryBuffData] = GameDataManager.GetMercenaryBuffData(
			mercenaryKey
		)
		for buffData: MercenaryBuffData in buffDataList:
			if not _unitGroupManager.AddStatBonusToUnitGroup(
				cell,
				buffData.statType,
				buffData.flatValue,
				buffData.ratioValue,
			):
				return false

	return true


func _ApplyCPBuffs() -> bool:
	var mercenaryKey: int = _mercenaryAssignmentManager.GetCPMercenaryKey()
	if mercenaryKey < 0:
		return true

	var buffDataList: Array[MercenaryBuffData] = GameDataManager.GetMercenaryBuffData(mercenaryKey)
	for buffData: MercenaryBuffData in buffDataList:
		if not _unitGroupManager.AddStatBonusToAllUnitGroups(
			buffData.statType,
			buffData.flatValue,
			buffData.ratioValue,
		):
			return false

	return true
