class_name UnitRuntime
extends RefCounted

const INVALID_COMMAND_ID: int = -1

var _unitManager: UnitManager
var _stageSnapshot: StageSnapshot
var _movementSimulator: MovementSimulator
var _moveCommandProcessor: MoveCommandProcessor


func Initialize(navigationService: NavigationService, initialCapacity: int) -> bool:
	if navigationService == null or not navigationService.IsReady():
		push_error("UnitRuntime: NavigationService가 준비되지 않았습니다.")
		return false

	if initialCapacity < 0:
		push_error("UnitRuntime: initialCapacity는 0 이상이어야 합니다.")
		return false

	_unitManager = UnitManager.new()
	_stageSnapshot = StageSnapshot.new(initialCapacity)
	_movementSimulator = MovementSimulator.new(navigationService, _unitManager)
	_moveCommandProcessor = MoveCommandProcessor.new(navigationService, _movementSimulator)
	return true


func IsReady() -> bool:
	return (
		_unitManager != null and _stageSnapshot != null
		and _movementSimulator != null and _moveCommandProcessor != null
	)


func GetStageSnapshot() -> StageSnapshot:
	return _stageSnapshot


func GetUnit(unitId: int) -> Unit:
	if _unitManager == null:
		return null

	return _unitManager.GetUnit(unitId)


func HasUnit(unitId: int) -> bool:
	return _unitManager != null and _unitManager.HasUnit(unitId)


func IsManagedUnit(unit: Unit) -> bool:
	if unit == null or not HasUnit(unit.unitId):
		return false

	return _unitManager.GetUnit(unit.unitId) == unit


func IsUnitMoving(unitId: int) -> bool:
	if not HasUnit(unitId):
		return false

	return _movementSimulator.IsUnitMoving(unitId)


func StopUnit(unitId: int) -> bool:
	if not HasUnit(unitId):
		return false

	return _movementSimulator.StopUnit(unitId)


func PauseUnit(unitId: int) -> bool:
	if not HasUnit(unitId):
		return false

	return _movementSimulator.PauseUnit(unitId)


func ResumeUnit(unitId: int) -> bool:
	if not HasUnit(unitId):
		return false

	return _movementSimulator.ResumeUnit(unitId)


func SetPath(unitId: int, path: PackedVector2Array) -> bool:
	if not HasUnit(unitId):
		return false

	return _movementSimulator.SetPath(unitId, path)


func TeleportUnit(unitId: int, worldPosition: Vector2) -> bool:
	if not HasUnit(unitId) or not worldPosition.is_finite():
		return false

	if not _movementSimulator.TeleportUnit(unitId, worldPosition, _stageSnapshot):
		return false

	var unit: Unit = _unitManager.GetUnit(unitId)
	if is_instance_valid(unit):
		unit.global_position = worldPosition

	return true


func IssueMoveCommand(units: Array[Unit], targetWorld: Vector2) -> int:
	if _moveCommandProcessor == null or _stageSnapshot == null:
		return INVALID_COMMAND_ID

	var unitIds: PackedInt32Array = CollectRegisteredUnitIds(units)
	if unitIds.is_empty():
		return INVALID_COMMAND_ID

	var command: MoveCommand = MoveCommand.new(unitIds, targetWorld)
	if not _moveCommandProcessor.Process(command, _stageSnapshot):
		return INVALID_COMMAND_ID

	return command.commandId


func Simulate(fixedDelta: float) -> bool:
	if _movementSimulator == null or _stageSnapshot == null or _unitManager == null:
		return false

	if not _movementSimulator.SimulateTick(_stageSnapshot, fixedDelta):
		return false

	_unitManager.SyncPositions(_stageSnapshot)
	return true


