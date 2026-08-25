class_name FacilitySystem
extends Node

signal ConstructionStarted(facilityId: StringName)
signal UpgradeStarted(facilityId: StringName)

var _facilityCatalog: FacilityCatalog


func Setup(facilityCatalog: FacilityCatalog) -> void:
	_facilityCatalog = facilityCatalog

# =========================================================
# 건설
# =========================================================


func RequestBuild(settlement: SettlementState, facilityId: StringName) -> bool:
	if _facilityCatalog == null:
		push_error("FacilitySystem: FacilityCatalog이 설정되지 않았습니다.")
		return false

	var facilityData := _facilityCatalog.GetFacilityData(facilityId)

	if facilityData == null:
		push_warning("FacilitySystem: 시설 데이터를 찾을 수 없습니다: %s" % facilityId)
		return false

	# 기본 시설은 플레이어가 건설할 수 없음
	if not facilityData.IsPlayerBuildable():
		push_warning("FacilitySystem: 플레이어가 건설할 수 없는 시설입니다: %s" % facilityId)
		return false

	# 이미 존재하거나 건설 중
	if settlement.GetFacility(facilityId) != null:
		push_warning("FacilitySystem: 이미 존재하거나 건설 중인 시설입니다: %s" % facilityId)
		return false

	var buildData := facilityData.GetBuildData()

	if buildData == null:
		push_warning("FacilitySystem: 건설 데이터가 없습니다: %s" % facilityId)
		return false

	# 기능 시설 총 10개
	if (
		facilityData.category == FacilityData.Category.FUNCTIONAL
		and _GetFunctionalFacilityCount(settlement) >= 10
	):
		push_warning("FacilitySystem: 기능 시설은 최대 10개까지 건설할 수 있습니다.")
		return false

	if not _CanAfford(settlement, buildData):
		push_warning("FacilitySystem: 자원이 부족합니다: %s" % facilityId)
		return false

	_PayCost(settlement, buildData)

	var facilityState := FacilityState.new(facilityId, 0, FacilityState.Status.CONSTRUCTING)

	settlement.facilities.append(facilityState)

	# 레벨 시설이면 Lv1 건설
	# 레벨 없는 시설이면 0 그대로
	var targetLevel := 0

	if facilityData.IsLevelBased():
		targetLevel = 1

	var task := ConstructionTask.new(
		facilityId,
		ConstructionTask.TaskType.BUILD,
		targetLevel,
		buildData.constructionTurns,
	)

	settlement.constructionTasks.append(task)

	ConstructionStarted.emit(facilityId)

	return true

# =========================================================
# 업그레이드
# =========================================================


func RequestUpgrade(settlement: SettlementState, facilityId: StringName) -> bool:
	if _facilityCatalog == null:
		push_error("FacilitySystem: FacilityCatalog이 설정되지 않았습니다.")
		return false

	var facilityData := _facilityCatalog.GetFacilityData(facilityId)

	if facilityData == null:
		push_warning("FacilitySystem: 시설 데이터를 찾을 수 없습니다: %s" % facilityId)
		return false

	if not facilityData.IsLevelBased():
		push_warning("FacilitySystem: 업그레이드할 수 없는 시설입니다: %s" % facilityId)
		return false

	var facilityState := settlement.GetFacility(facilityId)

	if facilityState == null or not facilityState.IsBuilt():
		push_warning("FacilitySystem: 건설되지 않은 시설입니다: %s" % facilityId)
		return false

	if facilityState.IsUnderConstruction():
		push_warning("FacilitySystem: 이미 업그레이드 중입니다: %s" % facilityId)
		return false

	var targetLevel := facilityState.level + 1

	if targetLevel > facilityData.GetMaxLevel():
		push_warning("FacilitySystem: 이미 최대 레벨입니다: %s" % facilityId)
		return false

	var levelData := facilityData.GetLevelData(targetLevel)

	if levelData == null:
		return false

	if not _CanAfford(settlement, levelData):
		push_warning("FacilitySystem: 업그레이드 자원이 부족합니다: %s" % facilityId)
		return false

	# 업그레이드도 시작할 때 전액 지불
	_PayCost(settlement, levelData)

	# 기존 레벨은 유지
	facilityState.status = FacilityState.Status.UPGRADING

	var task := ConstructionTask.new(
		facilityId,
		ConstructionTask.TaskType.UPGRADE,
		targetLevel,
		levelData.constructionTurns,
	)

	settlement.constructionTasks.append(task)

	UpgradeStarted.emit(facilityId)

	return true

# =========================================================
# 비용
# =========================================================


func _CanAfford(settlement: SettlementState, levelData: FacilityLevelData) -> bool:
	return (
		settlement.gold >= levelData.goldCost and settlement.food >= levelData.foodCost
		and settlement.wood >= levelData.woodCost
		and settlement.stone >= levelData.stoneCost and settlement.iron >= levelData.ironCost
		and settlement.magicStone >= levelData.magicStoneCost
	)


func _PayCost(settlement: SettlementState, levelData: FacilityLevelData) -> void:
	settlement.gold -= levelData.goldCost
	settlement.food -= levelData.foodCost
	settlement.wood -= levelData.woodCost
	settlement.stone -= levelData.stoneCost
	settlement.iron -= levelData.ironCost
	settlement.magicStone -= levelData.magicStoneCost

# =========================================================
# 기능 시설
# =========================================================


func _GetFunctionalFacilityCount(settlement: SettlementState) -> int:
	var count := 0

	for facilityState in settlement.facilities:
		var facilityData := _facilityCatalog.GetFacilityData(facilityState.facilityId)

		if facilityData == null:
			continue

		if facilityData.category == FacilityData.Category.FUNCTIONAL:
			count += 1

	return count
