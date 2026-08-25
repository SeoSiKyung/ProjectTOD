class_name ConstructionTask
extends RefCounted


enum TaskType {
	BUILD,
	UPGRADE
}


var facility_id: StringName = &""
var task_type: TaskType = TaskType.BUILD

var target_level: int = 1
var remaining_turns: int = 0


func _init(
	p_facility_id: StringName = &"",
	p_task_type: TaskType = TaskType.BUILD,
	p_target_level: int = 1,
	p_remaining_turns: int = 0
):
	facility_id = p_facility_id
	task_type = p_task_type
	target_level = p_target_level
	remaining_turns = p_remaining_turns


func advance_turn() -> void:
	if remaining_turns > 0:
		remaining_turns -= 1


func is_completed() -> bool:
	return remaining_turns <= 0
