class_name DefenseTargetingManager
extends RefCounted

const TARGET_ACQUISITION_INTERVAL_MS: int = 100
const CHASE_COMMAND_GROUP_SIZE: int = 20
const CHASE_REPATH_DISTANCE: float = 32.0

var _battleContext: DefenseBattleFacade
var _unitRuntime: UnitRuntime
var _stageSnapshot: StageSnapshot

var _targetSelector: DefenseTargetSelector

var _targetByAttacker: Dictionary[Unit, Unit] = { }
var _pendingEnemyRetargets: Array[Enemy] = []
var _pendingEnemyIds: Dictionary[Enemy, int] = { }
var _retargetCycleActive: bool = false
var _retargetCycleStartTick: int = 0
var _retargetCycleQueued: int = 0
var _retargetCycleSucceeded: int = 0
var _retargetCycleFailed: int = 0
var _retargetCycleCancelled: int = 0
var _retargetCycleMaxPending: int = 0
var _retargetCycleRequestUsec: int = 0
var _retargetCycleMaxRequestUsec: int = 0
var lastRetargetSummary: Dictionary = { }

var _targetAcquisitionIntervalFrames: int = 1
var _enemyTargetAcquisitionCursor: int = 0
var _unitTargetAcquisitionCursor: int = 0
var _machineTargetAcquisitionCursor: int = 0
var _trapTargetAcquisitionCursor: int = 0

var timingEnabled: bool = false
var timingExistingTargetsUsec: int = 0
var timingAcquisitionUsec: int = 0
var timingDefaultSelectionUsec: int = 0
var timingMissingEnemyCount: int = 0
var timingRetargetUsec: int = 0


func _init(battleContext: DefenseBattleFacade, unitRuntime: UnitRuntime) -> void:
	_battleContext = battleContext
	_unitRuntime = unitRuntime
	_stageSnapshot = unitRuntime.GetStageSnapshot()

	_targetSelector = DefenseTargetSelector.new(_battleContext, _stageSnapshot)

	var physicsTicksPerSecond: int = Engine.physics_ticks_per_second
	_targetAcquisitionIntervalFrames = maxi(
		1,
		Math.CeilDivide(physicsTicksPerSecond * TARGET_ACQUISITION_INTERVAL_MS, 1000),
	)


func Reset() -> void:
	_targetByAttacker.clear()
	_pendingEnemyRetargets.clear()
	_pendingEnemyIds.clear()
	_retargetCycleActive = false
	lastRetargetSummary.clear()
	_enemyTargetAcquisitionCursor = 0
	_unitTargetAcquisitionCursor = 0
	_machineTargetAcquisitionCursor = 0
	_trapTargetAcquisitionCursor = 0


func Update() -> void:
	lastRetargetSummary.clear()
	var phaseStart: int = Time.get_ticks_usec() if timingEnabled else 0
	_UpdateExistingTargets()

	if timingEnabled:
		timingExistingTargetsUsec += Time.get_ticks_usec() - phaseStart
		phaseStart = Time.get_ticks_usec()

	_UpdateTargetAcquisition()

	if timingEnabled:
		timingAcquisitionUsec += Time.get_ticks_usec() - phaseStart
		phaseStart = Time.get_ticks_usec()

	_ProcessPendingEnemyRetarget()

	if timingEnabled:
		timingRetargetUsec += Time.get_ticks_usec() - phaseStart

	_FinishRetargetCycle()


func BeginTimingSample(enabled: bool) -> void:
	timingEnabled = enabled
	if not enabled:
		return

	timingExistingTargetsUsec = 0
	timingAcquisitionUsec = 0
	timingDefaultSelectionUsec = 0
	timingMissingEnemyCount = 0
	timingRetargetUsec = 0


func SetTarget(attacker: Unit, target: Unit) -> bool:
	if attacker == null or target == null:
		return false

	_targetByAttacker[attacker] = target
	_CancelPendingEnemyRetarget(attacker)
	return true


