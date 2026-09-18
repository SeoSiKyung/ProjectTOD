class_name PathFollower
extends RefCounted

const REACH_DISTANCE: float = 0.001

static var _navigationService: NavigationService
var _halfSize: int
var _path: PackedVector2Array = []
var _nextNodeIndex: int = 0
var _targetNodeIndex: int = -1


func _init(halfSize: int) -> void:
	_halfSize = halfSize


static func SetNavigationService(navigationService: NavigationService) -> void:
	_navigationService = navigationService


static func ClearNavigationService(navigationService: NavigationService) -> void:
	if _navigationService == navigationService:
		_navigationService = null


func SetPath(path: PackedVector2Array, position: Vector2) -> void:
	ClearPath()
	for node: Vector2 in path:
		if not node.is_finite():
			push_error("이동 경로에 유효하지 않은 좌표가 있습니다.")
			return
	_path = path.duplicate()
	_SkipReachedNodes(position)


func ClearPath() -> void:
	_path.clear()
	_nextNodeIndex = 0
	_targetNodeIndex = -1


func IsEmpty() -> bool:
	return _nextNodeIndex >= _path.size()


func GetDesiredPosition(position: Vector2, maxStepDistance: float) -> Vector2:
	_targetNodeIndex = _FindFarthestVisibleNode(position)
	if _targetNodeIndex < 0 or maxStepDistance <= 0.0:
		return position
	return position.move_toward(_path[_targetNodeIndex], maxStepDistance)


func OnMovementCommitted(position: Vector2) -> void:
	if _targetNodeIndex >= 0 and _HasReached(position, _path[_targetNodeIndex]):
		_nextNodeIndex = _targetNodeIndex + 1
	_targetNodeIndex = -1
	_SkipReachedNodes(position)


func GetTargetPosition(fallback: Vector2) -> Vector2:
	if _targetNodeIndex < 0:
		return fallback
	return _path[_targetNodeIndex]


func _FindFarthestVisibleNode(position: Vector2) -> int:
	for index: int in range(_path.size() - 1, _nextNodeIndex - 1, -1):
		if _navigationService == null:
			return index
		if _navigationService.SegmentClear(position, _path[index], _halfSize):
			return index
	return -1


func _SkipReachedNodes(position: Vector2) -> void:
	while not IsEmpty() and _HasReached(position, _path[_nextNodeIndex]):
		_nextNodeIndex += 1


func _HasReached(position: Vector2, node: Vector2) -> bool:
	return position.distance_squared_to(node) <= REACH_DISTANCE * REACH_DISTANCE
