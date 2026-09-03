class_name OffenseSceneManager
extends Node

const INVALID_UNIT_ID: int = -1
const MAX_INT32_VALUE: int = 2147483647

@export_group("Scene")
@export var unitRoot: Node2D

@export_group("Navigation")
@export var navigationData: NavigationData
@export_range(0.0, 2.0, 0.05) var navigationStaticContactSlop: float = 1.0
@export_range(8, 256, 8) var navigationLocalSearchMarginCells: int = 64
@export_range(8, 256, 8) var navigationAnchorConnectionCacheCapacity: int = 64
@export var navigationProfileEnabled: bool = true

@export_group("Simulation")
@export_range(0, 100000, 1) var initialUnitCapacity: int = StageSnapshot.DEFAULT_SLOT_CAPACITY

var _unitManager: UnitManager
var _navigationService: NavigationService
var _movementSimulator: MovementSimulator
var _stageSnapshot: StageSnapshot

var _nextUnitId: int = 0
var _pendingDestroyUnitIds: PackedInt32Array = []
var _isInitialized: bool = false
var _isProcessingTick: bool = false


func _ready() -> void:
	set_physics_process(false)
	_initializeSystems()


func _physics_process(fixedDelta: float) -> void:
	if not _isInitialized:
		return

	_isProcessingTick = true

	_flushPendingDestroyUnits()
	_flushPendingDestroyUnits()

	var movementSucceeded: bool = _movementSimulator.SimulateTick(_stageSnapshot, fixedDelta)

	if movementSucceeded:
		_unitManager.SyncPositions(_stageSnapshot)

	_isProcessingTick = false


func _exit_tree() -> void:
	_shutdownSystems()


func RegisterUnit(unit: Unit, worldPosition: Vector2, moveSpeed: int) -> int:
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

	if unit.get_parent() != null:
		push_error("등록할 Unit은 아직 SceneTree에 추가되지 않은 상태여야 합니다.")
		return INVALID_UNIT_ID

	if not worldPosition.is_finite():
		push_error("Unit의 월드 위치가 유효하지 않습니다.")
		return INVALID_UNIT_ID

	if moveSpeed < 0:
		push_error("Unit의 이동 속도는 0 이상이어야 합니다.")
		return INVALID_UNIT_ID

	if _nextUnitId > MAX_INT32_VALUE:
		push_error("더 이상 새로운 unitId를 발급할 수 없습니다.")
		return INVALID_UNIT_ID

	var unitId: int = _nextUnitId
	var halfSize: int = unit.GetHalfSize()
	var movementAgent: MovementAgent = MovementAgent.new(unitId, worldPosition, moveSpeed, halfSize)

	if not _movementSimulator.RegisterAgent(movementAgent):
		return INVALID_UNIT_ID

	_stageSnapshot.RegisterUnit(unitId, worldPosition, halfSize)

	if not _stageSnapshot.HasUnit(unitId):
		_movementSimulator.UnregisterAgent(unitId)
		push_error("StageSnapshot에 Unit을 등록하지 못했습니다.")
		return INVALID_UNIT_ID

	var previousUnitId: int = unit.unitId
	var previousLocalPosition: Vector2 = unit.position

	unit.unitId = unitId
	unit.position = unitRoot.to_local(worldPosition)

	if not _unitManager.RegisterUnit(unitId, unit):
		unit.unitId = previousUnitId
		unit.position = previousLocalPosition
		_stageSnapshot.UnregisterUnit(unitId)
		_movementSimulator.UnregisterAgent(unitId)
		return INVALID_UNIT_ID

	_nextUnitId += 1
	unitRoot.add_child(unit)

	if unit.get_parent() != unitRoot or unit.is_queued_for_deletion():
		_unitManager.UnregisterUnit(unitId)
		_stageSnapshot.UnregisterUnit(unitId)
		_movementSimulator.UnregisterAgent(unitId)

		if not unit.is_queued_for_deletion():
			unit.unitId = previousUnitId
			unit.position = previousLocalPosition

		push_error("Unit을 UnitRoot에 추가하지 못했습니다.")
		return INVALID_UNIT_ID

	unit.global_position = worldPosition

	return unitId


