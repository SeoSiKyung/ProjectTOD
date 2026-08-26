class_name FacilityData
extends Resource

enum Category {
	BASIC,
	PRODUCTION,
	DEVELOPMENT,
	DEFENSE,
	FUNCTIONAL,
}

@export_group("Identity")

@export var id: StringName = &""
@export var displayName: String = ""
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
@export var baseData: FacilityLevelData


@export_group("Build Limit")

@export_range(1, 100, 1)
var maxCount: int = 1

@export var groupId: StringName = &""

@export_range(0, 100, 1)
var groupMaxCount: int = 0


func IsLevelBased() -> bool:
	return (
		category == Category.PRODUCTION or category == Category.DEVELOPMENT
		or category == Category.DEFENSE
	)


func IsPlayerBuildable() -> bool:
	return category != Category.BASIC


func GetMaxLevel() -> int:
	if not IsLevelBased():
		return 0

	return levels.size()


func GetLevelData(level: int) -> FacilityLevelData:
	if not IsLevelBased():
		return null

	if level < 1 or level > levels.size():
		return null

	return levels[level - 1]


func GetBuildData() -> FacilityLevelData:
	if IsLevelBased():
		return GetLevelData(1)

	return baseData


func GetEffectData(level: int) -> FacilityLevelData:
	if IsLevelBased():
		return GetLevelData(level)

	return baseData
