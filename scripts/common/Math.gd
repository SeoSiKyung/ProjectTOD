class_name Math

const EPSILON: float = 0.00001
const BIG_NUMBER: float = 1.0e30
const SQRT_2: float = 1.41421356237

const RATIO_SCALE: int = 1000

const DIRECTIONS_4: Array[Vector2i] = [
	Vector2i(0, -1),
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(-1, 0),
]

const DIRECTIONS_8: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(1, 1),
	Vector2i(0, 1),
	Vector2i(-1, 1),
	Vector2i(-1, 0),
	Vector2i(-1, -1),
	Vector2i(0, -1),
	Vector2i(1, -1),
]


static func ApplyRatio(value: int, ratio: int) -> int:
	return (value * ratio) / RATIO_SCALE


static func CeilDivide(value: int, divisor: int) -> int:
	return (value + divisor - 1) / divisor


static func OctileDistance(a: Vector2i, b: Vector2i) -> float:
	var dx: int = absi(a.x - b.x)
	var dy: int = absi(a.y - b.y)

	var diagonal: int = mini(dx, dy)
	var straight: int = maxi(dx, dy) - diagonal

	return float(diagonal) * SQRT_2 + float(straight)


static func QuantizeVector2(value: Vector2, quantum: float) -> Vector2:
	if quantum <= 0.0:
		return value

	return Vector2(round(value.x / quantum) * quantum, round(value.y / quantum) * quantum)


static func SegmentAabbEntryFraction(start: Vector2, delta: Vector2, half: Vector2) -> float:
	var tMin: float = 0.0
	var tMax: float = 1.0
	if absf(delta.x) <= EPSILON:
		if start.x < -half.x or start.x > half.x:
			return -1.0
	else:
		var tx1: float = (-half.x - start.x) / delta.x
		var tx2: float = (half.x - start.x) / delta.x
		if tx1 > tx2:
			var tempX: float = tx1
			tx1 = tx2
			tx2 = tempX

		tMin = maxf(tMin, tx1)
		tMax = minf(tMax, tx2)
		if tMin > tMax:
			return -1.0

	if absf(delta.y) <= EPSILON:
		if start.y < -half.y or start.y > half.y:
			return -1.0
	else:
		var ty1: float = (-half.y - start.y) / delta.y
		var ty2: float = (half.y - start.y) / delta.y
		if ty1 > ty2:
			var tempY: float = ty1
			ty1 = ty2
			ty2 = tempY

		tMin = maxf(tMin, ty1)
		tMax = minf(tMax, ty2)
		if tMin > tMax:
			return -1.0

	if tMax < 0.0 or tMin > 1.0:
		return -1.0

	return clampf(tMin, 0.0, 1.0)


static func SegmentIntersectsCenteredAabb(start: Vector2, end: Vector2, half: Vector2) -> bool:
	return SegmentAabbEntryFraction(start, end - start, half) >= 0.0

static func IsOpposite(a: Vector2, b: Vector2) -> bool:
	return a.dot(b) < 0.0
