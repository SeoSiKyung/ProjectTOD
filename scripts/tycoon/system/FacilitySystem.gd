class_name FacilitySystem
extends Node

signal ConstructionStarted(facility_id: StringName)
signal UpgradeStarted(facility_id: StringName)

var facilityCatalog: FacilityCatalog


func Setup(p_facility_catalog: FacilityCatalog) -> void:
	facilityCatalog = p_facility_catalog

# =========================================================
# 건설
# =========================================================


func RequestBuild(settlement: SettlementState, facility_id: StringName) -> bool:
	if facilityCatalog == null:
		push_error("FacilitySystem: FacilityCatalog이 설정되지 않았습니다.")
		return false

	var facility_data := facilityCatalog.GetFacilityData(facility_id)

	if facility_data == null:
		push_warning("FacilitySystem: 시설 데이터를 찾을 수 없습니다: %s" % facility_id)
		return false

	# 기본 시설은 플레이어가 건설할 수 없음
	if not facility_data.IsPlayerBuildable():
		push_warning("FacilitySystem: 플레이어가 건설할 수 없는 시설입니다: %s" % facility_id)
		return false

	# 이미 존재하거나 건설 중
	if settlement.GetFacility(facility_id) != null:
		push_warning("FacilitySystem: 이미 존재하거나 건설 중인 시설입니다: %s" % facility_id)
		return false

	var build_data := facility_data.GetBuildData()

	if build_data == null:
		push_warning("FacilitySystem: 건설 데이터가 없습니다: %s" % facility_id)
		return false

	# 기능 시설 총 10개
	if (
		facility_data.category == FacilityData.Category.FUNCTIONAL
		and _GetFunctionalFacilityCount(settlement) >= 10
	):
		push_warning("FacilitySystem: 기능 시설은 최대 10개까지 건설할 수 있습니다.")
		return false

	if not _CanAfford(settlement, build_data):
		push_warning("FacilitySystem: 자원이 부족합니다: %s" % facility_id)
		return false

	_PayCost(settlement, build_data)

	var facility_state := FacilityState.new(facility_id, 0, FacilityState.Status.CONSTRUCTING)

	settlement.facilities.append(facility_state)

	# 레벨 시설이면 Lv1 건설
	# 레벨 없는 시설이면 0 그대로
	var target_level := 0

	if facility_data.IsLevelBased():
		target_level = 1

	var task := ConstructionTask.new(
		facility_id,
		ConstructionTask.TaskType.BUILD,
		target_level,
		build_data.constructionTurns,
	)

	settlement.constructionTasks.append(task)

	ConstructionStarted.emit(facility_id)

	return true

# =========================================================
# 업그레이드
# =========================================================


func RequestUpgrade(settlement: SettlementState, facility_id: StringName) -> bool:
	if facilityCatalog == null:
		push_error("FacilitySystem: FacilityCatalog이 설정되지 않았습니다.")
		return false

	var facility_data := facilityCatalog.GetFacilityData(facility_id)

	if facility_data == null:
		push_warning("FacilitySystem: 시설 데이터를 찾을 수 없습니다: %s" % facility_id)
		return false

	if not facility_data.IsLevelBased():
		push_warning("FacilitySystem: 업그레이드할 수 없는 시설입니다: %s" % facility_id)
		return false

	var facility_state := settlement.GetFacility(facility_id)

	if facility_state == null or not facility_state.IsBuilt():
		push_warning("FacilitySystem: 건설되지 않은 시설입니다: %s" % facility_id)
		return false

	if facility_state.IsUnderConstruction():
		push_warning("FacilitySystem: 이미 업그레이드 중입니다: %s" % facility_id)
		return false

	var target_level := facility_state.level + 1

	if target_level > facility_data.GetMaxLevel():
		push_warning("FacilitySystem: 이미 최대 레벨입니다: %s" % facility_id)
		return false

	var level_data := facility_data.GetLevelData(target_level)

	if level_data == null:
		return false

	if not _CanAfford(settlement, level_data):
		push_warning("FacilitySystem: 업그레이드 자원이 부족합니다: %s" % facility_id)
		return false

	# 업그레이드도 시작할 때 전액 지불
	_PayCost(settlement, level_data)

	# 기존 레벨은 유지
	facility_state.status = FacilityState.Status.UPGRADING

	var task := ConstructionTask.new(
		facility_id,
		ConstructionTask.TaskType.UPGRADE,
		target_level,
		level_data.constructionTurns,
	)

	settlement.constructionTasks.append(task)

	UpgradeStarted.emit(facility_id)

	return true

# =========================================================
# 비용
# =========================================================


func _CanAfford(settlement: SettlementState, level_data: FacilityLevelData) -> bool:
	return (
		settlement.gold >= level_data.goldCost and settlement.food >= level_data.foodCost
		and settlement.wood >= level_data.woodCost
		and settlement.stone >= level_data.stoneCost and settlement.iron >= level_data.ironCost
		and settlement.magicStone >= level_data.magicStoneCost
	)


func _PayCost(settlement: SettlementState, level_data: FacilityLevelData) -> void:
	settlement.gold -= level_data.goldCost
	settlement.food -= level_data.foodCost
	settlement.wood -= level_data.woodCost
	settlement.stone -= level_data.stoneCost
	settlement.iron -= level_data.ironCost
	settlement.magicStone -= level_data.magicStoneCost

# =========================================================
# 기능 시설
# =========================================================


func _GetFunctionalFacilityCount(settlement: SettlementState) -> int:
	var count := 0

	for facility_state in settlement.facilities:
		var facility_data := facilityCatalog.GetFacilityData(facility_state.facilityId)

		if facility_data == null:
			continue

		if facility_data.category == FacilityData.Category.FUNCTIONAL:
			count += 1

	return count
