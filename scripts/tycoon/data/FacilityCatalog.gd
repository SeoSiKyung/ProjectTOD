class_name FacilityCatalog
extends Resource

@export var facilities: Array[FacilityData] = []


func GetFacilityData(facility_id: StringName) -> FacilityData:
	for facility in facilities:
		if facility.id == facility_id:
			return facility

	return null


func HasFacility(facility_id: StringName) -> bool:
	return GetFacilityData(facility_id) != null
