class_name DefenseMercenaryBuffService
extends RefCounted

var _deploymentManager: DefenseDeploymentManager
var _mercenaryAssignmentManager: DefenseMercenaryAssignmentManager
var _towerManager: DefenseTowerManager


func _init(
	deploymentManager: DefenseDeploymentManager,
	mercenaryAssignmentManager: DefenseMercenaryAssignmentManager,
	towerManager: DefenseTowerManager,
) -> void:
	_deploymentManager = deploymentManager
	_mercenaryAssignmentManager = mercenaryAssignmentManager
	_towerManager = towerManager


func Apply() -> bool:
	_towerManager.ClearStatBonuses()

	if not _ApplyTowerBuffs():
		return false

	return _ApplyCPBuffs()


func Clear() -> void:
	_towerManager.ClearStatBonuses()


func RemoveCPBuffs() -> bool:
	var mercenaryKey: int = _mercenaryAssignmentManager.GetCPMercenaryKey()
	if mercenaryKey < 0:
		return true

	var buffDataList: Array[MercenaryBuffData] = GameDataManager.GetMercenaryBuffData(mercenaryKey)
	for buffData: MercenaryBuffData in buffDataList:
		if not _towerManager.RemoveStatBonusFromAllTowers(
			buffData.statType,
			buffData.flatValue,
			buffData.ratioValue,
		):
			return false

	return true


func _ApplyTowerBuffs() -> bool:
	var cells: Array[Vector2i] = _deploymentManager.GetDeploymentCells()
	for cell: Vector2i in cells:
		var mercenaryKey: int = _mercenaryAssignmentManager.GetMercenaryKeyByUnitCell(cell)
		if mercenaryKey < 0:
			continue

		var buffDataList: Array[MercenaryBuffData] = GameDataManager.GetMercenaryBuffData(
			mercenaryKey
		)
		for buffData: MercenaryBuffData in buffDataList:
			if not _towerManager.AddStatBonusToTower(
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
		if not _towerManager.AddStatBonusToAllTowers(
			buffData.statType,
			buffData.flatValue,
			buffData.ratioValue,
		):
			return false

	return true
