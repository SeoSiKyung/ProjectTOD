class_name MovementCollisionQuery
extends RefCounted

const SEARCH_ITERATIONS: int = 24

class TravelQuery:
	var distance: float
	var blockerIds: Array[int] = []

var _navigationService: NavigationService


func _init(navigationService: NavigationService) -> void:
	_navigationService = navigationService


func QueryTravel(
	data: CollisionGroup.AgentData,
	direction: Vector2,
	distance: float,
	occupancy: StageSnapshot,
) -> TravelQuery:
	var result: TravelQuery = TravelQuery.new()
	result.distance = distance
	for otherId: int in _FindNearbyUnits(data, direction, distance, occupancy):
		if otherId == data.unitId:
			continue
		var contactDistance: float = FirstContactDistance(
			data.startPosition, direction, occupancy.GetPosition(otherId),
			float(data.halfSize + occupancy.GetHalfSize(otherId)),
		)
		if contactDistance < distance:
			result.blockerIds.append(otherId)
			result.distance = minf(result.distance, contactDistance)
	result.blockerIds.sort()
	return result


func GetStaticTravelDistance(
	data: CollisionGroup.AgentData,
	direction: Vector2,
	maxDistance: float,
) -> float:
	if _StaticSegmentClear(data, data.startPosition + direction * maxDistance):
		return maxDistance
	var clearDistance: float = 0.0
	var blockedDistance: float = maxDistance
	for iteration: int in range(SEARCH_ITERATIONS):
		var distance: float = (clearDistance + blockedDistance) * 0.5
		if _StaticSegmentClear(data, data.startPosition + direction * distance):
			clearDistance = distance
		else:
			blockedDistance = distance
	return clearDistance


func GetSafeEndpoint(
	data: CollisionGroup.AgentData,
	direction: Vector2,
	distance: float,
	occupancy: StageSnapshot,
) -> Vector2:
	var endpoint: Vector2 = data.startPosition + direction * distance
	if IsPositionClear(endpoint, data.halfSize, data.unitId, occupancy):
		return endpoint
	var clearDistance: float = 0.0
	var blockedDistance: float = distance
	for iteration: int in range(SEARCH_ITERATIONS):
		var testDistance: float = (clearDistance + blockedDistance) * 0.5
		var testPosition: Vector2 = data.startPosition + direction * testDistance
		if IsPositionClear(testPosition, data.halfSize, data.unitId, occupancy):
			clearDistance = testDistance
		else:
			blockedDistance = testDistance
	return data.startPosition + direction * clearDistance


func IsPositionClear(
	position: Vector2,
	halfSize: int,
	ignoredUnitId: int,
	occupancy: StageSnapshot,
) -> bool:
	var extent: Vector2 = Vector2.ONE * float(halfSize)
	for otherId: int in occupancy.FindUnitIdsInRect(position, extent):
		if otherId == ignoredUnitId:
			continue
		if Overlaps(position, halfSize, occupancy.GetPosition(otherId), occupancy.GetHalfSize(otherId)):
			return false
	return true


static func Overlaps(
	firstPosition: Vector2,
	firstHalfSize: int,
	secondPosition: Vector2,
	secondHalfSize: int,
) -> bool:
	var extent: float = float(firstHalfSize + secondHalfSize)
	return (
		absf(firstPosition.x - secondPosition.x) < extent
		and absf(firstPosition.y - secondPosition.y) < extent
	)


static func FirstContactDistance(
	origin: Vector2,
	direction: Vector2,
	center: Vector2,
	expandedHalfSize: float,
) -> float:
	var relative: Vector2 = center - origin
	var enterDistance: float = -INF
	var exitDistance: float = INF
	for axis: int in range(2):
		if direction[axis] == 0.0:
			if absf(relative[axis]) >= expandedHalfSize:
				return INF
			continue
		var first: float = (relative[axis] - expandedHalfSize) / direction[axis]
		var second: float = (relative[axis] + expandedHalfSize) / direction[axis]
		enterDistance = maxf(enterDistance, minf(first, second))
		exitDistance = minf(exitDistance, maxf(first, second))
	if enterDistance >= exitDistance or exitDistance <= 0.0:
		return INF
	return maxf(0.0, enterDistance)


func _FindNearbyUnits(
	data: CollisionGroup.AgentData,
	direction: Vector2,
	distance: float,
	occupancy: StageSnapshot,
) -> Array[int]:
	var movement: Vector2 = direction * distance
	var center: Vector2 = data.startPosition + movement * 0.5
	var extent: Vector2 = movement.abs() * 0.5 + Vector2.ONE * float(data.halfSize)
	return occupancy.FindUnitIdsInRect(center, extent)


func _StaticSegmentClear(data: CollisionGroup.AgentData, endpoint: Vector2) -> bool:
	return (
		_navigationService == null
		or _navigationService.SegmentClear(data.startPosition, endpoint, data.halfSize)
	)
