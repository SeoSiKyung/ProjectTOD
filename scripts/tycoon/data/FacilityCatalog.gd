class_name FacilityCatalog
extends Resource

@export var facilities: Array[FacilityData] = []


func GetFacilityData(facilityId: StringName) -> FacilityData:
	for facility in facilities:
		if facility.id == facilityId:
			return facility

	return null


func HasFacility(facilityId: StringName) -> bool:
	return GetFacilityData(facilityId) != null
