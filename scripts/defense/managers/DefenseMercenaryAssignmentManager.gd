class_name DefenseMercenaryAssignmentManager
extends RefCounted

enum TargetType {
	UNIT_GROUP,
	CP,
}


class DefenseMercenaryAssignment:
	var mercenaryKey: int
	var targetType: TargetType
	var unitCell: Vector2i


	func _init(
		pMercenaryKey: int,
		pTargetType: TargetType,
		pUnitCell: Vector2i = Vector2i(-1, -1),
	) -> void:
		mercenaryKey = pMercenaryKey
		targetType = pTargetType
		unitCell = pUnitCell


var _unitDeploymentManager: DefenseDeploymentManager

var _availableMercenaryKeys: Dictionary[int, bool] = { }

# mercenaryKey -> Assignment
var _assignmentByMercenaryKey: Dictionary[int, DefenseMercenaryAssignment] = { }

# 부대 Cell -> mercenaryKey
var _mercenaryKeyByUnitCell: Dictionary[Vector2i, int] = { }

var _cpMercenaryKey: int = -1


func _init(unitDeploymentManager: DefenseDeploymentManager) -> void:
	_unitDeploymentManager = unitDeploymentManager


func Initialize(availableMercenaryKeys: Array[int]) -> bool:
	_availableMercenaryKeys.clear()
	_assignmentByMercenaryKey.clear()
	_mercenaryKeyByUnitCell.clear()
	_cpMercenaryKey = -1

	for mercenaryKey: int in availableMercenaryKeys:
		var mercenaryData: MercenaryData = GameDataManager.GetMercenaryData(mercenaryKey)
		if mercenaryData == null:
			push_error(
				"DefenseMercenaryAssignmentManager: MercenaryData가 없습니다. key: " + str(mercenaryKey)
			)
			return false

		if _availableMercenaryKeys.has(mercenaryKey):
			push_error("DefenseMercenaryAssignmentManager: 중복 용병 Key입니다. key: " + str(mercenaryKey))
			return false

		_availableMercenaryKeys[mercenaryKey] = true

	return true


func GetAssignment(mercenaryKey: int) -> DefenseMercenaryAssignment:
	return _assignmentByMercenaryKey.get(mercenaryKey)


func GetMercenaryKeyByUnitCell(cell: Vector2i) -> int:
	return _mercenaryKeyByUnitCell.get(cell, -1)


func GetCPMercenaryKey() -> int:
	return _cpMercenaryKey


func IsAssigned(mercenaryKey: int) -> bool:
	return _assignmentByMercenaryKey.has(mercenaryKey)


func AssignToUnit(mercenaryKey: int, cell: Vector2i) -> bool:
	if not _availableMercenaryKeys.has(mercenaryKey):
		return false

	if _unitDeploymentManager.GetDeploymentByCell(cell) == null:
		return false

	var occupiedMercenaryKey: int = _mercenaryKeyByUnitCell.get(cell, -1)
	if occupiedMercenaryKey >= 0 and occupiedMercenaryKey != mercenaryKey:
		_UnassignInternal(occupiedMercenaryKey)

	_UnassignInternal(mercenaryKey)

	_assignmentByMercenaryKey[mercenaryKey] = DefenseMercenaryAssignment.new(
		mercenaryKey,
		TargetType.UNIT_GROUP,
		cell,
	)

	_mercenaryKeyByUnitCell[cell] = mercenaryKey

	return true


func AssignToCP(mercenaryKey: int) -> bool:
	if not _availableMercenaryKeys.has(mercenaryKey):
		return false

	var mercenaryData: MercenaryData = GameDataManager.GetMercenaryData(mercenaryKey)
	if mercenaryData == null:
		return false

	if _cpMercenaryKey >= 0 and _cpMercenaryKey != mercenaryKey:
		_UnassignInternal(_cpMercenaryKey)

	_UnassignInternal(mercenaryKey)

	_assignmentByMercenaryKey[mercenaryKey] = DefenseMercenaryAssignment.new(
		mercenaryKey,
		TargetType.CP,
	)

	_cpMercenaryKey = mercenaryKey

	return true


func Unassign(mercenaryKey: int) -> bool:
	if not _assignmentByMercenaryKey.has(mercenaryKey):
		return false

	_UnassignInternal(mercenaryKey)
	return true


func CanConfirmAssignment() -> bool:
	if _cpMercenaryKey < 0:
		return false

	return GetHeroAssignment() != null


func GetHeroAssignment() -> DefenseMercenaryAssignment:
	for mercenaryKey: int in _assignmentByMercenaryKey:
		var mercenaryData: MercenaryData = GameDataManager.GetMercenaryData(mercenaryKey)
		if mercenaryData == null:
			continue

		if not mercenaryData.isHero:
			continue

		return _assignmentByMercenaryKey[mercenaryKey]

	return null


func _UnassignInternal(mercenaryKey: int) -> void:
	var assignment: DefenseMercenaryAssignment = _assignmentByMercenaryKey.get(mercenaryKey)
	if assignment == null:
		return

	match assignment.targetType:
		TargetType.UNIT_GROUP:
			_mercenaryKeyByUnitCell.erase(assignment.unitCell)

		TargetType.CP:
			if _cpMercenaryKey == mercenaryKey:
				_cpMercenaryKey = -1

	_assignmentByMercenaryKey.erase(mercenaryKey)
