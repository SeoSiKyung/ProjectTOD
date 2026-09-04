class_name EventState
extends RefCounted

var _activeEventId: StringName = &""

var _pendingEventIds: Array[StringName] = []

var _triggeredOneShotEventIds: Array[StringName] = []

# =========================================================
# Active Event
# =========================================================


func HasActiveEvent() -> bool:
	return _activeEventId != &""


func GetActiveEventId() -> StringName:
	return _activeEventId


func ActivateEvent(eventId: StringName) -> bool:
	if eventId == &"":
		return false

	if HasActiveEvent():
		return false

	_activeEventId = eventId

	return true


func CompleteActiveEvent() -> void:
	_activeEventId = &""

# =========================================================
# Pending Event
# =========================================================


func HasPendingEvents() -> bool:
	return not _pendingEventIds.is_empty()


func AddPendingEvent(eventId: StringName) -> void:
	if eventId == &"":
		return

	if not _pendingEventIds.has(eventId):
		_pendingEventIds.append(eventId)


func ActivateNextPendingEvent() -> StringName:
	if HasActiveEvent():
		return &""

	if _pendingEventIds.is_empty():
		return &""

	var eventId: StringName = (_pendingEventIds.pop_front())

	_activeEventId = eventId

	return eventId


func GetPendingEventIds() -> Array[StringName]:
	return _pendingEventIds.duplicate()

# =========================================================
# One Shot Event
# =========================================================


func HasTriggeredOneShotEvent(eventId: StringName) -> bool:
	return _triggeredOneShotEventIds.has(eventId)


func MarkOneShotTriggered(eventId: StringName) -> void:
	if eventId == &"":
		return

	if not _triggeredOneShotEventIds.has(eventId):
		_triggeredOneShotEventIds.append(eventId)


func GetTriggeredOneShotEventIds() -> Array[StringName]:
	return _triggeredOneShotEventIds.duplicate()

# =========================================================
# Load
#
# SaveData에서 복구할 때 사용.
# 외부에서 내부 Array를 직접 조작하지 않도록
# EventState가 자신의 상태 복원을 담당.
# =========================================================


func Restore(
	activeEventId: StringName,
	pendingEventIds: Array[StringName],
	triggeredOneShotEventIds: Array[StringName],
) -> void:
	_activeEventId = activeEventId

	_pendingEventIds = (pendingEventIds.duplicate())

	_triggeredOneShotEventIds = (triggeredOneShotEventIds.duplicate())
