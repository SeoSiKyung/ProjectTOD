class_name MoveCommandProcessor
extends RefCounted

var _movePlanner: MovePlanner
var _navigationService: NavigationService
var _movementSimulator: MovementSimulator


func _init(movePlanner: MovePlanner, navigationService: NavigationService, movementSimulator: MovementSimulator) -> void:
	_movePlanner = movePlanner
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

	var destinations: PackedVector2Array = _movePlanner.Plan(unitIds, command.targetWorld, snapshot)

	if destinations.size() != unitIds.size():
		push_error("MovePlanner의 결과 수가 이동할 유닛 수와 일치하지 않습니다.")
		return false

	var paths: Array[PackedVector2Array] = []
	paths.resize(unitIds.size())

	for index: int in range(unitIds.size()):
		var unitId: int = unitIds[index]
		var startPosition: Vector2 = snapshot.GetPosition(unitId)
		var halfSize: int = snapshot.GetHalfSize(unitId)
		var destination: Vector2 = destinations[index]

		if not destination.is_finite():
			push_error("unitId %d의 목적지가 유효하지 않습니다." % unitId)
			return false

		paths[index] = _navigationService.FindPath(startPosition, destination, halfSize)

	var succeeded: bool = true

	for index: int in range(unitIds.size()):
		var unitId: int = unitIds[index]

		if _movementSimulator.SetPath(unitId, paths[index]):
			continue

		push_error("unitId %d에 이동 경로를 설정하지 못했습니다." % unitId)
		succeeded = false

	return succeeded


func _hasValidDependencies() -> bool:
	if not is_instance_valid(_movePlanner):
		push_error("MoveCommandProcessor에 MovePlanner가 없습니다.")
		return false

	if not is_instance_valid(_navigationService):
		push_error("MoveCommandProcessor에 NavigationService가 없습니다.")
		return false

	if not is_instance_valid(_movementSimulator):
		push_error("MoveCommandProcessor에 MovementSimulator가 없습니다.")
		return false

	return true


func _collectExistingUnitIds(sourceUnitIds: PackedInt32Array, snapshot: StageSnapshot) -> PackedInt32Array:
	var unitIds: PackedInt32Array = []

	for unitId: int in sourceUnitIds:
		if snapshot.HasUnit(unitId):
			unitIds.append(unitId)

	return unitIds