func RegisterUnit(unit: Unit, unitId: int, worldPosition: Vector2) -> bool:
	if not IsReady():
		push_error("UnitRuntime: Runtime이 초기화되지 않았습니다.")
		return false

	if not is_instance_valid(unit) or unit.is_queued_for_deletion():
		push_error("UnitRuntime: 유효하지 않은 Unit은 등록할 수 없습니다.")
		return false

	if unitId < 0 or _unitManager.HasUnit(unitId):
		push_error("UnitRuntime: 유효하지 않거나 이미 사용 중인 unitId입니다. unitId: " + str(unitId))
		return false

	if not worldPosition.is_finite():
		push_error("UnitRuntime: Unit의 월드 위치가 유효하지 않습니다.")
		return false

	if unit.moveSpeed < 0:
		push_error("UnitRuntime: Unit의 이동 속도는 0 이상의 값이어야 합니다.")
		return false

	var halfSize: int = unit.GetHalfSize()
	var movementAgent: MovementAgent = MovementAgent.new(
		unitId,
		worldPosition,
		unit.moveSpeed,
		halfSize,
	)

	if not _movementSimulator.RegisterAgent(movementAgent):
		push_error("UnitRuntime: MovementAgent 등록에 실패했습니다. unitId: " + str(unitId))
		return false

	_stageSnapshot.RegisterUnit(unitId, worldPosition, halfSize)
	if not _stageSnapshot.HasUnit(unitId):
		_movementSimulator.UnregisterAgent(unitId)
		push_error("UnitRuntime: StageSnapshot 등록에 실패했습니다. unitId: " + str(unitId))
		return false

	if not _unitManager.RegisterUnit(unitId, unit):
		_stageSnapshot.UnregisterUnit(unitId)
		_movementSimulator.UnregisterAgent(unitId)
		push_error("UnitRuntime: UnitManager 등록에 실패했습니다. unitId: " + str(unitId))
		return false

	unit.unitId = unitId
	_BindUnit(unit)
	return true


func UnregisterUnit(unit: Unit) -> bool:
	if not IsManagedUnit(unit):
		return false

	var unitId: int = unit.unitId
	_UnbindUnit(unit)
	_movementSimulator.UnregisterAgent(unitId)
	_stageSnapshot.UnregisterUnit(unitId)
	_unitManager.UnregisterUnit(unitId)
	return true


func CollectRegisteredUnitIds(units: Array[Unit]) -> PackedInt32Array:
	var unitIds: PackedInt32Array = []
	for unit: Unit in units:
		if IsManagedUnit(unit):
			unitIds.append(unit.unitId)

	return unitIds


func Clear() -> void:
	if _unitManager == null:
		return

	var units: Array[Unit] = []
	for unitId: int in _stageSnapshot.GetUnitIds():
		var unit: Unit = _unitManager.GetUnit(unitId)
		if unit != null:
			units.append(unit)

	for unit: Unit in units:
		UnregisterUnit(unit)

	_movementSimulator.Clear()
	_stageSnapshot.Clear()
	_unitManager.Clear()


func _BindUnit(unit: Unit) -> void:
	if unit == null:
		return

	unit.BindUnitRuntime(self)

	var moveSpeedChangedCallback: Callable = _OnUnitMoveSpeedChanged.bind(unit)
	if not unit.MoveSpeedChanged.is_connected(moveSpeedChangedCallback):
		unit.MoveSpeedChanged.connect(moveSpeedChangedCallback)


func _UnbindUnit(unit: Unit) -> void:
	if unit == null:
		return

	var moveSpeedChangedCallback: Callable = _OnUnitMoveSpeedChanged.bind(unit)
	if unit.MoveSpeedChanged.is_connected(moveSpeedChangedCallback):
		unit.MoveSpeedChanged.disconnect(moveSpeedChangedCallback)

	unit.BindUnitRuntime(null)


func _OnUnitMoveSpeedChanged(moveSpeed: int, unit: Unit) -> void:
	if not IsManagedUnit(unit):
		return

	if not _movementSimulator.SetMoveSpeed(unit.unitId, moveSpeed):
		push_error("UnitRuntime: MovementAgent 이동속도 갱신에 실패했습니다. unitId: " + str(unit.unitId))
