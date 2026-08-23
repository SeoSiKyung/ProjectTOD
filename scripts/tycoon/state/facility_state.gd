class_name FacilityState
extends RefCounted


enum Status {
	AVAILABLE,
	CONSTRUCTING,
	BUILT,
	UPGRADING
}


var facility_id: StringName = &""
var level: int = 0
var status: Status = Status.AVAILABLE


func _init(
	p_facility_id: StringName = &"",
	p_level: int = 0,
	p_status: Status = Status.AVAILABLE
):
	facility_id = p_facility_id
	level = p_level
	status = p_status


func is_built() -> bool:
	return level > 0


func is_under_construction() -> bool:
	return (
		status == Status.CONSTRUCTING
		or status == Status.UPGRADING
	)