func GetTarget(attacker: Unit) -> Unit:
	if attacker == null:
		return null

	return _targetByAttacker.get(attacker, null)


func ClearTarget(attacker: Unit) -> void:
	if attacker == null:
		return

	_targetByAttacker.erase(attacker)
	_CancelPendingEnemyRetarget(attacker)


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

	var selectionStart: int = Time.get_ticks_usec() if timingEnabled else 0
	var target: Unit = _targetSelector.FindDefaultEnemyTarget(enemies[0] as Enemy)
	if timingEnabled:
		timingDefaultSelectionUsec += Time.get_ticks_usec() - selectionStart
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


func _UpdateExistingTargets() -> void:
	for characterType: CharacterType.Type in CharacterType.COUNT:
		var characterCount: int = _battleContext.GetCharacterCount(characterType)
		for index: int in characterCount:
			var character: Unit = _battleContext.GetCharacterByIndex(characterType, index)
			if not _battleContext.IsManagedUnit(character):
				continue

			if character.fsm == null or not character.fsm.CanReceiveCommands():
				continue

			_UpdateCharacterTargeting(character, characterType)


func _UpdateCharacterTargeting(character: Unit, characterType: CharacterType.Type) -> void:
	var target: Unit = GetTarget(character)

	if target == null or not _battleContext.IsValidTarget(character, target):
		if target != null:
			ClearTarget(character)
		_HandleMissingTarget(character, characterType)
		return

	if not character.HasCharacterStats() or character.IsDead():
		return

	var acquisitionRange: int = character.GetStat(CharacterStats.Type.ACQUISITION_RANGE)
	var attackRange: int = character.GetStat(CharacterStats.Type.ATK_RANGE)

	if (
		_IsStaticCombatType(characterType)
		and not _targetSelector.IsWithinRange(character, target, acquisitionRange)
	):
		ClearTarget(character)
		_ReturnUnitToIdle(character)
		return

	if characterType == CharacterType.TRAP:
		var trap: Trap = character as Trap
		if trap == null:
			push_error("DefenseTargetingManager: TRAP 타입의 인스턴스가 Trap이 아닙니다.")
			return

		if not _stageSnapshot.HasUnit(trap.unitId) or not _stageSnapshot.HasUnit(target.unitId):
			return

		var distanceSquared: float = _targetSelector.GetFootprintDistanceSquared(
			trap.unitId,
			target.unitId,
		)
		if trap.CanTrigger(target, distanceSquared):
			_EnterAttack(trap, target, characterType)
		elif trap.fsm.currentState == UnitFSM.State.ATTACK:
			trap.fsm.ReturnFromAttackOutOfRange()

		return

	if _targetSelector.IsWithinRange(character, target, attackRange):
		_EnterAttack(character, target, characterType)
		return

	if character.fsm.currentState != UnitFSM.State.ATTACK:
		return

	match characterType:
		CharacterType.ENEMY:
			_IssueChaseTarget(character, target)
		CharacterType.TOWER, \
				CharacterType.MACHINE, \
				CharacterType.TRAP:
			character.fsm.ReturnFromAttackOutOfRange()


func _HandleMissingTarget(character: Unit, characterType: CharacterType.Type) -> void:
	match characterType:
		CharacterType.ENEMY:
			if timingEnabled:
				timingMissingEnemyCount += 1
			_QueueEnemyRetarget(character as Enemy)

		CharacterType.TOWER, \
				CharacterType.MACHINE, \
				CharacterType.TRAP:
			_ReturnUnitToIdle(character)


func HasPendingEnemyRetargets() -> bool:
	return not _pendingEnemyRetargets.is_empty()


