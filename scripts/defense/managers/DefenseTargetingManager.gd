class_name DefenseTargetingManager
extends RefCounted

const TARGET_ACQUISITION_INTERVAL_MS: int = 100
const CHASE_COMMAND_GROUP_SIZE: int = 20
const CHASE_REPATH_DISTANCE: float = 32.0

var _battleContext: DefenseBattleFacade
var _unitRuntime: UnitRuntime
var _stageSnapshot: StageSnapshot

var _candidateUnitIdBuffer: PackedInt32Array = []

var _targetByAttacker: Dictionary[Unit, Unit] = { }

var _targetAcquisitionIntervalFrames: int = 1
var _enemyTargetAcquisitionCursor: int = 0
var _unitTargetAcquisitionCursor: int = 0
var _machineTargetAcquisitionCursor: int = 0
var _trapTargetAcquisitionCursor: int = 0


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
	_enemyTargetAcquisitionCursor = 0
	_unitTargetAcquisitionCursor = 0
	_machineTargetAcquisitionCursor = 0
	_trapTargetAcquisitionCursor = 0


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
	if attacker == null:
		return

	_targetByAttacker.erase(attacker)


func RemoveUnit(unit: Unit) -> void:
	if unit == null:
		return

	ClearTarget(unit)

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

	var destination: Vector2 = target.global_position
	if not destination.is_finite():
		return false

	var commandId: int = _unitRuntime.IssueMoveCommand(validAttackers, destination)
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
			continue

		attacker.fsm.MarkChasePathIssued(destination)

	return true


# 에너미 스폰 시 그룹 단위로 최초 추격 명령 발행
func IssueInitialEnemyChases(enemies: Array[Unit]) -> void:
	if enemies.is_empty():
		return

	var target: Unit = _GetDefaultEnemyTarget(enemies[0] as Enemy)
	if target == null:
		return

	var startIndex: int = 0
	while startIndex < enemies.size():
		var endIndex = mini(startIndex + CHASE_COMMAND_GROUP_SIZE, enemies.size())

		var group: Array[Unit] = []
		for index: int in range(startIndex, endIndex):
			group.append(enemies[index])

		IssueChaseGroupTarget(group, target)
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

	if not character.HasCharacterStats() or character.IsDead():
		return

	var acquisitionRange: int = character.GetStat(CharacterStats.Type.ACQUISITION_RANGE)
	var attackRange: int = character.GetStat(CharacterStats.Type.ATK_RANGE)

	if (
		_IsFriendlyStaticCombatType(characterType)
		and not IsWithinRange(character, target, acquisitionRange)
	):
		ClearTarget(character)
		_ReturnUnitToIdle(character)
		return

	if characterType == CharacterData.CharacterType.TRAP:
		var trap: Trap = character as Trap
		if trap == null:
			push_error("DefenseTargetingManager: TRAP 타입의 인스턴스가 Trap이 아닙니다.")
			return

		if not _stageSnapshot.HasUnit(trap.unitId) or not _stageSnapshot.HasUnit(target.unitId):
			return

		var distanceSquared: float = _GetFootprintDistanceSquared(trap.unitId, target.unitId)
		if trap.CanTrigger(target, distanceSquared):
			_EnterAttack(trap, target, characterType)
		elif trap.fsm.currentState == UnitFSM.State.ATTACK:
			trap.fsm.ReturnFromAttackOutOfRange()

		return

	if IsWithinRange(character, target, attackRange):
		_EnterAttack(character, target, characterType)
		return

	if character.fsm.currentState != UnitFSM.State.ATTACK:
		return

	match characterType:
		CharacterData.CharacterType.ENEMY:
			_IssueChaseTarget(character, target)
		CharacterData.CharacterType.TOWER, \
				CharacterData.CharacterType.MACHINE, \
				CharacterData.CharacterType.TRAP:
			character.fsm.ReturnFromAttackOutOfRange()


func _HandleMissingTarget(character: Unit, characterType: CharacterData.CharacterType) -> void:
	match characterType:
		CharacterData.CharacterType.ENEMY:
			_IssueDefaultEnemyChase(character as Enemy)

		CharacterData.CharacterType.TOWER, \
				CharacterData.CharacterType.MACHINE, \
				CharacterData.CharacterType.TRAP:
			_ReturnUnitToIdle(character)


func _GetDefaultEnemyTarget(enemy: Enemy) -> Unit:
	if enemy == null or not _battleContext.IsManagedUnit(enemy):
		return null

	var policy: TargetPolicy = _GetEnemyTargetPolicy(enemy)
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
			bestDistanceSquared = _GetFootprintDistanceSquared(enemy.unitId, cp.unitId)
			bestUnitId = cp.unitId

	var candidateTypes: Array[CharacterData.CharacterType] = [
		CharacterData.CharacterType.TOWER,
		CharacterData.CharacterType.MACHINE,
		CharacterData.CharacterType.TRAP,
	]
	for characterType: CharacterData.CharacterType in candidateTypes:
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

			var distanceSquared: float = _GetFootprintDistanceSquared(
				enemy.unitId,
				candidate.unitId,
			)

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


func _GetEnemyTargetPolicy(enemy: Enemy) -> TargetPolicy:
	if enemy == null:
		return null

	return enemy.GetTargetPolicy()


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


