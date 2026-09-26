class_name OffenseSceneManager
extends Node

const INVALID_UNIT_ID: int = -1
const MAX_INT32_VALUE: int = 2147483647

@export_group("Scene")
@export var unitRoot: Node2D

@export_group("Navigation")
@export var navigationData: NavigationData
@export_range(8, 256, 8) var navigationLocalSearchMarginCells: int = 64
@export_range(8, 256, 8) var navigationAnchorConnectionCacheCapacity: int = 64

@export_group("Simulation")
@export_range(0, 100000, 1) var initialUnitCapacity: int = StageSnapshot.DEFAULT_SLOT_CAPACITY

var _navigationService: NavigationService
var _unitRuntime: UnitRuntime

var _nextUnitId: int = 0
var _pendingDestroyUnitIds: PackedInt32Array = []
var _isInitialized: bool = false
var _isProcessingTick: bool = false


func _ready() -> void:
	set_physics_process(false)

	if not _initializeSystems():
		return

	_isInitialized = true
	_registerExistingUnits()

	set_physics_process(true)


func _physics_process(fixedDelta: float) -> void:
	if not _isInitialized:
		return

	_isProcessingTick = true

	_flushPendingDestroyUnits()

	_unitRuntime.Simulate(fixedDelta)

	_isProcessingTick = false


func _exit_tree() -> void:
	_shutdownSystems()


func IsReady() -> bool:
	return _isInitialized


func GetUnit(unitId: int) -> Unit:
	if not _isInitialized:
		return null

	return _unitRuntime.GetUnit(unitId)


func IssueMoveCommand(units: Array[Unit], targetWorld: Vector2) -> int:
	if not _isInitialized or _unitRuntime == null:
		return UnitRuntime.INVALID_COMMAND_ID

	return _unitRuntime.IssueMoveCommand(units, targetWorld)


func RegisterUnit(unit: Unit, worldPosition: Vector2) -> int:
	if not _isInitialized:
		push_error("OffenseSceneManager가 초기화되지 않았습니다.")
		return INVALID_UNIT_ID

	if _isProcessingTick:
		push_error("틱 처리 중에는 Unit을 등록할 수 없습니다.")
		return INVALID_UNIT_ID

	if not is_instance_valid(unit):
		push_error("유효하지 않은 Unit은 등록할 수 없습니다.")
		return INVALID_UNIT_ID

	if unit.is_queued_for_deletion():
		push_error("삭제 대기 중인 Unit은 등록할 수 없습니다.")
		return INVALID_UNIT_ID

	var alreadyInUnitRoot: bool = unit.get_parent() == unitRoot

	if unit.get_parent() != null and not alreadyInUnitRoot:
		push_error("등록할 Unit은 부모가 없거나 UnitRoot의 직접적인 자식이어야 합니다.")
		return INVALID_UNIT_ID

	if _nextUnitId > MAX_INT32_VALUE:
		push_error("더 이상 새로운 unitId를 발급할 수 없습니다.")
		return INVALID_UNIT_ID

	var unitId: int = _nextUnitId
	var previousUnitId: int = unit.unitId
	var previousLocalPosition: Vector2 = unit.position

	if not _unitRuntime.RegisterUnit(unit, unitId, worldPosition):
		return INVALID_UNIT_ID

	unit.position = unitRoot.to_local(worldPosition)
	_nextUnitId += 1

	if not alreadyInUnitRoot:
		unitRoot.add_child(unit)

	if unit.get_parent() != unitRoot or unit.is_queued_for_deletion():
		_unitRuntime.UnregisterUnit(unit)

		if not unit.is_queued_for_deletion():
			unit.unitId = previousUnitId
			unit.position = previousLocalPosition

		push_error("Unit을 UnitRoot에 추가하지 못했습니다.")
		return INVALID_UNIT_ID

	unit.global_position = worldPosition

	return unitId


func DestroyUnit(unitId: int) -> bool:
	if not _isInitialized or not _unitRuntime.HasUnit(unitId):
		return false

	if _isProcessingTick:
		if not _pendingDestroyUnitIds.has(unitId):
			_pendingDestroyUnitIds.append(unitId)

		return true

	return _destroyUnitImmediately(unitId)


func SetUnitPath(unitId: int, path: PackedVector2Array) -> bool:
	if not _isInitialized or not _unitRuntime.HasUnit(unitId):
		return false

	return _unitRuntime.SetPath(unitId, path)


