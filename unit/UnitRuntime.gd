class_name UnitRuntime
extends RefCounted

const INVALID_COMMAND_ID: int = -1

var _navigationService: NavigationService
var _unitManager: UnitManager
var _stageSnapshot: StageSnapshot
var _movementSimulator: MovementSimulator
var _moveCommandProcessor: MoveCommandProcessor

var _timingCommandMetrics: NavigationProfileMetrics
var _timingMovementMetrics: MovementProfileMetrics
var _timingEnabled: bool = false
var _timingCommandCount: int = 0
var _timingCommandFailures: int = 0
var _timingCommandUnits: int = 0
var _timingCommandUsec: int = 0
var _timingCommandMaxUsec: int = 0
var _timingSlowestUnitId: int = -1
var _timingSlowestUnitCount: int = 0
var _timingSlowestTarget: Vector2
var _timingSlowestStart: Vector2
var _timingSlowestHalfSize: int = 0


func Initialize(navigationService: NavigationService, initialCapacity: int) -> bool:
	if navigationService == null or not navigationService.IsReady():
		push_error("UnitRuntime: NavigationService가 준비되지 않았습니다.")
		return false

	if initialCapacity < 0:
		push_error("UnitRuntime: initialCapacity는 0 이상이어야 합니다.")
		return false

	_navigationService = navigationService
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
	var previousMetrics: NavigationProfileMetrics
	if _timingEnabled:
		if _timingCommandCount == 0:
			_timingCommandMetrics = NavigationProfileMetrics.new()
			_timingCommandMetrics.capturePortalBatchDetails = true
			_timingCommandMetrics.portalBatchTick = Engine.get_physics_frames()
			_moveCommandProcessor.profileMetrics = _timingCommandMetrics
		previousMetrics = _navigationService.GetProfileMetrics()
		_navigationService.SetProfileMetrics(_timingCommandMetrics)
	var commandStart: int = Time.get_ticks_usec() if _timingEnabled else 0
	var succeeded: bool = _moveCommandProcessor.Process(command, _stageSnapshot)
	if _timingEnabled:
		var elapsed: int = Time.get_ticks_usec() - commandStart
		_navigationService.SetProfileMetrics(previousMetrics)
		_timingCommandCount += 1
		_timingCommandUnits += unitIds.size()
		_timingCommandUsec += elapsed
		if not succeeded:
			_timingCommandFailures += 1
		if _timingCommandCount == 1 or elapsed > _timingCommandMaxUsec:
			_timingCommandMaxUsec = elapsed
			_timingSlowestUnitId = unitIds[0]
			_timingSlowestUnitCount = unitIds.size()
			_timingSlowestTarget = targetWorld
			_timingSlowestStart = _stageSnapshot.GetPosition(unitIds[0])
			_timingSlowestHalfSize = _stageSnapshot.GetHalfSize(unitIds[0])
	if not succeeded:
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


func BeginTimingSample(enabled: bool) -> void:
	_movementSimulator.capturePathRebuildTiming = enabled
	_movementSimulator.lastPathRebuildMetrics = null
	if not enabled:
		if _timingEnabled:
			_moveCommandProcessor.profileMetrics = null
			_movementSimulator.ClearProfileMetrics()
		_timingEnabled = false
		return
	if _timingCommandMetrics == null:
		_timingCommandMetrics = NavigationProfileMetrics.new()
		_timingMovementMetrics = MovementProfileMetrics.new()
	if not _timingEnabled:
		_moveCommandProcessor.profileMetrics = _timingCommandMetrics
		_movementSimulator.SetProfileMetrics(_timingMovementMetrics)
	_timingEnabled = true
	_timingCommandCount = 0
	_timingCommandFailures = 0
	_timingCommandUnits = 0
	_timingCommandUsec = 0
	_timingCommandMaxUsec = 0
	_timingSlowestUnitId = -1
	_timingSlowestUnitCount = 0
	_timingSlowestTarget = Vector2.ZERO
	_timingSlowestStart = Vector2.ZERO
	_timingSlowestHalfSize = 0
	_timingCommandMetrics.commandTargetCorrectionUsec = 0
	_timingCommandMetrics.commandBuildPathsUsec = 0
	_timingCommandMetrics.commandAssignmentUsec = 0
	_timingMovementMetrics.pathRebuildUsec = 0
	_timingMovementMetrics.pathRebuildRequests = 0
	_timingMovementMetrics.pathRebuildFailures = 0
	_timingMovementMetrics.captureTickUsec = 0
	_timingMovementMetrics.collisionResolveUsec = 0
	_timingMovementMetrics.commitTickUsec = 0
	_timingMovementMetrics.arrivalResolveUsec = 0