func DestroyUnit(unitId: int) -> bool:
	if not _isInitialized or not _unitManager.HasUnit(unitId):
		return false

	if _isProcessingTick:
		if not _pendingDestroyUnitIds.has(unitId):
			_pendingDestroyUnitIds.append(unitId)

		return true

	return _destroyUnitImmediately(unitId)


func SetUnitPath(unitId: int, path: PackedVector2Array) -> bool:
	if not _isInitialized or not _unitManager.HasUnit(unitId):
		return false

	return _movementSimulator.SetPath(unitId, path)


func StopUnit(unitId: int) -> bool:
	if not _isInitialized or not _unitManager.HasUnit(unitId):
		return false

	return _movementSimulator.StopUnit(unitId)


func TeleportUnit(unitId: int, worldPosition: Vector2) -> bool:
	if not _isInitialized or _isProcessingTick or not _unitManager.HasUnit(unitId):
		return false

	if not worldPosition.is_finite():
		return false

	if not _movementSimulator.TeleportUnit(unitId, worldPosition, _stageSnapshot):
		return false

	var unit: Unit = _unitManager.GetUnit(unitId)

	if is_instance_valid(unit):
		unit.global_position = worldPosition

	return true


func Clear() -> void:
	if not _isInitialized:
		return

	if _isProcessingTick:
		push_error("틱 처리 중에는 OffenseSceneManager를 비울 수 없습니다.")
		return

	_pendingDestroyUnitIds.clear()
	var unitIds: Array[int] = _stageSnapshot.GetUnitIds()

	unitIds.sort()

	for unitId: int in unitIds:
		_destroyUnitImmediately(unitId)

	_movementSimulator.Clear()
	_stageSnapshot.Clear()
	_unitManager.Clear()


func _initializeSystems() -> void:
	if not is_instance_valid(unitRoot):
		push_error("OffenseSceneManager에 UnitRoot가 지정되지 않았습니다.")
		return

	if unitRoot.is_queued_for_deletion() or not unitRoot.is_inside_tree():
		push_error("UnitRoot는 SceneTree에 등록된 유효한 Node2D여야 합니다.")
		return

	if navigationData == null:
		push_error("OffenseSceneManager에 NavigationData가 지정되지 않았습니다.")
		return

	_navigationService = NavigationService.new()
	_navigationService.navigationData = navigationData
	_navigationService.staticContactSlop = navigationStaticContactSlop
	_navigationService.localSearchMarginCells = navigationLocalSearchMarginCells
	_navigationService.anchorConnectionCacheCapacity = navigationAnchorConnectionCacheCapacity
	_navigationService.navigationProfileEnabled = navigationProfileEnabled
	_navigationService.Reload()

	if not _navigationService.IsReady():
		push_error("NavigationService 초기화에 실패했습니다.")
		_navigationService = null
		return

	_unitManager = UnitManager.new()
	_stageSnapshot = StageSnapshot.new(initialUnitCapacity)
	_movementSimulator = MovementSimulator.new(_navigationService)
	_isInitialized = true
	set_physics_process(true)


func _flushPendingDestroyUnits() -> void:
	if _pendingDestroyUnitIds.is_empty():
		return

	_pendingDestroyUnitIds.sort()

	for unitId: int in _pendingDestroyUnitIds:
		_destroyUnitImmediately(unitId)

	_pendingDestroyUnitIds.clear()


func _destroyUnitImmediately(unitId: int) -> bool:
	if not _unitManager.HasUnit(unitId):
		return false

	_movementSimulator.UnregisterAgent(unitId)
	_stageSnapshot.UnregisterUnit(unitId)

	var unit: Unit = _unitManager.UnregisterUnit(unitId)

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
	_movementSimulator = null
	_stageSnapshot = null
	_unitManager = null
	_navigationService = null
	_isInitialized = false
	_isProcessingTick = false
