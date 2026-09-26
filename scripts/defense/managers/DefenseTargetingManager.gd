class_name DefenseTargetingManager
extends RefCounted

const TARGET_ACQUISITION_INTERVAL_MS: int = 100
const CHASE_COMMAND_GROUP_SIZE: int = 20

var _battleContext: DefenseBattleFacade
var _unitRuntime: UnitRuntime
var _stageSnapshot: StageSnapshot

var _candidateUnitIdBuffer: PackedInt32Array = []

var _targetByAttacker: Dictionary[Unit, Unit] = { }

var _targetAcquisitionIntervalFrames: int = 1
var _monsterTargetAcquisitionCursor: int = 0
var _unitTargetAcquisitionCursor: int = 0


func _init(battleContext: DefenseBattleFacade, unitRuntime: UnitRuntime) -> void:
	_battleContext = battleContext
	_unitRuntime = unitRuntime
	_stageSnapshot = unitRuntime.GetStageSnapshot()

	_candidateUnitIdBuffer.resize(_stageSnapshot.GetSlotCapacity())

	var physicsTicksPerSecond: int = Engine.physics_ticks_per_second
	_targetAcquisitionIntervalFrames = maxi(
		1,
		Math.CeilDivide(physicsTicksPerSecond * TARGET_ACQUISITION_INTERVAL_MS, 1000),
	)


func Reset() -> void:
	_targetByAttacker.clear()
	_monsterTargetAcquisitionCursor = 0
	_unitTargetAcquisitionCursor = 0


func Update() -> void:
	_UpdateExistingTargets()
	_UpdateTargetAcquisition()


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
	if attacker != null:
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
	Reset()


func IssueChaseGroupTarget(attackers: Array[Unit], target: Unit) -> bool:
	if attackers.is_empty() or not _battleContext.IsManagedUnit(target):
		return false

	var validAttackers: Array[Unit] = []
	for attacker: Unit in attackers:
		if not _battleContext.IsValidTarget(attacker, target):
			continue

		validAttackers.append(attacker)

	if validAttackers.is_empty():
		return false

	var commandId: int = _unitRuntime.IssueMoveCommand(validAttackers, target.global_position)
	if commandId < 0:
		for attacker: Unit in validAttackers:
			_unitRuntime.StopUnit(attacker.unitId)

		return false

	for attacker: Unit in validAttackers:
		if attacker.fsm == null:
			_unitRuntime.StopUnit(attacker.unitId)
			continue

		if not attacker.fsm.RequestChase(target):
			_unitRuntime.StopUnit(attacker.unitId)
			continue

		if not SetTarget(attacker, target):
			_unitRuntime.StopUnit(attacker.unitId)
			attacker.fsm.RequestIdle()

	return true


func IssueChaseGroupsToCP(monsters: Array[Unit]) -> void:
	var cp: DefenseCP = _battleContext.GetCP()
	if cp == null or monsters.is_empty():
		return

	var startIndex: int = 0
	while startIndex < monsters.size():
		var endIndex: int = mini(startIndex + CHASE_COMMAND_GROUP_SIZE, monsters.size())
		var group: Array[Unit] = []

		for index: int in range(startIndex, endIndex):
			group.append(monsters[index])

		IssueChaseGroupTarget(group, cp)
		startIndex = endIndex


func IsWithinRange(attacker: Unit, target: Unit, range: int) -> bool:
	if attacker == null or target == null or range < 0:
		return false

	if not _stageSnapshot.HasUnit(attacker.unitId) or not _stageSnapshot.HasUnit(target.unitId):
		return false

	var distanceSquared: float = _GetFootprintDistanceSquared(attacker.unitId, target.unitId)
	return distanceSquared <= range * range