func PrintTimingSample(simulationUsec: int) -> void:
	if not _timingEnabled:
		return
	var correction: int = _timingCommandMetrics.commandTargetCorrectionUsec
	var build: int = _timingCommandMetrics.commandBuildPathsUsec
	var assignment: int = _timingCommandMetrics.commandAssignmentUsec
	print(
		"[디펜스 계측/명령] Process 횟수=%d 유닛합=%d 실패=%d 합계=%.3fms 최대=%.3fms"
		% [
			_timingCommandCount,
			_timingCommandUnits,
			_timingCommandFailures,
			_timingCommandUsec / 1000.0,
			_timingCommandMaxUsec / 1000.0,
		],
		" | 보정=%.3f 경로생성=%.3f 설정=%.3f 나머지=%.3fms"
		% [
			correction / 1000.0,
			build / 1000.0,
			assignment / 1000.0,
			(_timingCommandUsec - correction - build - assignment) / 1000.0,
		],
		" | 최대요청 첫유닛=%d 인원=%d 시작=%s 원래목표=%s 반크기=%d"
		% [
			_timingSlowestUnitId,
			_timingSlowestUnitCount,
			_timingSlowestStart,
			_timingSlowestTarget,
			_timingSlowestHalfSize,
		],
	)
	if _timingCommandCount > 0:
		_PrintNavigationTiming("명령합계", _timingCommandMetrics, build)
	if simulationUsec <= 0:
		return
	var rebuild: int = _timingMovementMetrics.pathRebuildUsec
	var capture: int = _timingMovementMetrics.captureTickUsec
	var collision: int = _timingMovementMetrics.collisionResolveUsec
	var commit: int = _timingMovementMetrics.commitTickUsec
	var arrival: int = _timingMovementMetrics.arrivalResolveUsec
	print(
		"[디펜스 계측/이동] 재탐색=%d회 실패=%d 재탐색=%.3f 캡처=%.3f 충돌=%.3f 위치확정=%.3f 도착처리=%.3f 나머지=%.3fms"
		% [
			_timingMovementMetrics.pathRebuildRequests,
			_timingMovementMetrics.pathRebuildFailures,
			rebuild / 1000.0,
			capture / 1000.0,
			collision / 1000.0,
			commit / 1000.0,
			arrival / 1000.0,
			(simulationUsec - rebuild - capture - collision - commit - arrival) / 1000.0,
		],
	)
	if _movementSimulator.lastPathRebuildMetrics != null:
		print(
			"[디펜스 계측/재탐색대상] 유닛=%d 명령=%d revision=%d 시작=%s Agent목표=%s 반크기=%d 성공=%s 경유점=%d"
			% [
				_movementSimulator.lastPathRebuildUnitId,
				_movementSimulator.lastPathRebuildCommandId,
				_movementSimulator.lastPathRebuildRevision,
				_movementSimulator.lastPathRebuildStart,
				_movementSimulator.lastPathRebuildTarget,
				_movementSimulator.lastPathRebuildHalfSize,
				_movementSimulator.lastPathRebuildSucceeded,
				_movementSimulator.lastPathRebuildWaypointCount,
			],
		)
		_PrintNavigationTiming(
			"재탐색",
			_movementSimulator.lastPathRebuildMetrics,
			_movementSimulator.lastPathRebuildUsec,
		)


