class_name StoryState
extends RefCounted

# =========================================================
# 스토리
# =========================================================

var storyFlags: Dictionary = { }

var collectedIntel: Array[StringName] = []

var pendingEvents: Array[StringName] = []

# =========================================================
# Story Flag
# =========================================================


func HasStoryFlag(flag: StringName) -> bool:
	return storyFlags.get(flag, false)


func SetStoryFlag(flag: StringName, value: bool = true) -> void:
	storyFlags[flag] = value

# =========================================================
# 정보
# =========================================================


func HasIntel(intelId: StringName) -> bool:
	return collectedIntel.has(intelId)


func AddIntel(intelId: StringName) -> void:
	if not collectedIntel.has(intelId):
		collectedIntel.append(intelId)

# =========================================================
# 대기 이벤트
# =========================================================


func AddPendingEvent(eventId: StringName) -> void:
	if not pendingEvents.has(eventId):
		pendingEvents.append(eventId)


func PopPendingEvent() -> StringName:
	if pendingEvents.is_empty():
		return &""

	return pendingEvents.pop_front()
