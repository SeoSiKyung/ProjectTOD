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

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var category: Category = Category.PRODUCTION
@export var icon: Texture2D


@export_group("Level Based Facility")

# 생산 / 발전 / 방어 시설에서 사용
# index 0 = Lv1
# index 1 = Lv2 ...
@export var levels: Array[FacilityLevelData] = []


@export_group("Non Level Facility")

# 기본 / 기능 시설에서 사용
# 레벨이 없으므로 건설 비용, 시간, 기본 효과만 저장
@export var base_data: FacilityLevelData


@export_group("Build Limit")

@export_range(1, 100, 1)
var max_count: int = 1

@export var group_id: StringName = &""

@export_range(0, 100, 1)
var group_max_count: int = 0


func is_level_based() -> bool:
	return (
		category == Category.PRODUCTION
		or category == Category.DEVELOPMENT
		or category == Category.DEFENSE
	)


func is_player_buildable() -> bool:
	return category != Category.BASIC


func get_max_level() -> int:
	if not is_level_based():
		return 0

	return levels.size()


func get_level_data(level: int) -> FacilityLevelData:
	if not is_level_based():
		return null

	if level < 1 or level > levels.size():
		return null

	return levels[level - 1]


func get_build_data() -> FacilityLevelData:
	if is_level_based():
		return get_level_data(1)

	return base_data


func get_effect_data(level: int) -> FacilityLevelData:
	if is_level_based():
		return get_level_data(level)

	return base_data
