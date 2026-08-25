class_name FacilitySystem
extends Node


signal construction_started(facility_id: StringName)
signal upgrade_started(facility_id: StringName)


var facility_catalog: FacilityCatalog


func setup(p_facility_catalog: FacilityCatalog) -> void:
	facility_catalog = p_facility_catalog


# =========================================================
# 건설
# =========================================================

func request_build(
	settlement: SettlementState,
	facility_id: StringName
) -> bool:

	if facility_catalog == null:
		push_error("FacilitySystem: FacilityCatalog이 설정되지 않았습니다.")
		return false


	var facility_data := facility_catalog.get_facility_data(
		facility_id
	)

	if facility_data == null:
		push_warning(
			"FacilitySystem: 시설 데이터를 찾을 수 없습니다: %s"
			% facility_id
		)
		return false


	# 기본 시설은 플레이어가 건설할 수 없음
	if not facility_data.is_player_buildable():
		push_warning(
			"FacilitySystem: 플레이어가 건설할 수 없는 시설입니다: %s"
			% facility_id
		)
		return false


	# 이미 존재하거나 건설 중
	if settlement.get_facility(facility_id) != null:
		push_warning(
			"FacilitySystem: 이미 존재하거나 건설 중인 시설입니다: %s"
			% facility_id
		)
		return false


	var build_data := facility_data.get_build_data()

	if build_data == null:
		push_warning(
			"FacilitySystem: 건설 데이터가 없습니다: %s"
			% facility_id
		)
		return false


	# 기능 시설 총 10개
	if (
		facility_data.category
		== FacilityData.Category.FUNCTIONAL
		and _get_functional_facility_count(settlement) >= 10
	):
		push_warning(
			"FacilitySystem: 기능 시설은 최대 10개까지 건설할 수 있습니다."
		)
		return false


	if not _can_afford(settlement, build_data):
		push_warning(
			"FacilitySystem: 자원이 부족합니다: %s"
			% facility_id
		)
		return false


	_pay_cost(settlement, build_data)


	var facility_state := FacilityState.new(
		facility_id,
		0,
		FacilityState.Status.CONSTRUCTING
	)

	settlement.facilities.append(facility_state)


	# 레벨 시설이면 Lv1 건설
	# 레벨 없는 시설이면 0 그대로
	var target_level := 0

	if facility_data.is_level_based():
		target_level = 1


	var task := ConstructionTask.new(
		facility_id,
		ConstructionTask.TaskType.BUILD,
		target_level,
		build_data.construction_turns
	)

	settlement.construction_tasks.append(task)

	construction_started.emit(facility_id)

	return true

# =========================================================
# 업그레이드
# =========================================================

func request_upgrade(
	settlement: SettlementState,
	facility_id: StringName
) -> bool:

	if facility_catalog == null:
		push_error("FacilitySystem: FacilityCatalog이 설정되지 않았습니다.")
		return false

	var facility_data := facility_catalog.get_facility_data(facility_id)

	if facility_data == null:
		push_warning(
			"FacilitySystem: 시설 데이터를 찾을 수 없습니다: %s"
			% facility_id
		)
		return false
	
	if not facility_data.is_level_based():
		push_warning(
			"FacilitySystem: 업그레이드할 수 없는 시설입니다: %s"
			% facility_id
		)
		return false

	var facility_state := settlement.get_facility(facility_id)

	if facility_state == null or not facility_state.is_built():
		push_warning(
			"FacilitySystem: 건설되지 않은 시설입니다: %s"
			% facility_id
		)
		return false


	if facility_state.is_under_construction():
		push_warning(
			"FacilitySystem: 이미 업그레이드 중입니다: %s"
			% facility_id
		)
		return false


	var target_level := facility_state.level + 1

	if target_level > facility_data.get_max_level():
		push_warning(
			"FacilitySystem: 이미 최대 레벨입니다: %s"
			% facility_id
		)
		return false


	var level_data := facility_data.get_level_data(target_level)

	if level_data == null:
		return false


	if not _can_afford(settlement, level_data):
		push_warning(
			"FacilitySystem: 업그레이드 자원이 부족합니다: %s"
			% facility_id
		)
		return false


	# 업그레이드도 시작할 때 전액 지불
	_pay_cost(settlement, level_data)

	# 기존 레벨은 유지
	facility_state.status = FacilityState.Status.UPGRADING


	var task := ConstructionTask.new(
		facility_id,
		ConstructionTask.TaskType.UPGRADE,
		target_level,
		level_data.construction_turns
	)

	settlement.construction_tasks.append(task)

	upgrade_started.emit(facility_id)

	return true


# =========================================================
# 비용
# =========================================================

func _can_afford(
	settlement: SettlementState,
	level_data: FacilityLevelData
) -> bool:

	return (
		settlement.gold >= level_data.gold_cost
		and settlement.food >= level_data.food_cost
		and settlement.wood >= level_data.wood_cost
		and settlement.stone >= level_data.stone_cost
		and settlement.iron >= level_data.iron_cost
		and settlement.magic_stone >= level_data.magic_stone_cost
	)


func _pay_cost(
	settlement: SettlementState,
	level_data: FacilityLevelData
) -> void:

	settlement.gold -= level_data.gold_cost
	settlement.food -= level_data.food_cost
	settlement.wood -= level_data.wood_cost
	settlement.stone -= level_data.stone_cost
	settlement.iron -= level_data.iron_cost
	settlement.magic_stone -= level_data.magic_stone_cost


# =========================================================
# 기능 시설
# =========================================================

func _get_functional_facility_count(
	settlement: SettlementState
) -> int:

	var count := 0

	for facility_state in settlement.facilities:
		var facility_data := facility_catalog.get_facility_data(
			facility_state.facility_id
		)

		if facility_data == null:
			continue

		if facility_data.category == FacilityData.Category.FUNCTIONAL:
			count += 1

	return count
