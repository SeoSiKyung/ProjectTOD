class_name ConstructionSystem
extends Node


signal construction_completed(
	facility_id: StringName,
	level: int
)

signal upgrade_completed(
	facility_id: StringName,
	level: int
)


func process_turn_start(settlement: SettlementState) -> void:
	# 뒤에서부터 순회해야 완료된 Task를 안전하게 제거할 수 있음
	for i in range(
		settlement.construction_tasks.size() - 1,
		-1,
		-1
	):
		var task := settlement.construction_tasks[i]

		task.advance_turn()

		if task.is_completed():
			_complete_task(
				settlement,
				task
			)

			settlement.construction_tasks.remove_at(i)


func _complete_task(
	settlement: SettlementState,
	task: ConstructionTask
) -> void:

	var facility_state := settlement.get_facility(
		task.facility_id
	)

	if facility_state == null:
		push_warning(
			"ConstructionSystem: FacilityState를 찾을 수 없습니다: %s"
			% task.facility_id
		)
		return


	facility_state.level = task.target_level
	facility_state.status = FacilityState.Status.BUILT


	match task.task_type:

		ConstructionTask.TaskType.BUILD:
			construction_completed.emit(
				task.facility_id,
				task.target_level
			)

		ConstructionTask.TaskType.UPGRADE:
			upgrade_completed.emit(
				task.facility_id,
				task.target_level
			)