func _QueueEnemyRetarget(enemy: Enemy) -> void:
	if not is_instance_valid(enemy) or _pendingEnemyIds.has(enemy):
		return

	if not _battleContext.IsManagedUnit(enemy) or enemy.IsDead() or enemy.fsm == null:
		return

	if not enemy.fsm.CanReceiveCommands():
		return

	if (
		enemy.fsm.currentState != UnitFSM.State.IDLE
		and enemy.fsm.currentState != UnitFSM.State.CHASE
		and enemy.fsm.currentState != UnitFSM.State.ATTACK
	):
		return

	if enemy.fsm.currentState != UnitFSM.State.IDLE or _unitRuntime.IsUnitMoving(enemy.unitId):
		_unitRuntime.StopUnit(enemy.unitId)
		if not enemy.fsm.RequestIdle():
			return

	var selectionStart: int = Time.get_ticks_usec() if timingEnabled else 0
	var target: Unit = _targetSelector.FindDefaultEnemyTarget(enemy)
	if timingEnabled:
		timingDefaultSelectionUsec += Time.get_ticks_usec() - selectionStart

	if target == null:
		return

	if not _retargetCycleActive:
		_retargetCycleActive = true
		_retargetCycleStartTick = Engine.get_physics_frames()
		_retargetCycleQueued = 0
		_retargetCycleSucceeded = 0
		_retargetCycleFailed = 0
		_retargetCycleCancelled = 0
		_retargetCycleMaxPending = 0
		_retargetCycleRequestUsec = 0
		_retargetCycleMaxRequestUsec = 0

	_pendingEnemyRetargets.append(enemy)
	_pendingEnemyIds[enemy] = enemy.unitId
	_retargetCycleQueued += 1
	_retargetCycleMaxPending = maxi(_retargetCycleMaxPending, _pendingEnemyRetargets.size())


func _CancelPendingEnemyRetarget(unit: Unit) -> void:
	if not _pendingEnemyIds.has(unit):
		return

	_pendingEnemyIds.erase(unit)
	_pendingEnemyRetargets.erase(unit)
	_retargetCycleCancelled += 1


func _ProcessPendingEnemyRetarget() -> void:
	while not _pendingEnemyRetargets.is_empty():
		var enemy: Enemy = _pendingEnemyRetargets.pop_front()
		var expectedId: int = _pendingEnemyIds.get(enemy, -1)
		_pendingEnemyIds.erase(enemy)
		if not is_instance_valid(enemy):
			_retargetCycleCancelled += 1
			continue

		if (
			enemy.unitId != expectedId or not _battleContext.IsManagedUnit(enemy)
			or enemy.IsDead() or enemy.fsm == null
		):
			_retargetCycleCancelled += 1
			continue

		if (
			enemy.fsm.currentState != UnitFSM.State.IDLE or not enemy.fsm.CanReceiveCommands()
			or _unitRuntime.IsUnitMoving(enemy.unitId) or GetTarget(enemy) != null
		):
			_retargetCycleCancelled += 1
			continue

		var requestStart: int = Time.get_ticks_usec() if timingEnabled else 0
		var succeeded: bool = _IssueDefaultEnemyChase(enemy)
		if timingEnabled:
			var elapsed: int = Time.get_ticks_usec() - requestStart
			_retargetCycleRequestUsec += elapsed
			_retargetCycleMaxRequestUsec = maxi(_retargetCycleMaxRequestUsec, elapsed)

		if succeeded:
			_retargetCycleSucceeded += 1
		else:
			_retargetCycleFailed += 1
		break


func _FinishRetargetCycle() -> void:
	if not _retargetCycleActive or HasPendingEnemyRetargets():
		return

	_retargetCycleActive = false
	if not timingEnabled:
		return

	lastRetargetSummary = {
		"queued": _retargetCycleQueued,
		"succeeded": _retargetCycleSucceeded,
		"failed": _retargetCycleFailed,
		"cancelled": _retargetCycleCancelled,
		"max_pending": _retargetCycleMaxPending,
		"ticks": Engine.get_physics_frames() - _retargetCycleStartTick + 1,
		"request_usec": _retargetCycleRequestUsec,
		"max_request_usec": _retargetCycleMaxRequestUsec,
	}


