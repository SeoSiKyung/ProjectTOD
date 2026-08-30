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
var _needsShortcutRefresh: bool = false


func SetPath(path: PackedVector2Array) -> void:
	_path = path
	_initIndex()

func ClearPath() -> void:
	_path.clear()
	_initIndex()

func _initIndex() -> void:
	_originalPathIndex = 0
	_shortcutIndex = 0
	_goalIndex = _path.size() - 1
	_needsShortcutRefresh = not _path.is_empty()


func GetDesiredPosition(curPosition: Vector2, maxDistance: float) -> Vector2:
	if IsEmpty():
		return curPosition
		
	var curWaypoint: Vector2 = _path[_shortcutIndex]
	var remainDistance: Vector2 = curWaypoint - curPosition
	var maxDelta: Vector2 = remainDistance.normalized() * maxDistance
	return curPosition + maxDelta if remainDistance.length() > maxDelta.length() else curPosition + remainDistance
	
func IsEmpty() -> bool:
	return _path.is_empty()


func OnMovementCommitted(curPosition: Vector2, halfSize: int) -> void:
	if IsEmpty():
		return

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
	var shortcutBlocked: bool = (
		_navigationService != null
		and not _navigationService.SegmentClear(curPosition, _path[_shortcutIndex], halfSize)
	)
	if _needsShortcutRefresh or _IsReached(curPosition, _path[_shortcutIndex]) or shortcutBlocked:
		_needsShortcutRefresh = false
		_FindNextShortcutIndex(curPosition, halfSize)

func _FindNextShortcutIndex(curPosition: Vector2, halfSize: int) -> bool:
	if _navigationService == null:
		_shortcutIndex = _originalPathIndex
		return true

	for idx in range(_goalIndex, _originalPathIndex - 1, -1):
		if _navigationService.SegmentClear(curPosition, _path[idx], halfSize):
			_shortcutIndex = idx
			return true
	return false

func _IsReached(pos1: Vector2, pos2: Vector2) -> bool:
	return (pos1 - pos2).length() < REACH_DISTANCE
