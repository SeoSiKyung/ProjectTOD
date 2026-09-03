class_name EventConditionData
extends Resource

# =========================================================
# Cycle 조건
#
# 0 = 제한 없음
#
# 예:
# minCycle = 3
# → Cycle 3 이상
#
# minCycle = 3
# maxCycle = 3
# → Cycle 3에서만
# =========================================================

@export var minCycle: int = 0
@export var maxCycle: int = 0

# =========================================================
# StoryFlag 조건
#
# requiredStoryFlags
# → 모두 true여야 함.
#
# excludedStoryFlags
# → 하나라도 true이면 발생 불가.
# =========================================================

@export var requiredStoryFlags: Array[StringName] = []

@export var excludedStoryFlags: Array[StringName] = []

# =========================================================
# Intel 조건
#
# 등록된 Intel을 모두 가지고 있어야 함.
# =========================================================

@export var requiredIntelIds: Array[StringName] = []

# =========================================================
# 시설 조건
#
# 등록된 시설이 모두 "완공" 상태여야 함.
#
# 건설 중인 시설은 조건을 만족하지 않음.
# =========================================================

@export var requiredFacilityIds: Array[StringName] = []
