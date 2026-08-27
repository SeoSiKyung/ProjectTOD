class_name FacilityCatalog
extends Resource

@export var facilities: Array[FacilityData] = []


func GetFacilityData(facilityId: StringName) -> FacilityData:
	for facilityData in facilities:
		if facilityData == null:
			continue

		if facilityData.id == facilityId:
			return facilityData

	return null
