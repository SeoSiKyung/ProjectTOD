class_name ConstructionSystem
extends Node

signal ConstructionCompleted(facility_id: StringName, level: int)

signal UpgradeCompleted(facility_id: StringName, level: int)


func ProcessTurnStart(settlement: SettlementState) -> void:
	# 뒤에서부터 순회해야 완료된 Task를 안전하게 제거할 수 있음
	for i in range(settlement.constructionTasks.size() - 1, -1, -1):
		var task := settlement.constructionTasks[i]

		task.AdvanceTurn()

		if task.IsCompleted():
			CompleteTask(settlement, task)

			settlement.constructionTasks.remove_at(i)


func CompleteTask(settlement: SettlementState, task: ConstructionTask) -> void:
	var facility_state := settlement.GetFacility(task.facilityId)

	if facility_state == null:
		push_warning("ConstructionSystem: FacilityState를 찾을 수 없습니다: %s" % task.facilityId)
		return

	facility_state.level = task.targetLevel
	facility_state.status = FacilityState.Status.BUILT

	match task.taskType:
		ConstructionTask.TaskType.BUILD:
			ConstructionCompleted.emit(task.facilityId, task.targetLevel)

		ConstructionTask.TaskType.UPGRADE:
			UpgradeCompleted.emit(task.facilityId, task.targetLevel)
