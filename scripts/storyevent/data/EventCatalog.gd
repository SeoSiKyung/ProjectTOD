class_name EventCatalog
extends Resource

@export var events: Array[EventData] = []


func GetEventData(eventId: StringName) -> EventData:
	for eventData in events:
		if eventData == null:
			continue

		if eventData.id == eventId:
			return eventData

	return null