func _UpdateExistingTargets() -> void:
	for characterType: CharacterData.CharacterType in CharacterData.CharacterType.COUNT:
		var characterCount: int = _battleContext.GetCharacterCount(characterType)
		for index: int in characterCount:
			var character: Unit = _battleContext.GetCharacterByIndex(characterType, index)
			if not _battleContext.IsManagedUnit(character):
				continue

			if character.fsm == null or not character.fsm.CanReceiveCommands():
				continue

			_UpdateCharacterTargeting(character, characterType)


func _UpdateCharacterTargeting(character: Unit, characterType: CharacterData.CharacterType) -> void:
	var target: Unit = GetTarget(character)

	if target == null or not _battleContext.IsValidTarget(character, target):
		ClearTarget(character)
		_HandleMissingTarget(character, characterType)
		return

	var status: DefenseCharacterStatus = _battleContext.GetCharacterStatus(character)
	if status == null:
		return

	if (
		characterType == CharacterData.CharacterType.UNIT
		and not IsWithinRange(character, target, status.acquisitionRange)
	):
		ClearTarget(character)
		_ReturnUnitToIdle(character)
		return

	if IsWithinRange(character, target, status.atkRange):
		_EnterAttack(character, target, characterType)
		return

	if character.fsm.currentState != UnitFSM.State.ATTACK:
		return

	match characterType:
		CharacterData.CharacterType.MONSTER:
			_IssueChaseTarget(character, target)

		CharacterData.CharacterType.UNIT:
			character.fsm.ReturnFromAttackOutOfRange()


func _HandleMissingTarget(character: Unit, characterType: CharacterData.CharacterType) -> void:
	match characterType:
		CharacterData.CharacterType.MONSTER:
			_IssueChaseTarget(character, _battleContext.GetCP())

		CharacterData.CharacterType.UNIT:
			_ReturnUnitToIdle(character)


func _ReturnUnitToIdle(unit: Unit) -> void:
	if unit.fsm.currentState == UnitFSM.State.ATTACK:
		unit.fsm.RequestIdle()


func _EnterAttack(attacker: Unit, target: Unit, characterType: CharacterData.CharacterType) -> void:
	if attacker.fsm.currentState == UnitFSM.State.ATTACK:
		return

	var returnState: UnitFSM.State = UnitFSM.State.IDLE

	if characterType == CharacterData.CharacterType.MONSTER:
		if not _unitRuntime.StopUnit(attacker.unitId):
			return

		returnState = UnitFSM.State.CHASE

	attacker.fsm.RequestAttack(target, returnState)


func _UpdateTargetAcquisition() -> void:
	_unitTargetAcquisitionCursor = _UpdateTargetAcquisitionByType(
		CharacterData.CharacterType.UNIT,
		_unitTargetAcquisitionCursor,
	)
	_monsterTargetAcquisitionCursor = _UpdateTargetAcquisitionByType(
		CharacterData.CharacterType.MONSTER,
		_monsterTargetAcquisitionCursor,
	)


func _UpdateTargetAcquisitionByType(characterType: CharacterData.CharacterType, cursor: int) -> int:
	var characterCount: int = _battleContext.GetCharacterCount(characterType)
	if characterCount == 0:
		return 0

	var acquisitionCount: int = mini(
		Math.CeilDivide(characterCount, _targetAcquisitionIntervalFrames),
		characterCount,
	)

	for i: int in range(acquisitionCount):
		if cursor >= characterCount:
			cursor = 0

		var character: Unit = _battleContext.GetCharacterByIndex(characterType, cursor)
		cursor += 1
		if not _battleContext.IsManagedUnit(character):
			continue

		if character.fsm == null or not character.fsm.CanReceiveCommands():
			continue

		var currentTarget: Unit = GetTarget(character)
		if not _ShouldAcquireTarget(characterType, currentTarget):
			continue

		var newTarget: Unit = _FindNearestEnemyInAcquisitionRange(character)
		if newTarget != null:
			_SetAcquiredTarget(character, newTarget, characterType)

	return cursor


