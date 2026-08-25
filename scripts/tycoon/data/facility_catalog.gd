class_name FacilityCatalog
extends Resource


@export var facilities: Array[FacilityData] = []


func get_facility_data(facility_id: StringName) -> FacilityData:
	for facility in facilities:
		if facility.id == facility_id:
			return facility

	return null


func has_facility(facility_id: StringName) -> bool:
	return get_facility_data(facility_id) != null
