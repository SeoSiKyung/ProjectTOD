class_name EventData
extends Resource

@export var id: StringName = &""

@export var displayName: String = ""

@export_multiline var description: String = ""

@export_range(0.0, 1.0, 0.01)
var triggerChance: float = 0.0

@export var choices: Array[EventChoiceData] = []


func GetChoiceData(choiceId: StringName) -> EventChoiceData:
	for choiceData in choices:
		if choiceData == null:
			continue

		if choiceData.id == choiceId:
			return choiceData

	return null
