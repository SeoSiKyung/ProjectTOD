class_name MoveCommandProcessor
extends RefCounted

const ARRIVAL_GAP: float = 2.0
const ARRIVAL_RADIUS_SCALE: float = 1.15

var _navigationService: NavigationService
var _movementSimulator: MovementSimulator
var _nextGeneratedCommandId: int = 0


class PathGroup:
	var halfSize: int = 0
	var unitIndices: Array[int] = []


func _init(navigationService: NavigationService, movementSimulator: MovementSimulator) -> void:
	_navigationService = navigationService
	_movementSimulator = movementSimulator


func Process(command: MoveCommand, snapshot: StageSnapshot) -> bool:
	if not is_instance_valid(command):
		push_error("MoveCommandProcessor에 MoveCommand가 없습니다.")
		return false

	if not is_instance_valid(snapshot):
		push_error("MoveCommandProcessor에 StageSnapshot이 없습니다.")
		return false

	if not _hasValidDependencies():
		return false

	if not _navigationService.IsReady():
		push_error("NavigationService가 준비되지 않았습니다.")
		return false

	if not command.targetWorld.is_finite():
		push_error("MoveCommand의 목적지가 유효하지 않습니다.")
		return false

	var unitIds: PackedInt32Array = _collectExistingUnitIds(command.unitIds, snapshot)

	if unitIds.is_empty():
		return false

	var paths: Array[PackedVector2Array] = []
	var targets: PackedVector2Array = []
	var pathReady: PackedByteArray = []
	var groups: Dictionary = {}
	var groupKeys: Array[Vector2i] = []

	for _index: int in range(unitIds.size()):
		paths.append(PackedVector2Array())
		targets.append(Vector2.ZERO)

	pathReady.resize(unitIds.size())
	pathReady.fill(0)

	for index: int in range(unitIds.size()):
		var unitId: int = unitIds[index]
		var startPosition: Vector2 = snapshot.GetPosition(unitId)
		var halfSize: int = snapshot.GetHalfSize(unitId)

		if not startPosition.is_finite():
			push_error("unitId %d의 위치가 유효하지 않습니다." % unitId)
			continue

		var componentId: int = _navigationService.GetComponentId(startPosition, halfSize)
		if componentId < 0:
			push_error("unitId %d가 이동 가능한 Component에 없습니다." % unitId)
			continue

		var groupKey: Vector2i = Vector2i(halfSize, componentId)
		var group: PathGroup = groups.get(groupKey) as PathGroup
		if group == null:
			group = PathGroup.new()
			group.halfSize = halfSize
			groups[groupKey] = group
			groupKeys.append(groupKey)

		group.unitIndices.append(index)

	for groupKey: Vector2i in groupKeys:
		var group: PathGroup = groups[groupKey] as PathGroup
		var groupStarts: PackedVector2Array = []

		for unitIndex: int in group.unitIndices:
			groupStarts.append(snapshot.GetPosition(unitIds[unitIndex]))

		var target: Vector2 = _navigationService.GetNearestReachablePoint(
			command.targetWorld,
			group.halfSize,
			groupStarts[0],
		)
		var groupPaths: Array[PackedVector2Array] = _navigationService.BuildPaths(
			groupStarts,
			target,
			group.halfSize,
		)

		if groupPaths.size() != group.unitIndices.size():
			push_error("NavigationService의 경로 수가 이동 그룹의 유닛 수와 일치하지 않습니다.")
			continue

		for groupIndex: int in range(group.unitIndices.size()):
			var unitIndex: int = group.unitIndices[groupIndex]
			paths[unitIndex] = groupPaths[groupIndex]
			targets[unitIndex] = target
			pathReady[unitIndex] = 1

	var commandId: int = _resolveCommandId(command)
	var arrivalRadius: float = _calculateArrivalRadius(unitIds, snapshot)

	var succeeded: bool = true

	for index: int in range(unitIds.size()):
		var unitId: int = unitIds[index]

		if pathReady[index] == 0 or paths[index].is_empty():
			_movementSimulator.StopUnit(unitId)
			push_error("unitId %d의 이동 경로를 생성하지 못했습니다." % unitId)
			succeeded = false
			continue

		if _movementSimulator.SetMoveCommand(
			unitId,
			paths[index],
			commandId,
			targets[index],
			arrivalRadius,
		):
			continue

		push_error("unitId %d에 이동 경로를 설정하지 못했습니다." % unitId)
		succeeded = false

	return succeeded


func _hasValidDependencies() -> bool:
	if not is_instance_valid(_navigationService):
		push_error("MoveCommandProcessor에 NavigationService가 없습니다.")
		return false

	if not is_instance_valid(_movementSimulator):
		push_error("MoveCommandProcessor에 MovementSimulator가 없습니다.")
		return false

	return true


func _resolveCommandId(command: MoveCommand) -> int:
	if command.commandId >= 0:
		_nextGeneratedCommandId = maxi(_nextGeneratedCommandId, command.commandId + 1)
		return command.commandId

	command.commandId = _nextGeneratedCommandId
	_nextGeneratedCommandId += 1
	return command.commandId


func _calculateArrivalRadius(unitIds: PackedInt32Array, snapshot: StageSnapshot) -> float:
	var occupiedArea: float = 0.0

	for unitId: int in unitIds:
		var diameter: float = float(snapshot.GetHalfSize(unitId) * 2) + ARRIVAL_GAP
		occupiedArea += diameter * diameter

	return sqrt(occupiedArea / PI) * ARRIVAL_RADIUS_SCALE


func _collectExistingUnitIds(sourceUnitIds: PackedInt32Array, snapshot: StageSnapshot) -> PackedInt32Array:
	var unitIds: PackedInt32Array = []

	for unitId: int in sourceUnitIds:
		if snapshot.HasUnit(unitId):
			unitIds.append(unitId)

	return unitIds
