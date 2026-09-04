class_name EventData
extends Resource

@export var id: StringName = &""

@export var displayName: String = ""

@export_multiline var description: String = ""


# =========================================================
# 발생 설정
# =========================================================

@export_range(0.0, 1.0, 0.01)
var triggerChance: float = 0.0

# =========================================================
# 1회성
#
# true:
# 한 게임에서 한 번 발생한 뒤 다시 발생하지 않음.
#
# false:
# 조건과 확률을 만족하면 반복 발생 가능.
# =========================================================

@export var oneShot: bool = false

# =========================================================
# 발생 조건
# =========================================================

@export var condition: EventConditionData

# =========================================================
# 선택지
# =========================================================

@export var choices: Array[EventChoiceData] = []

# =========================================================
# Choice 조회
# =========================================================


func GetChoiceData(choiceId: StringName) -> EventChoiceData:
	for choiceData in choices:
		if choiceData == null:
			continue

		if choiceData.id == choiceId:
			return choiceData

	return null
