class_name DefenseTargetingManager
extends RefCounted

var _stageSnapshot: StageSnapshot

var _targetByAttacker: Dictionary[Unit, Unit] = { }


func _init(stageSnapshot: StageSnapshot) -> void:
	_stageSnapshot = stageSnapshot


func SetTarget(attacker: Unit, target: Unit) -> bool:
	if attacker == null or target == null:
		return false

	_targetByAttacker[attacker] = target
	return true


func GetTarget(attacker: Unit) -> Unit:
	if attacker == null:
		return null

	return _targetByAttacker.get(attacker, null)


func ClearTarget(attacker: Unit) -> void:
	if attacker == null:
		return

	_targetByAttacker.erase(attacker)


func RemoveUnit(unit: Unit) -> void:
	if unit == null:
		return

	_targetByAttacker.erase(unit)

	var attackers: Array[Unit] = _targetByAttacker.keys()
	for attacker: Unit in attackers:
		if _targetByAttacker[attacker] == unit:
			_targetByAttacker.erase(attacker)


func Clear() -> void:
	_targetByAttacker.clear()


func FindCandidateUnitIds(attacker: Unit, range: int) -> Array[int]:
	if attacker == null or range < 0:
		return []

	if not _stageSnapshot.HasUnit(attacker.unitId):
		return []

	var attackerPosition: Vector2 = _stageSnapshot.GetPosition(attacker.unitId)
	var attackerHalfSize: int = _stageSnapshot.GetHalfSize(attacker.unitId)
	var searchExtent: int = range + attackerHalfSize

	return _stageSnapshot.FindUnitIdsInRect(attackerPosition, Vector2(searchExtent, searchExtent))


func IsWithinRange(attacker: Unit, target: Unit, range: int) -> bool:
	if attacker == null or target == null or range < 0:
		return false

	if not _stageSnapshot.HasUnit(attacker.unitId) or not _stageSnapshot.HasUnit(target.unitId):
		return false

	var distanceSquared: float = GetFootprintDistanceSquared(attacker.unitId, target.unitId)
	return distanceSquared <= range * range


func GetFootprintDistanceSquared(firstUnitId: int, secondUnitId: int) -> float:
	var firstPosition: Vector2 = _stageSnapshot.GetPosition(firstUnitId)
	var secondPosition: Vector2 = _stageSnapshot.GetPosition(secondUnitId)

	var combinedHalfSize: float = float(
		_stageSnapshot.GetHalfSize(firstUnitId) + _stageSnapshot.GetHalfSize(secondUnitId)
	)

	var dx: float = maxf(absf(firstPosition.x - secondPosition.x) - combinedHalfSize, 0.0)
	var dy: float = maxf(absf(firstPosition.y - secondPosition.y) - combinedHalfSize, 0.0)
	return dx * dx + dy * dy
