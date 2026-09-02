class_name PathFollower
extends RefCounted

const REACH_DISTANCE: float = 1.0
static var _navigationService: NavigationService

static func SetNavigationService(naviService: NavigationService) -> void:
	_navigationService = naviService
	
static func ClearNavigationService(naviService: NavigationService) -> void:
	if _navigationService == naviService:
		_navigationService = null

var _path: PackedVector2Array = PackedVector2Array()
var _originalPathIndex: int = 0
var _shortcutIndex: int = 0
var _goalIndex: int = 0

func SetPath(path) -> void:
	_path = path
	_initIndex()

func ClearPath() -> void:
	_path.clear()
	_initIndex()

func _initIndex() -> void:
	_originalPathIndex = 0
	_shortcutIndex = 0
	_goalIndex = _path.size() - 1


func GetDesirePosition(curPosition: Vector2, speed: float) -> Vector2:
	if IsEmpty():
		return curPosition
	
	var curWaypoint: Vector2 = _path[_shortcutIndex]
	var remainDistance = curWaypoint - curPosition
	var maxDelta = remainDistance.normalized() * speed
	return maxDelta if remainDistance.length() > maxDelta.length() else remainDistance
	
func IsEmpty() -> bool:
	return _path.is_empty()


func OnMovementCommitted(curPosition, halfSize) -> void:
	if _IsReached(curPosition, _path[_goalIndex]):
		ClearPath()
		return
	
	_UpdateIndex(curPosition, halfSize)
	
func _UpdateIndex(curPosition: Vector2, halfSize: int) -> void:
	_UpdateOriginalPathIndex(curPosition)
	_UpdateShortcutIndex(curPosition, halfSize)
	if _originalPathIndex > _goalIndex:
		ClearPath()

func _UpdateOriginalPathIndex(curPosition: Vector2) -> void:
	var target: Vector2 = _path[_shortcutIndex] - curPosition
	var candidateIdx: int = _originalPathIndex
	for idx in range(_originalPathIndex, _shortcutIndex):
		var check: Vector2 = _path[idx] - curPosition
		if Math.IsOpposite(check, target):
			candidateIdx = idx + 1
		else:
			break
	_originalPathIndex = candidateIdx
	
func _UpdateShortcutIndex(curPosition: Vector2, halfSize: int) -> void:
	if _IsReached(curPosition, _path[_shortcutIndex]):
		_FindNextShortcutIndex(curPosition, halfSize)

func _FindNextShortcutIndex(curPosition: Vector2, halfSize: int) -> bool:
	for idx in range(_goalIndex, _originalPathIndex - 1, -1):
		if _navigationService.SegmentClear(curPosition, _path[idx], halfSize):
			_shortcutIndex = idx
			return true
	return false

func _IsReached(pos1: Vector2, pos2: Vector2) -> bool:
	return (pos1 - pos2).length() < REACH_DISTANCE