func _PrintNavigationTiming(
	label: String,
	metrics: NavigationProfileMetrics,
	totalUsec: int,
) -> void:
	var connectionUsec: int = metrics.startAnchorConnectionUsec + metrics.targetAnchorConnectionUsec
	var coveredUsec: int = (
		metrics.regionLookupUsec + metrics.sameRegionPathUsec + connectionUsec
		+ metrics.anchorGraphUsec + metrics.pathAssemblyUsec + metrics.fallbackGridUsec
	)
	print(
		"[디펜스 계측/경로:%s] 전체=%.3f Region조회=%.3f 동일지역경로=%.3f 시작연결=%.3f 목표연결=%.3f 그래프=%.3f 그래프경로조립=%.3f 최종Grid대체=%.3f 나머지=%.3fms"
		% [
			label,
			totalUsec / 1000.0,
			metrics.regionLookupUsec / 1000.0,
			metrics.sameRegionPathUsec / 1000.0,
			metrics.startAnchorConnectionUsec / 1000.0,
			metrics.targetAnchorConnectionUsec / 1000.0,
			metrics.anchorGraphUsec / 1000.0,
			metrics.pathAssemblyUsec / 1000.0,
			metrics.fallbackGridUsec / 1000.0,
			(totalUsec - coveredUsec) / 1000.0,
		],
	)
	var connectionCoveredUsec: int = (
		metrics.anchorDirectCheckUsec + metrics.anchorProbeUsec
		+ metrics.anchorPortalBatchUsec + metrics.anchorIndividualFallbackUsec
	)
	print(
		"[디펜스 계측/연결내부:%s] 직선=%.3f Probe=%.3f PortalBatch=%.3f 개별대체=%.3f 나머지=%.3fms | Anchor캐시 hit=%d miss=%d 일반Grid=%d회 expanded=%d"
		% [
			label,
			metrics.anchorDirectCheckUsec / 1000.0,
			metrics.anchorProbeUsec / 1000.0,
			metrics.anchorPortalBatchUsec / 1000.0,
			metrics.anchorIndividualFallbackUsec / 1000.0,
			(connectionUsec - connectionCoveredUsec) / 1000.0,
			metrics.anchorCacheHits,
			metrics.anchorCacheMisses,
			metrics.gridSearchCalls,
			metrics.gridExpanded,
		],
	)
	if metrics.portalDetailCalls <= 0:
		return
	print(
		"[디펜스 계측/Batch내부:%s] 호출=%d 준비=%.3f Grid=%.3f 마무리=%.3fms | Grid내부 준비=%.3f 탐색=%.3f 복원=%.3fms"
		% [
			label,
			metrics.portalDetailCalls,
			metrics.portalDetailPreparationUsec / 1000.0,
			metrics.portalDetailGridUsec / 1000.0,
			metrics.portalDetailFinalizationUsec / 1000.0,
			metrics.portalDetailGridPreparationUsec / 1000.0,
			metrics.portalDetailGridSearchUsec / 1000.0,
			metrics.portalDetailGridReconstructionUsec / 1000.0,
		],
	)
	print(
		"[디펜스 계측/최대Batch:%s] 시간=%.3fms 시작=%s Region=%d 목표수=%d expanded=%d relaxed=%d 탐색범위=%d 반환경로=%d 경유점=%d"
		% [
			label,
			metrics.portalDetailWorstUsec / 1000.0,
			metrics.portalDetailWorstStart,
			metrics.portalDetailWorstRegion,
			metrics.portalDetailWorstTargetCount,
			metrics.portalDetailWorstExpanded,
			metrics.portalDetailWorstRelaxed,
			metrics.portalDetailWorstSearchArea,
			metrics.portalDetailWorstGridReturnedPaths,
			metrics.portalDetailWorstGridReconstructedWaypoints,
		],
		" | 내부 Grid=%.3f 탐색=%.3f 복원=%.3fms"
		% [
			metrics.portalDetailWorstGridUsec / 1000.0,
			metrics.portalDetailWorstGridSearchUsec / 1000.0,
			metrics.portalDetailWorstGridReconstructionUsec / 1000.0,
		],
	)
