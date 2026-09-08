extends Node

const EVENT_CATALOG: EventCatalog = preload("res://data/event/event_catalog.tres")

@onready var _eventPopup: EventPopup = ($"../UI/UIRoot/EventPopup")


func _ready() -> void:
	call_deferred("_ShowTestEvent")


func _ShowTestEvent() -> void:
	var eventData: EventData = (EVENT_CATALOG.GetEventData(&"tavern_rumor"))

	if eventData == null:
		push_error("TestNode: tavern_rumor를 찾지 못했습니다.")

		return

	if _eventPopup == null:
		push_error("TestNode: EventPopup을 찾지 못했습니다.")

		return

	_eventPopup.ShowEvent(eventData)