func _FindNearestEnemyInAcquisitionRange(attacker: Unit) -> Unit:
	var attackerStatus: DefenseCharacterStatus = _battleContext.GetCharacterStatus(attacker)
	if attackerStatus == null or attackerStatus.IsDead():
		return null

	var acquisitionRange: int = attackerStatus.acquisitionRange
	if not _battleContext.IsManagedUnit(attacker) or acquisitionRange < 0:
		return null

	var candidateCount: int = _FindCandidateUnitIds(
		attacker,
		acquisitionRange,
		_candidateUnitIdBuffer,
	)

	var nearestTarget: Unit = null
	var nearestDistanceSquared: float = INF
	var nearestUnitId: int = -1

	for index: int in candidateCount:
		var unitId: int = _candidateUnitIdBuffer[index]
		if unitId == attacker.unitId:
			continue

		var candidate: Unit = _battleContext.GetUnit(unitId)
		if not _battleContext.IsValidTarget(attacker, candidate):
			continue

		if candidate == _battleContext.GetCP():
			continue

		var distanceSquared: float = _GetFootprintDistanceSquared(attacker.unitId, candidate.unitId)
		if distanceSquared > acquisitionRange * acquisitionRange:
			continue

		if (
			nearestTarget == null or distanceSquared < nearestDistanceSquared
			or (is_equal_approx(distanceSquared, nearestDistanceSquared) and unitId < nearestUnitId)
		):
			nearestTarget = candidate
			nearestDistanceSquared = distanceSquared
			nearestUnitId = unitId

	return nearestTarget


func _ShouldAcquireTarget(characterType: CharacterData.CharacterType, currentTarget: Unit) -> bool:
	match characterType:
		CharacterData.CharacterType.MONSTER:
			return currentTarget == _battleContext.GetCP()

		CharacterData.CharacterType.UNIT:
			return currentTarget == null

	return false


func _SetAcquiredTarget(
	character: Unit,
	target: Unit,
	characterType: CharacterData.CharacterType,
) -> void:
	match characterType:
		CharacterData.CharacterType.MONSTER:
			if _IssueChaseTarget(character, target):
				return

			if not _IssueChaseTarget(character, _battleContext.GetCP()):
				push_warning(
					"DefenseTargetingManager: Monster 타겟 전환 및 CP 복귀에 실패했습니다. unitId: "
					+ str(character.unitId)
				)

		CharacterData.CharacterType.UNIT:
			SetTarget(character, target)


func _IssueChaseTarget(attacker: Unit, target: Unit) -> bool:
	if not _battleContext.IsValidTarget(attacker, target):
		return false

	var units: Array[Unit] = [attacker]
	var commandId: int = _unitRuntime.IssueMoveCommand(units, target.global_position)
	if commandId < 0:
		return false

	if attacker.fsm == null:
		_unitRuntime.StopUnit(attacker.unitId)
		return false

	if not attacker.fsm.RequestChase(target):
		_unitRuntime.StopUnit(attacker.unitId)
		return false

	if not SetTarget(attacker, target):
		_unitRuntime.StopUnit(attacker.unitId)
		attacker.fsm.RequestIdle()
		return false

	return true


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


func _GetFootprintDistanceSquared(firstUnitId: int, secondUnitId: int) -> float:
	var firstPosition: Vector2 = _stageSnapshot.GetPosition(firstUnitId)
	var secondPosition: Vector2 = _stageSnapshot.GetPosition(secondUnitId)
	var combinedHalfSize: float = float(
		_stageSnapshot.GetHalfSize(firstUnitId) + _stageSnapshot.GetHalfSize(secondUnitId)
	)

	var dx: float = maxf(absf(firstPosition.x - secondPosition.x) - combinedHalfSize, 0.0)
	var dy: float = maxf(absf(firstPosition.y - secondPosition.y) - combinedHalfSize, 0.0)
	return dx * dx + dy * dy
