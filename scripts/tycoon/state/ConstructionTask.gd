class_name ConstructionTask
extends RefCounted

enum TaskType {
	BUILD,
	UPGRADE,
}

var facilityId: StringName = &""
var taskType: TaskType = TaskType.BUILD

var targetLevel: int = 1
var remainingTurns: int = 0


func _init(
	pFacilityId: StringName = &"",
	pTaskType: TaskType = TaskType.BUILD,
	pTargetLevel: int = 1,
	pRemainingTurns: int = 0,
):
	facilityId = pFacilityId
	taskType = pTaskType
	targetLevel = pTargetLevel
	remainingTurns = pRemainingTurns


func AdvanceTurn() -> void:
	if remainingTurns > 0:
		remainingTurns -= 1


func IsCompleted() -> bool:
	return remainingTurns <= 0
