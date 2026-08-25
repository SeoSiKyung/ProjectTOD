class_name FacilityState
extends RefCounted


enum Status {
	AVAILABLE,
	CONSTRUCTING,
	BUILT,
	UPGRADING
}


var facility_id: StringName = &""

# 레벨이 있는 시설에서만 의미가 있음.
# 기본/기능 시설은 0 유지.
var level: int = 0

var status: Status = Status.AVAILABLE


func _init(
	p_facility_id: StringName = &"",
	p_level: int = 0,
	p_status: Status = Status.AVAILABLE
) -> void:

	facility_id = p_facility_id
	level = p_level
	status = p_status


func is_built() -> bool:
	return (
		status == Status.BUILT
		or status == Status.UPGRADING
	)


func is_under_construction() -> bool:
	return (
		status == Status.CONSTRUCTING
		or status == Status.UPGRADING
	)
