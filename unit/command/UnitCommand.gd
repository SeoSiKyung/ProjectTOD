class_name UnitCommand
extends RefCounted

const INVALID_COMMAND_ID: int = -1

var commandId: int = INVALID_COMMAND_ID
var unitIds: PackedInt32Array = []


func _init(pUnitIds: PackedInt32Array) -> void:
	unitIds = _normalizeUnitIds(pUnitIds)


func _normalizeUnitIds(sourceUnitIds: PackedInt32Array) -> PackedInt32Array:
	var sortedUnitIds: PackedInt32Array = sourceUnitIds.duplicate()
	var normalizedUnitIds: PackedInt32Array = []
	var previousUnitId: int = -1
	var foundInvalidUnitId: bool = false

	sortedUnitIds.sort()

	for unitId: int in sortedUnitIds:
		if unitId < 0:
			foundInvalidUnitId = true
			continue

		if unitId == previousUnitId:
			continue

		normalizedUnitIds.append(unitId)
		previousUnitId = unitId

	if foundInvalidUnitId:
		push_error("UnitCommand에서 유효하지 않은 unitId를 제외했습니다.")

	return normalizedUnitIds
