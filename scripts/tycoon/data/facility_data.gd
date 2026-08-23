class_name FacilityData
extends Resource


enum Category {
	BASIC,
	PRODUCTION,
	DEVELOPMENT,
	DEFENSE,
	FUNCTIONAL
}


@export_group("Identity")

# 내부 코드에서 사용하는 고유 ID
# 예: farm, workshop, barracks
@export var id: StringName = &""

@export var display_name: String = ""

@export_multiline var description: String = ""

@export var category: Category = Category.PRODUCTION

@export var icon: Texture2D


@export_group("Levels")

# index 0 = Lv1
# index 1 = Lv2
# index 2 = Lv3 ...
@export var levels: Array[FacilityLevelData] = []


@export_group("Build Limit")

# 동일 시설 최대 건설 개수
@export_range(1, 100, 1)
var max_count: int = 1

# 특정 시설들을 하나의 그룹으로 묶어 제한할 때 사용.
# 예: 각 길드 지부는 max_count = 1이지만
# group_id = "guild_branch", group_max_count = 2
@export var group_id: StringName = &""

@export_range(0, 100, 1)
var group_max_count: int = 0


func get_max_level() -> int:
	return levels.size()


func get_level_data(level: int) -> FacilityLevelData:
	if level < 1 or level > levels.size():
		return null

	return levels[level - 1]
