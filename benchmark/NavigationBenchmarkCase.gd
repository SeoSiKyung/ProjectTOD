class_name NavigationBenchmarkCase

const GROUP_HALF_SIZE: int = 16
const FAR_TARGET: Vector2 = Vector2(3040, 3120)

enum Type {
	SINGLE_PATH,
	GROUP_PATHS,
}

var caseName: String
var type: Type

var start: Vector2
var unitStarts: PackedVector2Array

var target: Vector2
var halfSize: int


func _init(
	pCaseName: String,
	pType: Type,
	pTarget: Vector2,
	pHalfSize: int,
	pStart: Vector2 = Vector2.ZERO,
	pUnitStarts: PackedVector2Array = PackedVector2Array(),
) -> void:
	caseName = pCaseName
	type = pType
	target = pTarget
	halfSize = pHalfSize
	start = pStart
	unitStarts = pUnitStarts


static func CreateCases() -> Array[NavigationBenchmarkCase]:
	return [
		# 좁은 배치 + 먼 목적지
		_CreateGroupCase("Group5_Close_FarTarget", FAR_TARGET, _CloseStarts()),
		# 중간 배치 + 먼 목적지
		_CreateGroupCase("Group5_Medium_FarTarget", FAR_TARGET, _MediumStarts()),
		# 넓은 배치 + 먼 목적지
		_CreateGroupCase("Group5_Spread_FarTarget", FAR_TARGET, _SpreadStarts()),
		# 넓은 배치 + 이동 방향과 나란한 형태
		_CreateGroupCase("Group5_Spread_Inline_FarTarget", FAR_TARGET, _InlineStarts()),
		# 넓은 배치 + 이동 방향에 수직인 형태
		_CreateGroupCase("Group5_Spread_Lateral_FarTarget", FAR_TARGET, _LateralStarts()),
		# 좁은 배치 + 그룹 반경 내부 목적지
		_CreateGroupCase("Group5_Close_InsideRadius", Vector2(410, 430), _CloseStarts()),
		# 그룹 반경 경계 바로 안쪽 목적지
		_CreateGroupCase("Group5_Close_RadiusInsideEdge", Vector2(410, 366), _CloseStarts()),
		# 그룹 반경 경계 바로 바깥쪽 목적지
		_CreateGroupCase("Group5_Close_RadiusOutsideEdge", Vector2(410, 360), _CloseStarts()),
	]


static func _CreateGroupCase(
	pCaseName: String,
	pTarget: Vector2,
	pUnitStarts: PackedVector2Array,
) -> NavigationBenchmarkCase:
	return NavigationBenchmarkCase.new(
		pCaseName,
		Type.GROUP_PATHS,
		pTarget,
		GROUP_HALF_SIZE,
		Vector2.ZERO,
		pUnitStarts,
	)


static func _CloseStarts() -> PackedVector2Array:
	return PackedVector2Array(
		[
			Vector2(370, 390),
			Vector2(410, 390),
			Vector2(450, 390),
			Vector2(390, 430),
			Vector2(430, 430),
		]
	)


static func _MediumStarts() -> PackedVector2Array:
	return PackedVector2Array(
		[
			Vector2(330, 374),
			Vector2(410, 374),
			Vector2(490, 374),
			Vector2(370, 454),
			Vector2(450, 454),
		]
	)


static func _SpreadStarts() -> PackedVector2Array:
	return PackedVector2Array(
		[
			Vector2(250, 342),
			Vector2(410, 342),
			Vector2(570, 342),
			Vector2(330, 502),
			Vector2(490, 502),
		]
	)


static func _InlineStarts() -> PackedVector2Array:
	return PackedVector2Array(
		[
			Vector2(330, 330),
			Vector2(390, 390),
			Vector2(450, 450),
			Vector2(510, 510),
			Vector2(570, 570),
		]
	)


static func _LateralStarts() -> PackedVector2Array:
	return PackedVector2Array(
		[
			Vector2(330, 570),
			Vector2(390, 510),
			Vector2(450, 450),
			Vector2(510, 390),
			Vector2(570, 330),
		]
	)
