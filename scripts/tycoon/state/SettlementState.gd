class_name SettlementState
extends RefCounted

# =========================================================
# 자원
# =========================================================

var gold: int = 0
var food: int = 0
var wood: int = 0
var stone: int = 0
var iron: int = 0
var magicStone: int = 0

# =========================================================
# 마을 상태
# =========================================================

var population: int = 0
var stability: int = 100

# =========================================================
# 시설
# =========================================================

var facilities: Array[FacilityState] = []

var constructionTasks: Array[ConstructionTask] = []

# =========================================================
# 시설 검색
# =========================================================


func GetFacility(facilityId: StringName) -> FacilityState:
	for facility in facilities:
		if facility.facilityId == facilityId:
			return facility

	return null


func HasFacility(facilityId: StringName) -> bool:
	var facility := GetFacility(facilityId)

	if facility == null:
		return false

	return facility.IsBuilt()


func IsFacilityUnderConstruction(facilityId: StringName) -> bool:
	var facility := GetFacility(facilityId)

	if facility == null:
		return false

	return facility.IsUnderConstruction()

# =========================================================
# 건설 작업 검색
# =========================================================


func GetConstructionTask(facilityId: StringName) -> ConstructionTask:
	for task in constructionTasks:
		if task.facilityId == facilityId:
			return task

	return null
