class_name DefenseTargetSelector
extends RefCounted

var _battleContext: DefenseBattleFacade
var _stageSnapshot: StageSnapshot

var _candidateUnitIdBuffer: PackedInt32Array = []


func _init(battleContext: DefenseBattleFacade, stageSnapshot: StageSnapshot) -> void:
	_battleContext = battleContext
	_stageSnapshot = stageSnapshot

	_candidateUnitIdBuffer.resize(_stageSnapshot.GetSlotCapacity())


func FindDefaultEnemyTarget(enemy: Enemy) -> Unit:
	if enemy == null or not _battleContext.IsManagedUnit(enemy):
		return null

	var policy: TargetPolicy = enemy.GetTargetPolicy()
	if policy == null:
		return null

	var bestTarget: Unit = null
	var bestPriority: int = TargetPolicy.INVALID_PRIORITY
	var bestDistanceSquared: float = INF
	var bestUnitId: int = -1

	var cp: Unit = _battleContext.GetCP()
	if cp != null and _battleContext.IsValidTarget(enemy, cp):
		var cpPriority: int = policy.GetPriority(enemy, cp, TargetPolicy.SelectionContext.DEFAULT)
		if cpPriority != TargetPolicy.INVALID_PRIORITY:
			bestTarget = cp
			bestPriority = cpPriority
			bestDistanceSquared = GetFootprintDistanceSquared(enemy.unitId, cp.unitId)
			bestUnitId = cp.unitId

	var candidateTypes: Array[CharacterType.Type] = [
		CharacterType.TOWER,
		CharacterType.MACHINE,
		CharacterType.TRAP,
	]

	for characterType: CharacterType.Type in candidateTypes:
		var characterCount: int = _battleContext.GetCharacterCount(characterType)
		for index: int in characterCount:
			var candidate: Unit = _battleContext.GetCharacterByIndex(characterType, index)
			if not _battleContext.IsValidTarget(enemy, candidate):
				continue

			var priority: int = policy.GetPriority(
				enemy,
				candidate,
				TargetPolicy.SelectionContext.DEFAULT,
			)
			if priority == TargetPolicy.INVALID_PRIORITY:
				continue

			var distanceSquared: float = GetFootprintDistanceSquared(enemy.unitId, candidate.unitId)
			if _IsBetterTarget(
				priority,
				distanceSquared,
				candidate.unitId,
				bestPriority,
				bestDistanceSquared,
				bestUnitId,
			):
				bestTarget = candidate
				bestPriority = priority
				bestDistanceSquared = distanceSquared
				bestUnitId = candidate.unitId

	return bestTarget


func FindBestTargetInAcquisitionRange(attacker: Unit, policy: TargetPolicy = null) -> Unit:
	if attacker == null or not attacker.HasCharacterStats() or attacker.IsDead():
		return null

	var acquisitionRange: int = attacker.GetStat(CharacterStats.Type.ACQUISITION_RANGE)
	if not _battleContext.IsManagedUnit(attacker) or acquisitionRange < 0:
		return null

	var candidateCount: int = _FindCandidateUnitIds(
		attacker,
		acquisitionRange,
		_candidateUnitIdBuffer,
	)

	var bestTarget: Unit = null
	var bestPriority: int = TargetPolicy.INVALID_PRIORITY
	var bestDistanceSquared: float = INF
	var bestUnitId: int = -1

	for index: int in candidateCount:
		var unitId: int = _candidateUnitIdBuffer[index]
		if unitId == attacker.unitId:
			continue

		var candidate: Unit = _battleContext.GetUnit(unitId)
		if not _battleContext.IsValidTarget(attacker, candidate):
			continue

		var priority: int = 0
		if policy != null:
			priority = policy.GetPriority(
				attacker,
				candidate,
				TargetPolicy.SelectionContext.ACQUISITION,
			)
			if priority == TargetPolicy.INVALID_PRIORITY:
				continue

		var distanceSquared: float = GetFootprintDistanceSquared(attacker.unitId, candidate.unitId)
		if distanceSquared > acquisitionRange * acquisitionRange:
			continue

		if _IsBetterTarget(
			priority,
			distanceSquared,
			unitId,
			bestPriority,
			bestDistanceSquared,
			bestUnitId,
		):
			bestTarget = candidate
			bestPriority = priority
			bestDistanceSquared = distanceSquared
			bestUnitId = unitId

	return bestTarget


func IsWithinRange(attacker: Unit, target: Unit, range: int) -> bool:
	if attacker == null or target == null or range < 0:
		return false

	if not _stageSnapshot.HasUnit(attacker.unitId) or not _stageSnapshot.HasUnit(target.unitId):
		return false

	var distanceSquared: float = GetFootprintDistanceSquared(attacker.unitId, target.unitId)
	return distanceSquared <= range * range


func GetFootprintDistanceSquared(firstUnitId: int, secondUnitId: int) -> float:
	var firstHalfSize: float = float(_stageSnapshot.GetHalfSize(firstUnitId))
	var secondHalfSize: float = float(_stageSnapshot.GetHalfSize(secondUnitId))

	return Math.AabbDistanceSquared(
		_stageSnapshot.GetPosition(firstUnitId),
		Vector2(firstHalfSize, firstHalfSize),
		_stageSnapshot.GetPosition(secondUnitId),
		Vector2(secondHalfSize, secondHalfSize),
	)


func _FindCandidateUnitIds(attacker: Unit, range: int, resultBuffer: PackedInt32Array) -> int:
	if attacker == null or range < 0 or not _stageSnapshot.HasUnit(attacker.unitId):
		return 0

	var attackerPosition: Vector2 = _stageSnapshot.GetPosition(attacker.unitId)
	var attackerHalfSize: int = _stageSnapshot.GetHalfSize(attacker.unitId)
	var searchExtent: int = range + attackerHalfSize

	return _stageSnapshot.FindUnitIdsInRect(
		attackerPosition,
		Vector2(searchExtent, searchExtent),
		resultBuffer,
	)


func _IsBetterTarget(
	priority: int,
	distanceSquared: float,
	unitId: int,
	bestPriority: int,
	bestDistanceSquared: float,
	bestUnitId: int,
) -> bool:
	if priority > bestPriority:
		return true

	if priority < bestPriority:
		return false

	if distanceSquared < bestDistanceSquared:
		return true

	if distanceSquared > bestDistanceSquared:
		return false

	return bestUnitId < 0 or unitId < bestUnitId
