class_name SettlementState
extends RefCounted


# =========================================================
# 진행 상태
# =========================================================

var cycle: int = 1

# 현재 사이클 안에서의 턴
var current_turn: int = 0

# 이번 사이클의 총 턴 수
# 사이클마다 달라질 수 있음
var cycle_turn_limit: int = 10


# =========================================================
# 자원
# =========================================================

var gold: int = 0
var food: int = 0
var wood: int = 0
var stone: int = 0
var iron: int = 0
var magic_stone: int = 0


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
var construction_tasks: Array[ConstructionTask] = []


# =========================================================
# 스토리 / 이벤트
# =========================================================

# 예:
# story_flags["met_blacksmith"] = true
var story_flags: Dictionary = {}

# 획득한 정보
# 예:
# "arden_record_01"
var collected_intel: Array[StringName] = []

# 오펜스 도중 발생했지만
# 아직 플레이어에게 보여주지 않은 이벤트
var pending_events: Array[StringName] = []


# =========================================================
# 턴
# =========================================================

func get_remaining_turns() -> int:
	return max(cycle_turn_limit - current_turn, 0)


func is_cycle_finished() -> bool:
	return current_turn >= cycle_turn_limit


# =========================================================
# 시설 검색
# =========================================================

func get_facility(facility_id: StringName) -> FacilityState:
	for facility in facilities:
		if facility.facility_id == facility_id:
			return facility

	return null


func has_facility(facility_id: StringName) -> bool:
	var facility := get_facility(facility_id)

	if facility == null:
		return false

	return facility.is_built()


func is_facility_under_construction(
	facility_id: StringName
) -> bool:
	var facility := get_facility(facility_id)

	if facility == null:
		return false

	return facility.is_under_construction()


# =========================================================
# 건설 작업 검색
# =========================================================

func get_construction_task(
	facility_id: StringName
) -> ConstructionTask:

	for task in construction_tasks:
		if task.facility_id == facility_id:
			return task

	return null


# =========================================================
# 스토리
# =========================================================

func has_story_flag(flag: StringName) -> bool:
	return story_flags.get(flag, false)


func set_story_flag(
	flag: StringName,
	value: bool = true
) -> void:
	story_flags[flag] = value


func has_intel(intel_id: StringName) -> bool:
	return collected_intel.has(intel_id)


func add_intel(intel_id: StringName) -> void:
	if not collected_intel.has(intel_id):
		collected_intel.append(intel_id)


# =========================================================
# 이벤트
# =========================================================

func add_pending_event(event_id: StringName) -> void:
	if not pending_events.has(event_id):
		pending_events.append(event_id)


func pop_pending_event() -> StringName:
	if pending_events.is_empty():
		return &""

	return pending_events.pop_front()
