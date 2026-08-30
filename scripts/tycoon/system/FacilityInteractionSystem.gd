class_name FacilityInteractionSystem
extends Node

var _facilityCatalog: FacilityCatalog


func Setup(facilityCatalog: FacilityCatalog) -> void:
	_facilityCatalog = facilityCatalog

# =========================================================
# 시설 상호작용 가능 여부
# =========================================================


func CanInteract(settlement: SettlementState, facilityId: StringName) -> bool:
	return GetInteractionId(settlement, facilityId) != &""

# =========================================================
# 시설 Interaction ID 조회
# =========================================================


func GetInteractionId(settlement: SettlementState, facilityId: StringName) -> StringName:
	if _facilityCatalog == null:
		push_error("FacilityInteractionSystem: FacilityCatalog이 설정되지 않았습니다.")
		return &""

	# =====================================================
	# 실제 시설이 존재하는지
	# =====================================================
	var facilityState := settlement.GetFacility(facilityId)

	if facilityState == null:
		return &""

	# =====================================================
	# 완공된 시설인지
	# =====================================================
	if not facilityState.IsBuilt():
		return &""

	# =====================================================
	# FacilityData 조회
	# =====================================================
	var facilityData := (_facilityCatalog.GetFacilityData(facilityId))

	if facilityData == null:
		push_warning("FacilityInteractionSystem: 시설 데이터를 찾을 수 없습니다: %s" % facilityId)
		return &""

	# =====================================================
	# 상호작용 기능 확인
	# =====================================================
	if not facilityData.HasInteraction():
		return &""

	return facilityData.interactionId