func IssueStopCommand(units: Array[Unit]) -> int:
	if not _isInitialized:
		return INVALID_UNIT_ID

	var stoppedCount: int = 0

	for unitId: int in _unitRuntime.CollectRegisteredUnitIds(units):
		if not _unitRuntime.StopUnit(unitId):
			continue

		var unit: Unit = _unitRuntime.GetUnit(unitId)

		if is_instance_valid(unit) and unit.fsm != null:
			unit.fsm.RequestIdle()

		stoppedCount += 1

	if stoppedCount == 0:
		return INVALID_UNIT_ID

	return stoppedCount


func StopUnits(unitIds: PackedInt32Array) -> void:
	if not _isInitialized:
		return

	for unitId: int in unitIds:
		if _unitRuntime.HasUnit(unitId):
			_unitRuntime.StopUnit(unitId)


func TeleportUnit(unitId: int, worldPosition: Vector2) -> bool:
	if not _isInitialized or _isProcessingTick or not _unitRuntime.HasUnit(unitId):
		return false

	if not worldPosition.is_finite():
		return false

	return _unitRuntime.TeleportUnit(unitId, worldPosition)


func Clear() -> void:
	if not _isInitialized:
		return

	if _isProcessingTick:
		push_error("틱 처리 중에는 OffenseSceneManager를 비울 수 없습니다.")
		return

	_pendingDestroyUnitIds.clear()
	var unitIds: Array[int] = _unitRuntime.GetStageSnapshot().GetUnitIds()

	unitIds.sort()

	for unitId: int in unitIds:
		_destroyUnitImmediately(unitId)

	_unitRuntime.Clear()


func _initializeSystems() -> bool:
	if not is_instance_valid(unitRoot):
		push_error("OffenseSceneManager에 UnitRoot가 지정되지 않았습니다.")
		return false

	if unitRoot.is_queued_for_deletion() or not unitRoot.is_inside_tree():
		push_error("UnitRoot는 SceneTree에 등록된 유효한 Node2D여야 합니다.")
		return false

	if navigationData == null:
		push_error("OffenseSceneManager에 NavigationData가 지정되지 않았습니다.")
		return false

	_navigationService = NavigationService.new()
	_navigationService.navigationData = navigationData
	_navigationService.localSearchMarginCells = navigationLocalSearchMarginCells
	_navigationService.anchorConnectionCacheCapacity = navigationAnchorConnectionCacheCapacity
	_navigationService.Reload()

	if not _navigationService.IsReady():
		push_error("NavigationService 초기화에 실패했습니다.")
		_navigationService = null
		return false

	_unitRuntime = UnitRuntime.new()
	return _unitRuntime.Initialize(_navigationService, initialUnitCapacity)


func _registerExistingUnits() -> void:
	var existingUnits: Array[Unit] = []

	for child: Node in unitRoot.get_children():
		if child is Unit:
			existingUnits.append(child as Unit)

	for unit: Unit in existingUnits:
		var unitId: int = RegisterUnit(unit, unit.global_position)
		if unitId < 0:
			push_error("UnitRoot의 Unit을 등록하지 못했습니다: %s" % unit.name)


func _flushPendingDestroyUnits() -> void:
	if _pendingDestroyUnitIds.is_empty():
		return

	_pendingDestroyUnitIds.sort()

	for unitId: int in _pendingDestroyUnitIds:
		_destroyUnitImmediately(unitId)

	_pendingDestroyUnitIds.clear()


func _destroyUnitImmediately(unitId: int) -> bool:
	if not _unitRuntime.HasUnit(unitId):
		return false

	var unit: Unit = _unitRuntime.GetUnit(unitId)
	if not _unitRuntime.UnregisterUnit(unit):
		return false

	if is_instance_valid(unit):
		unit.process_mode = Node.PROCESS_MODE_DISABLED

		if not unit.is_queued_for_deletion():
			unit.queue_free()

	return true


func _shutdownSystems() -> void:
	set_physics_process(false)

	if _isInitialized:
		_isProcessingTick = false
		Clear()
	else:
		_pendingDestroyUnitIds.clear()

	PathFollower.SetNavigationService(null)
	_unitRuntime = null
	_navigationService = null
	_isInitialized = false
	_isProcessingTick = false
