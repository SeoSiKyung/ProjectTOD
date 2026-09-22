class_name DefenseTargetingManager
extends RefCounted

var _unitManager: UnitManager
var _stageSnapshot: StageSnapshot

var _unitGroupManager: DefenseUnitGroupManager
var _monsterManager: DefenseMonsterManager
var _cpManager: DefenseCPManager

var _targetByAttacker: Dictionary[Unit, Unit] = { }


func _init(
	unitManager: UnitManager,
	stageSnapshot: StageSnapshot,
	unitGroupManager: DefenseUnitGroupManager,
	monsterManager: DefenseMonsterManager,
	cpManager: DefenseCPManager,
) -> void:
	_unitManager = unitManager
	_stageSnapshot = stageSnapshot

	_unitGroupManager = unitGroupManager
	_monsterManager = monsterManager
	_cpManager = cpManager


func SetTarget(attacker: Unit, target: Unit) -> bool:
	if not IsValidTarget(attacker, target):
		return false

	_targetByAttacker[attacker] = target
	return true


func GetTarget(attacker: Unit) -> Unit:
	if attacker == null:
		return null

	var target: Unit = _targetByAttacker.get(attacker)
	if target == null:
		return null

	if not IsValidTarget(attacker, target):
		_targetByAttacker.erase(attacker)
		return null

	return target


func ClearTarget(attacker: Unit) -> void:
	_targetByAttacker.erase(attacker)


func RemoveUnit(unit: Unit) -> void:
	if unit == null:
		return

	_targetByAttacker.erase(unit)

	var attackers: Array[Unit] = _targetByAttacker.keys()
	for attacker: Unit in attackers:
		if _targetByAttacker.get(attacker) == unit:
			_targetByAttacker.erase(attacker)


func Clear() -> void:
	_targetByAttacker.clear()


func FindNearestEnemyInAcquisitionRange(attacker: Unit) -> Unit:
	var attackerStatus: DefenseCharacterStatus = _GetCharacterStatus(attacker)
	if attackerStatus == null or attackerStatus.IsDead():
		return null

	return _FindNearestEnemy(attacker, attackerStatus.acquisitionRange)


func IsInAttackRange(attacker: Unit, target: Unit) -> bool:
	if not IsValidTarget(attacker, target):
		return false

	var attackerStatus: DefenseCharacterStatus = _GetCharacterStatus(attacker)
	if attackerStatus == null:
		return false

	return _IsWithinRange(attacker, target, attackerStatus.atkRange)


func IsInAcquisitionRange(attacker: Unit, target: Unit) -> bool:
	if not IsValidTarget(attacker, target):
		return false

	var attackerStatus: DefenseCharacterStatus = _GetCharacterStatus(attacker)
	if attackerStatus == null:
		return false

	return _IsWithinRange(attacker, target, attackerStatus.acquisitionRange)


func IsValidTarget(attacker: Unit, target: Unit) -> bool:
	if not _IsManagedUnit(attacker) or not _IsManagedUnit(target):
		return false

	if attacker == target:
		return false

	var attackerStatus: DefenseCharacterStatus = _GetCharacterStatus(attacker)
	if attackerStatus == null or attackerStatus.IsDead():
		return false

	var cp: DefenseCP = _cpManager.GetCP()
	if target == cp:
		var cpStatus: DefenseCPStatus = _cpManager.GetStatus()
		return (
			attackerStatus.characterType == CharacterData.CharacterType.MONSTER
			and cpStatus != null and not cpStatus.IsDestroyed()
		)

	var targetStatus: DefenseCharacterStatus = _GetCharacterStatus(target)
	if targetStatus == null or targetStatus.IsDead():
		return false

	return attackerStatus.characterType != targetStatus.characterType


func _FindNearestEnemy(attacker: Unit, range: int) -> Unit:
	if not _IsManagedUnit(attacker):
		return null

	if range < 0:
		return null

	var attackerPosition: Vector2 = _stageSnapshot.GetPosition(attacker.unitId)
	var attackerHalfSize: int = _stageSnapshot.GetHalfSize(attacker.unitId)

	var searchExtent: int = range + attackerHalfSize

	var candidateIds: Array[int] = _stageSnapshot.FindUnitIdsInRect(
		attackerPosition,
		Vector2(searchExtent, searchExtent),
	)

	var nearestTarget: Unit = null
	var nearestDistanceSquared: float = INF
	var nearestUnitId: int = -1

	for unitId: int in candidateIds:
		if unitId == attacker.unitId:
			continue

		var candidate: Unit = _unitManager.GetUnit(unitId)
		if not IsValidTarget(attacker, candidate):
			continue

		# CP는 기본 목적지로 따로 취급하고, acquisition 탐색에서는 일반 적 캐릭터만 찾는다.
		if candidate == _cpManager.GetCP():
			continue

		var distanceSquared: float = _GetFootprintDistanceSquared(attacker.unitId, candidate.unitId)
		if distanceSquared > range * range:
			continue

		if (
			nearestTarget == null or distanceSquared < nearestDistanceSquared
			or (is_equal_approx(distanceSquared, nearestDistanceSquared) and unitId < nearestUnitId)
		):
			nearestTarget = candidate
			nearestDistanceSquared = distanceSquared
			nearestUnitId = unitId

	return nearestTarget


func _IsWithinRange(attacker: Unit, target: Unit, range: int) -> bool:
	if range < 0:
		return false

	var distanceSquared: float = _GetFootprintDistanceSquared(attacker.unitId, target.unitId)
	return distanceSquared <= range * range


func _GetFootprintDistanceSquared(firstUnitId: int, secondUnitId: int) -> float:
	var firstPosition: Vector2 = _stageSnapshot.GetPosition(firstUnitId)
	var secondPosition: Vector2 = _stageSnapshot.GetPosition(secondUnitId)

	var combinedHalfSize: float = float(
		_stageSnapshot.GetHalfSize(firstUnitId) + _stageSnapshot.GetHalfSize(secondUnitId)
	)

	var dx: float = maxf(absf(firstPosition.x - secondPosition.x) - combinedHalfSize, 0.0)
	var dy: float = maxf(absf(firstPosition.y - secondPosition.y) - combinedHalfSize, 0.0)
	return dx * dx + dy * dy


func _GetCharacterStatus(character: Unit) -> DefenseCharacterStatus:
	var status: DefenseCharacterStatus = _unitGroupManager.GetStatusByCharacter(character)
	if status != null:
		return status

	return _monsterManager.GetStatusByCharacter(character)


func _IsManagedUnit(unit: Unit) -> bool:
	if unit == null:
		return false

	if not _unitManager.HasUnit(unit.unitId):
		return false

	if not _stageSnapshot.HasUnit(unit.unitId):
		return false

	return _unitManager.GetUnit(unit.unitId) == unit