func _IssueDefaultEnemyChase(enemy: Enemy) -> bool:
	var target: Unit = _GetDefaultEnemyTarget(enemy)
	if target == null:
		return false

	return _IssueChaseTarget(enemy, target)


func _IssueChaseTarget(attacker: Unit, target: Unit) -> bool:
	if not _battleContext.IsValidTarget(attacker, target):
		return false

	var destination: Vector2 = target.global_position
	if not destination.is_finite():
		return false

	var units: Array[Unit] = [attacker]
	var commandId: int = _unitRuntime.IssueMoveCommand(units, destination)
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

	attacker.fsm.MarkChasePathIssued(destination)
	return true


func _RefreshEnemyChase(enemy: Enemy) -> void:
	if enemy == null or enemy.fsm == null:
		return

	if enemy.fsm.currentState != UnitFSM.State.CHASE:
		return

	var target: Unit = GetTarget(enemy)
	if not _battleContext.IsValidTarget(enemy, target):
		return

	var destination: Vector2 = target.global_position

	if not enemy.fsm.NeedsChaseRepath(destination, CHASE_REPATH_DISTANCE):
		return

	_IssueChaseTarget(enemy, target)


func _ReturnUnitToIdle(unit: Unit) -> void:
	if unit.fsm.currentState == UnitFSM.State.ATTACK:
		unit.fsm.RequestIdle()


func _EnterAttack(attacker: Unit, target: Unit, characterType: CharacterData.CharacterType) -> void:
	if attacker.fsm.currentState == UnitFSM.State.ATTACK:
		return

	var returnState: UnitFSM.State = UnitFSM.State.IDLE

	if characterType == CharacterData.CharacterType.ENEMY:
		if not _unitRuntime.StopUnit(attacker.unitId):
			return

		returnState = UnitFSM.State.CHASE

	attacker.fsm.RequestAttack(target, returnState)


func _UpdateTargetAcquisition() -> void:
	_unitTargetAcquisitionCursor = _UpdateTargetAcquisitionByType(
		CharacterData.CharacterType.TOWER,
		_unitTargetAcquisitionCursor,
	)
	_machineTargetAcquisitionCursor = _UpdateTargetAcquisitionByType(
		CharacterData.CharacterType.MACHINE,
		_machineTargetAcquisitionCursor,
	)
	_trapTargetAcquisitionCursor = _UpdateTargetAcquisitionByType(
		CharacterData.CharacterType.TRAP,
		_trapTargetAcquisitionCursor,
	)
	_enemyTargetAcquisitionCursor = _UpdateTargetAcquisitionByType(
		CharacterData.CharacterType.ENEMY,
		_enemyTargetAcquisitionCursor,
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
		if _ShouldAcquireTarget(character, characterType, currentTarget):
			var targetPolicy: TargetPolicy = null
			if characterType == CharacterData.CharacterType.ENEMY:
				targetPolicy = _GetEnemyTargetPolicy(character as Enemy)

			var newTarget: Unit = _FindBestEnemyInAcquisitionRange(character, targetPolicy)
			if newTarget != null and newTarget != currentTarget:
				_SetAcquiredTarget(character, newTarget, characterType)

		if characterType == CharacterData.CharacterType.ENEMY:
			_RefreshEnemyChase(character as Enemy)

	return cursor


func _FindBestEnemyInAcquisitionRange(attacker: Unit, policy: TargetPolicy = null) -> Unit:
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

		var distanceSquared: float = _GetFootprintDistanceSquared(attacker.unitId, candidate.unitId)
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


func _ShouldAcquireTarget(
	character: Unit,
	characterType: CharacterData.CharacterType,
	currentTarget: Unit,
) -> bool:
	match characterType:
		CharacterData.CharacterType.ENEMY:
			if character.fsm != null and character.fsm.currentState == UnitFSM.State.ATTACK:
				return false

			var policy: TargetPolicy = _GetEnemyTargetPolicy(character as Enemy)
			if policy == null or currentTarget == null:
				return false

			var priority: int = policy.GetPriority(
				character,
				currentTarget,
				TargetPolicy.SelectionContext.DEFAULT,
			)
			return priority != TargetPolicy.INVALID_PRIORITY
		CharacterData.CharacterType.TOWER, \
				CharacterData.CharacterType.MACHINE, \
				CharacterData.CharacterType.TRAP:
			return currentTarget == null

	return false


func _SetAcquiredTarget(
	character: Unit,
	target: Unit,
	characterType: CharacterData.CharacterType,
) -> void:
	match characterType:
		CharacterData.CharacterType.ENEMY:
			if _IssueChaseTarget(character, target):
				return

			if not _IssueDefaultEnemyChase(character as Enemy):
				push_warning(
					"DefenseTargetingManager: Enemy 기본 타겟 복귀에 실패했습니다. unitId: "
					+ str(character.unitId)
				)

		CharacterData.CharacterType.TOWER, \
				CharacterData.CharacterType.MACHINE, \
				CharacterData.CharacterType.TRAP:
			SetTarget(character, target)


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


func _IsFriendlyStaticCombatType(characterType: CharacterData.CharacterType) -> bool:
	return (
		characterType == CharacterData.CharacterType.TOWER
		or characterType == CharacterData.CharacterType.MACHINE
		or characterType == CharacterData.CharacterType.TRAP
	)
