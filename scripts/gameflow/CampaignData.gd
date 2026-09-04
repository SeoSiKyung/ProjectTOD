class_name CampaignData
extends Resource

@export var cycles: Array[CycleData] = []


func GetCycleData(cycleNumber: int) -> CycleData:
	for cycleData in cycles:
		if cycleData == null:
			continue

		if cycleData.cycle == cycleNumber:
			return cycleData

	return null


func HasCycle(cycleNumber: int) -> bool:
	return GetCycleData(cycleNumber) != null
