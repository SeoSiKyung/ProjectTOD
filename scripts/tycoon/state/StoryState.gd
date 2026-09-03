class_name StoryState
extends RefCounted

var storyFlags: Dictionary = { }

var collectedIntel: Array[StringName] = []

# =========================================================
# Story Flag
# =========================================================


func HasStoryFlag(flag: StringName) -> bool:
	return storyFlags.get(flag, false)


func SetStoryFlag(flag: StringName, value: bool = true) -> void:
	storyFlags[flag] = value

# =========================================================
# Intel
# =========================================================


func HasIntel(intelId: StringName) -> bool:
	return collectedIntel.has(intelId)


func AddIntel(intelId: StringName) -> void:
	if not collectedIntel.has(intelId):
		collectedIntel.append(intelId)
