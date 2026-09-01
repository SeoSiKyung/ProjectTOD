class_name EventSystem
extends Node

var _eventCatalog: EventCatalog

var _random: RandomNumberGenerator

# =========================================================
# 초기화
# =========================================================


func Setup(eventCatalog: EventCatalog) -> void:
	_eventCatalog = eventCatalog

	_random = RandomNumberGenerator.new()
	_random.randomize()

# =========================================================
# 턴 시작 이벤트 판정
# =========================================================


func ProcessTurnStart(context: TurnContext) -> void:
	if context == null:
		return

	if _eventCatalog == null:
		return

	for eventData in _eventCatalog.events:
		if eventData == null:
			continue

		if eventData.id == &"":
			continue

		if eventData.triggerChance <= 0.0:
			continue

		var triggered: bool = false

		if eventData.triggerChance >= 1.0:
			triggered = true

		else:
			triggered = (_random.randf() < eventData.triggerChance)

		if not triggered:
			continue

		context.triggeredEvents.append(eventData.id)

# =========================================================
# EventData 조회
# =========================================================


func GetEventData(eventId: StringName) -> EventData:
	if _eventCatalog == null:
		return null

	return _eventCatalog.GetEventData(eventId)