func _GetEnemyTargetPolicy(enemy: Enemy) -> TargetPolicy:
	if enemy == null:
		return null

	return enemy.GetTargetPolicy()


func _IssueDefaultEnemyChase(enemy: Enemy) -> bool:
	var selectionStart: int = Time.get_ticks_usec() if timingEnabled else 0
	var target: Unit = _targetSelector.FindDefaultEnemyTarget(enemy)
	if timingEnabled:
		timingDefaultSelectionUsec += Time.get_ticks_usec() - selectionStart
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


func _EnterAttack(attacker: Unit, target: Unit, characterType: CharacterType.Type) -> void:
	if attacker.fsm.currentState == UnitFSM.State.ATTACK:
		return

	var returnState: UnitFSM.State = UnitFSM.State.IDLE

	if characterType == CharacterType.ENEMY:
		if not _unitRuntime.StopUnit(attacker.unitId):
			return

		returnState = UnitFSM.State.CHASE

	attacker.fsm.RequestAttack(target, returnState)


func _UpdateTargetAcquisition() -> void:
	_unitTargetAcquisitionCursor = _UpdateTargetAcquisitionByType(
		CharacterType.TOWER,
		_unitTargetAcquisitionCursor,
	)
	_machineTargetAcquisitionCursor = _UpdateTargetAcquisitionByType(
		CharacterType.MACHINE,
		_machineTargetAcquisitionCursor,
	)
	_trapTargetAcquisitionCursor = _UpdateTargetAcquisitionByType(
		CharacterType.TRAP,
		_trapTargetAcquisitionCursor,
	)
	_enemyTargetAcquisitionCursor = _UpdateTargetAcquisitionByType(
		CharacterType.ENEMY,
		_enemyTargetAcquisitionCursor,
	)


func _UpdateTargetAcquisitionByType(characterType: CharacterType.Type, cursor: int) -> int:
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

		if _pendingEnemyIds.has(character):
			continue

		var currentTarget: Unit = GetTarget(character)
		if _ShouldAcquireTarget(character, characterType, currentTarget):
			var targetPolicy: TargetPolicy = null
			if characterType == CharacterType.ENEMY:
				targetPolicy = _GetEnemyTargetPolicy(character as Enemy)

			var newTarget: Unit = _targetSelector.FindBestTargetInAcquisitionRange(
				character,
				targetPolicy,
			)
			if newTarget != null and newTarget != currentTarget:
				_SetAcquiredTarget(character, newTarget, characterType)

		if characterType == CharacterType.ENEMY:
			_RefreshEnemyChase(character as Enemy)

	return cursor


func _ShouldAcquireTarget(
	character: Unit,
	characterType: CharacterType.Type,
	currentTarget: Unit,
) -> bool:
	match characterType:
		CharacterType.ENEMY:
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
		CharacterType.TOWER, \
				CharacterType.MACHINE:
			if currentTarget == null:
				return true

			if not character.HasCharacterStats():
				return false

			var attackRange: int = character.GetStat(CharacterStats.Type.ATK_RANGE)
			return not _targetSelector.IsWithinRange(character, currentTarget, attackRange)
		CharacterType.TRAP:
			return currentTarget == null

	return false


func _SetAcquiredTarget(character: Unit, target: Unit, characterType: CharacterType.Type) -> void:
	match characterType:
		CharacterType.ENEMY:
			if _IssueChaseTarget(character, target):
				return

			if not _IssueDefaultEnemyChase(character as Enemy):
				push_warning(
					"DefenseTargetingManager: Enemy 기본 타겟 복귀에 실패했습니다. unitId: "
					+ str(character.unitId)
				)

		CharacterType.TOWER, \
				CharacterType.MACHINE, \
				CharacterType.TRAP:
			SetTarget(character, target)


func _IsStaticCombatType(characterType: CharacterType.Type) -> bool:
	return (
		characterType == CharacterType.TOWER or characterType == CharacterType.MACHINE
		or characterType == CharacterType.TRAP
	)
