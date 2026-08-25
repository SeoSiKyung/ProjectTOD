class_name FacilityState
extends RefCounted

enum Status {
	AVAILABLE,
	CONSTRUCTING,
	BUILT,
	UPGRADING,
}

var facilityId: StringName = &""

# 레벨이 있는 시설에서만 의미가 있음.
# 기본/기능 시설은 0 유지.
var level: int = 0

var status: Status = Status.AVAILABLE


func _init(pFacilityId: StringName = &"", pLevel: int = 0, pStatus: Status = Status.AVAILABLE) -> void:
	facilityId = pFacilityId
	level = pLevel
	status = pStatus


func IsBuilt() -> bool:
	return (status == Status.BUILT or status == Status.UPGRADING)


func IsUnderConstruction() -> bool:
	return (status == Status.CONSTRUCTING or status == Status.UPGRADING)
