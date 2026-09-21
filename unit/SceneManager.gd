class_name SceneManager
extends Node

const INVALID_COMMAND_ID: int = -1

var _unitManager: UnitManager
var _stageSnapshot: StageSnapshot

var _movementSimulator: MovementSimulator

var _moveCommandProcessor: MoveCommandProcessor


func IsUnitMoving(unitId: int) -> bool:
	if not _HasUnit(unitId):
		return false

	return _movementSimulator.IsUnitMoving(unitId)


func StopUnit(unitId: int) -> bool:
	if not _HasUnit(unitId):
		return false

	return _movementSimulator.StopUnit(unitId)


func PauseUnit(unitId: int) -> bool:
	if not _HasUnit(unitId):
		return false

	return _movementSimulator.PauseUnit(unitId)


func ResumeUnit(unitId: int) -> bool:
	if not _HasUnit(unitId):
		return false

	return _movementSimulator.ResumeUnit(unitId)


func IssueMoveCommand(units: Array[Unit], targetWorld: Vector2) -> int:
	if _moveCommandProcessor == null or _stageSnapshot == null:
		return INVALID_COMMAND_ID

	var unitIds: PackedInt32Array = _CollectRegisteredUnitIds(units)

	if unitIds.is_empty():
		return INVALID_COMMAND_ID

	var command: MoveCommand = MoveCommand.new(unitIds, targetWorld)

	if not _moveCommandProcessor.Process(command, _stageSnapshot):
		return INVALID_COMMAND_ID

	return command.commandId


func _InitializeUnitRuntime(navigationService: NavigationService, initialCapacity: int) -> bool:
	if navigationService == null or not navigationService.IsReady():
		push_error("SceneManager: NavigationService가 준비되지 않았습니다.")
		return false

	if initialCapacity < 0:
		push_error("SceneManager: initialCapacity는 0 이상이어야 합니다.")
		return false

	_unitManager = UnitManager.new()
	_stageSnapshot = StageSnapshot.new(initialCapacity)

	_movementSimulator = MovementSimulator.new(navigationService, _unitManager)

	_moveCommandProcessor = MoveCommandProcessor.new(navigationService, _movementSimulator)

	return true


func _SimulateUnitRuntime(fixedDelta: float) -> bool:
	if _movementSimulator == null or _stageSnapshot == null:
		return false

	if not _movementSimulator.SimulateTick(_stageSnapshot, fixedDelta):
		return false

	_unitManager.SyncPositions(_stageSnapshot)
	return true


func _RegisterUnitRuntime(unit: Unit, unitId: int, worldPosition: Vector2) -> bool:
	if _unitManager == null or _stageSnapshot == null or _movementSimulator == null:
		push_error("SceneManager: Unit Runtime이 초기화되지 않았습니다.")
		return false

	if not is_instance_valid(unit) or unit.is_queued_for_deletion():
		push_error("SceneManager: 유효하지 않은 Unit은 등록할 수 없습니다.")
		return false

	if unitId < 0 or _unitManager.HasUnit(unitId):
		push_error("SceneManager: 유효하지 않거나 이미 사용 중인 unitId입니다. unitId: " + str(unitId))
		return false

	if not worldPosition.is_finite():
		push_error("SceneManager: Unit의 월드 위치가 유효하지 않습니다.")
		return false

	if not is_finite(unit.moveSpeed) or unit.moveSpeed < 0.0:
		push_error("SceneManager: Unit의 이동 속도는 0 이상의 유효한 값이어야 합니다.")
		return false

	var halfSize: int = unit.GetHalfSize()
	var movementAgent: MovementAgent = MovementAgent.new(
		unitId,
		worldPosition,
		unit.moveSpeed,
		halfSize,
	)

	if not _movementSimulator.RegisterAgent(movementAgent):
		push_error("SceneManager: MovementAgent 등록에 실패했습니다. unitId: " + str(unitId))
		return false

	_stageSnapshot.RegisterUnit(unitId, worldPosition, halfSize)

	if not _stageSnapshot.HasUnit(unitId):
		_movementSimulator.UnregisterAgent(unitId)
		push_error("SceneManager: StageSnapshot 등록에 실패했습니다. unitId: " + str(unitId))
		return false

	if not _unitManager.RegisterUnit(unitId, unit):
		_stageSnapshot.UnregisterUnit(unitId)
		_movementSimulator.UnregisterAgent(unitId)
		push_error("SceneManager: UnitManager 등록에 실패했습니다. unitId: " + str(unitId))
		return false

	unit.unitId = unitId
	_BindUnitRuntime(unit)
	return true


func _UnregisterUnitRuntime(unit: Unit) -> bool:
	if not _IsManagedUnit(unit):
		return false

	var unitId: int = unit.unitId

	_UnbindUnitRuntime(unit)
	_movementSimulator.UnregisterAgent(unitId)
	_stageSnapshot.UnregisterUnit(unitId)
	_unitManager.UnregisterUnit(unitId)
	return true


func _BindUnitRuntime(unit: Unit) -> void:
	if unit == null:
		return

	unit.BindSceneManager(self)

	var moveSpeedChangedCallback: Callable = _OnUnitMoveSpeedChanged.bind(unit)

	if not unit.MoveSpeedChanged.is_connected(moveSpeedChangedCallback):
		unit.MoveSpeedChanged.connect(moveSpeedChangedCallback)


func _UnbindUnitRuntime(unit: Unit) -> void:
	if unit == null:
		return

	var moveSpeedChangedCallback: Callable = _OnUnitMoveSpeedChanged.bind(unit)

	if unit.MoveSpeedChanged.is_connected(moveSpeedChangedCallback):
		unit.MoveSpeedChanged.disconnect(moveSpeedChangedCallback)

	unit.BindSceneManager(null)


func _OnUnitMoveSpeedChanged(moveSpeed: float, unit: Unit) -> void:
	if not _IsManagedUnit(unit):
		return

	if not _movementSimulator.SetMoveSpeed(unit.unitId, moveSpeed):
		push_error("SceneManager: MovementAgent 이동속도 갱신에 실패했습니다. unitId: " + str(unit.unitId))


func _IsManagedUnit(unit: Unit) -> bool:
	if unit == null:
		return false

	if not _HasUnit(unit.unitId):
		return false

	return _unitManager.GetUnit(unit.unitId) == unit


func _HasUnit(unitId: int) -> bool:
	if _unitManager == null or _movementSimulator == null:
		return false

	return _unitManager.HasUnit(unitId)


func _CollectRegisteredUnitIds(units: Array[Unit]) -> PackedInt32Array:
	var unitIds: PackedInt32Array = []

	for unit: Unit in units:
		if not _IsManagedUnit(unit):
			continue

		unitIds.append(unit.unitId)

	return unitIds
