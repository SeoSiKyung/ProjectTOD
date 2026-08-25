class_name SettlementState
extends RefCounted

# =========================================================
# 진행 상태
# =========================================================

var cycle: int = 1

# 현재 사이클 안에서의 턴
var currentTurn: int = 0

# 이번 사이클의 총 턴 수
# 사이클마다 달라질 수 있음
var cycleTurnLimit: int = 10

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

# 현재 존재하는 시설들의 상태
var facilities: Array[FacilityState] = []

# 현재 진행 중인 건설 / 업그레이드
var constructionTasks: Array[ConstructionTask] = []


# =========================================================
# 스토리 / 이벤트
# =========================================================

# 예:
# storyFlags["met_blacksmith"] = true
var storyFlags: Dictionary = { }

# 획득한 정보
# 예:
# "arden_record_01"
var collectedIntel: Array[StringName] = []

# 오펜스 도중 발생했지만
# 아직 플레이어에게 보여주지 않은 이벤트
var pendingEvents: Array[StringName] = []

# =========================================================
# 턴
# =========================================================


func GetRemainingTurns() -> int:
	return max(cycleTurnLimit - currentTurn, 0)


func IsCycleFinished() -> bool:
	return currentTurn >= cycleTurnLimit

# =========================================================
# 시설 검색
# =========================================================


func GetFacility(facility_id: StringName) -> FacilityState:
	for facility in facilities:
		if facility.facilityId == facility_id:
			return facility

	return null


func HasFacility(facility_id: StringName) -> bool:
	var facility := GetFacility(facility_id)

	if facility == null:
		return false

	return facility.IsBuilt()


func IsFacilityUnderConstruction(facility_id: StringName) -> bool:
	var facility := GetFacility(facility_id)

	if facility == null:
		return false

	return facility.IsUnderConstruction()

# =========================================================
# 건설 작업 검색
# =========================================================


func GetConstructionTask(facility_id: StringName) -> ConstructionTask:
	for task in constructionTasks:
		if task.facilityId == facility_id:
			return task

	return null

# =========================================================
# 스토리
# =========================================================


func HasStoryFlag(flag: StringName) -> bool:
	return storyFlags.get(flag, false)


func SetStoryFlag(flag: StringName, value: bool = true) -> void:
	storyFlags[flag] = value


func HasIntel(intel_id: StringName) -> bool:
	return collectedIntel.has(intel_id)


func AddIntel(intel_id: StringName) -> void:
	if not collectedIntel.has(intel_id):
		collectedIntel.append(intel_id)

# =========================================================
# 이벤트
# =========================================================


func AddPendingEvent(event_id: StringName) -> void:
	if not pendingEvents.has(event_id):
		pendingEvents.append(event_id)


func PopPendingEvent() -> StringName:
	if pendingEvents.is_empty():
		return &""

	return pendingEvents.pop_front()
