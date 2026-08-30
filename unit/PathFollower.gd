class_name PathFollower
extends RefCounted

const REACH_DISTACNE: float = 1.0
	
var _path: PackedVector2Array = PackedVector2Array()
var _originalPathIndex: int = 0
var _zippedPathIndex: int = 0
var _goal: Vector2 = Vector2.ZERO

func Set(path) -> void:
	_path = path
	_initIndex()
	_goal = path[path.size() - 1]

func Clear() -> void:
	_path.clear()
	_initIndex()
	_goal = Vector2.ZERO
	
func _initIndex() -> void:
	_originalPathIndex = 0
	_zippedPathIndex = 0
	
	
func IsEmpty() -> bool:
	return _path.is_empty()

func GetDesirePosition(curPosition: Vector2, speed: float) -> Vector2:
	if IsEmpty():
		return curPosition
	
	var curWaypoint: Vector2 = _path[_pathIndex]
	var remainDistance = curWaypoint - curPosition
	var maxDelta = remainDistance.normalized() * speed
	return maxDelta if remainDistance.length() > maxDelta.length() else remainDistance

func _getCurrentWaypoint() -> Vector2:
	return _path[_pathIndex]

func UpdateIndex(curPosition) -> void:
	if (curPosition - _getCurrentWaypoint()).length() > REACH_DISTACNE:
		_pathIndex += 1
		if _pathIndex >= _path.size():
			Clear()
