class_name DefenseSpawnPositionManager
extends RefCounted

const SPAWN_POSITION_GAP: int = 4
const MAX_SPAWN_POSITION_ATTEMPTS: int = 2048

var _spawnPoints: Node2D
var _navigationService: NavigationService
var _stageSnapshot: StageSnapshot


func _init(spawnPoints: Node2D, navigationService: NavigationService, stageSnapshot: StageSnapshot) -> void:
	_spawnPoints = spawnPoints
	_navigationService = navigationService
	_stageSnapshot = stageSnapshot


func GetSpawnPoint(spawnPointKey: int) -> Marker2D:
	if _spawnPoints == null:
		return null

	var spawnPointPath: NodePath = NodePath("SpawnPoint" + str(spawnPointKey))

	var node: Node = _spawnPoints.get_node_or_null(spawnPointPath)
	if node is Marker2D:
		return node as Marker2D

	return null


func FindNextCandidateIndex(center: Vector2, halfSize: int, startCandidateIndex: int) -> int:
	var candidateIndex: int = startCandidateIndex
	var attemptCount: int = 0

	while attemptCount < MAX_SPAWN_POSITION_ATTEMPTS:
		var position: Vector2 = GetSpawnPosition(center, halfSize, candidateIndex)

		if _CanSpawnAt(position, halfSize):
			return candidateIndex

		candidateIndex += 1
		attemptCount += 1

	return -1


func GetSpawnPosition(center: Vector2, halfSize: int, candidateIndex: int) -> Vector2:
	var spacing: float = _CalculateSpacing(halfSize)
	var gridOffset: Vector2i = _GetSquareSpiralOffset(candidateIndex)

	return center + Vector2(gridOffset) * spacing


func _CalculateSpacing(halfSize: int) -> float:
	return float(halfSize * 2 + SPAWN_POSITION_GAP)


func _CanSpawnAt(position: Vector2, halfSize: int) -> bool:
	if not _navigationService.CanPlaceStatic(position, halfSize):
		return false

	var nearbyUnitIds: Array[int] = _stageSnapshot.FindUnitIdsInRect(
		position,
		Vector2(float(halfSize), float(halfSize)),
	)

	return nearbyUnitIds.is_empty()


func _GetSquareSpiralOffset(index: int) -> Vector2i:
	if index <= 0:
		return Vector2i.ZERO

	var ring: int = ceili((sqrt(float(index + 1)) - 1.0) * 0.5)

	var sideLength: int = ring * 2

	var ringStartIndex: int = ((ring * 2 - 1) * (ring * 2 - 1))

	var offset: int = index - ringStartIndex
	if offset < sideLength:
		return Vector2i(ring, -ring + 1 + offset)

	offset -= sideLength
	if offset < sideLength:
		return Vector2i(ring - 1 - offset, ring)

	offset -= sideLength
	if offset < sideLength:
		return Vector2i(-ring, ring - 1 - offset)

	offset -= sideLength
	return Vector2i(-ring + 1 + offset, -ring)
