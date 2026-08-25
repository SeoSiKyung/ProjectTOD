class_name ConstructionSystem
extends Node

signal ConstructionCompleted(facilityId: StringName, level: int)

signal UpgradeCompleted(facilityId: StringName, level: int)


func ProcessTurnStart(settlement: SettlementState) -> void:
	# 뒤에서부터 순회해야 완료된 Task를 안전하게 제거할 수 있음
	for i in range(settlement.constructionTasks.size() - 1, -1, -1):
		var task := settlement.constructionTasks[i]

		task.AdvanceTurn()

		if task.IsCompleted():
			_CompleteTask(settlement, task)

			settlement.constructionTasks.remove_at(i)


func _CompleteTask(settlement: SettlementState, task: ConstructionTask) -> void:
	var facilityState := settlement.GetFacility(task.facilityId)

	if facilityState == null:
		push_warning("ConstructionSystem: FacilityState를 찾을 수 없습니다: %s" % task.facilityId)
		return

	facilityState.level = task.targetLevel
	facilityState.status = FacilityState.Status.BUILT

	match task.taskType:
		ConstructionTask.TaskType.BUILD:
			ConstructionCompleted.emit(task.facilityId, task.targetLevel)

		ConstructionTask.TaskType.UPGRADE:
			UpgradeCompleted.emit(task.facilityId, task.targetLevel)
