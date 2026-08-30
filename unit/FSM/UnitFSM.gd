class_name UnitFSM
extends Node

enum State {
	IDLE,
	MOVE,
	FOLLOW,
	CHASE,
	ATTACK_MOVE,
	ATTACK,
	STUN,
	DIE,
}

signal state_changed(previousState: State, currentState: State)

var currentState: State = State.IDLE
var attackReturnState: State = State.IDLE

var _followTarget: Unit = null
var _chaseTarget: Unit = null
var _attackTarget: Unit = null
var _stunTimeLeft: float = 0.0

var _unit: Unit = null
var _stateBeforeStun: State = State.IDLE


func BindUnit(pUnit: Unit) -> void:
	_unit = pUnit


func _physics_process(delta: float) -> void:
	match currentState:
		State.MOVE:
			_UpdateMove()
		State.FOLLOW:
			_UpdateFollow()
		State.CHASE:
			_UpdateChase()
		State.ATTACK_MOVE:
			_UpdateAttackMove()
		State.ATTACK:
			_UpdateAttack()
		State.STUN:
			_UpdateStun(delta)


func CanReceiveCommands() -> bool:
	return currentState != State.STUN and currentState != State.DIE


func RequestIdle() -> bool:
	if not CanReceiveCommands():
		return false

	_ClearTargets()
	_ChangeState(State.IDLE)
	return true


func RequestMove() -> bool:
	if not CanReceiveCommands():
		return false

	_ClearTargets()
	_ChangeState(State.MOVE)
	return true


func RequestFollow(target: Unit) -> bool:
	if not CanReceiveCommands():
		return false

	if not _IsValidTarget(target):
		return false

	_followTarget = target
	_chaseTarget = null
	_attackTarget = null
	attackReturnState = State.IDLE
	_ChangeState(State.FOLLOW)
	return true


func RequestChase(target: Unit) -> bool:
	if not CanReceiveCommands():
		return false

	if not _IsValidTarget(target):
		return false

	_followTarget = null
	_chaseTarget = target
	_attackTarget = null
	attackReturnState = State.IDLE
	_ChangeState(State.CHASE)
	return true


func RequestAttackMove() -> bool:
	if not CanReceiveCommands():
		return false

	_ClearTargets()
	_ChangeState(State.ATTACK_MOVE)
	return true


func RequestAttack(target: Unit, returnState: State = State.IDLE) -> bool:
	if not CanReceiveCommands():
		return false

	if not _IsValidTarget(target):
		return false

	if (
		returnState != State.IDLE and returnState != State.CHASE
		and returnState != State.ATTACK_MOVE
	):
		returnState = State.IDLE

	_followTarget = null
	_attackTarget = target
	attackReturnState = returnState

	if returnState == State.CHASE:
		_chaseTarget = target
	else:
		_chaseTarget = null

	_ChangeState(State.ATTACK)
	return true


func ReturnFromAttackOutOfRange() -> void:
	if currentState != State.ATTACK:
		return

	if attackReturnState == State.CHASE and _IsValidTarget(_chaseTarget):
		_attackTarget = null
		_ChangeState(State.CHASE)
		return

	if (
		attackReturnState == State.ATTACK_MOVE and _unit != null
		and _unit.movement != null and _unit.movement.IsMoving()
	):
		_attackTarget = null
		_ChangeState(State.ATTACK_MOVE)
		return

	_EnterIdleInternal()


func FinishAttack() -> void:
	if currentState != State.ATTACK:
		return

	if attackReturnState == State.CHASE and _IsValidTarget(_chaseTarget):
		_attackTarget = null
		_ChangeState(State.CHASE)
		return

	if (
		attackReturnState == State.ATTACK_MOVE and _unit != null
		and _unit.movement != null and _unit.movement.IsMoving()
	):
		_attackTarget = null
		_ChangeState(State.ATTACK_MOVE)
		return

	_EnterIdleInternal()


func ApplyStun(duration: float) -> void:
	if currentState == State.DIE:
		return

	if duration <= 0.0:
		return

	if currentState == State.STUN:
		_stunTimeLeft = maxf(_stunTimeLeft, duration)
		return

	_stateBeforeStun = currentState
	_stunTimeLeft = duration

	if _unit != null and _unit.movement != null:
		_unit.movement.Pause()

	_ChangeState(State.STUN)


func Die() -> void:
	if currentState == State.DIE:
		return

	_stunTimeLeft = 0.0
	_stateBeforeStun = State.IDLE
	_ClearTargets()

	if _unit != null and _unit.movement != null:
		_unit.movement.Stop()

	_ChangeState(State.DIE)


func _UpdateMove() -> void:
	if _unit == null or _unit.movement == null:
		_EnterIdleInternal()
		return

	if _unit.movement.IsIdle():
		_EnterIdleInternal()


func _UpdateFollow() -> void:
	if not _IsValidTarget(_followTarget):
		_EnterIdleInternal()


func _UpdateChase() -> void:
	if not _IsValidTarget(_chaseTarget):
		_EnterIdleInternal()


func _UpdateAttackMove() -> void:
	if _unit == null or _unit.movement == null:
		_EnterIdleInternal()
		return

	if _unit.movement.IsIdle():
		_EnterIdleInternal()


func _UpdateAttack() -> void:
	if not _IsValidTarget(_attackTarget):
		_EnterIdleInternal()


func _UpdateStun(delta: float) -> void:
	_stunTimeLeft = maxf(_stunTimeLeft - delta, 0.0)

	if _stunTimeLeft > 0.0:
		return

	_ResumeAfterStun()


func _ResumeAfterStun() -> void:
	var resumeState: State = _stateBeforeStun
	_stateBeforeStun = State.IDLE

	if _unit != null and _unit.movement != null:
		_unit.movement.Resume()

	match resumeState:
		State.MOVE:
			if _HasActiveMovement():
				_ChangeState(State.MOVE)
				return

		State.FOLLOW:
			if _IsValidTarget(_followTarget):
				_ChangeState(State.FOLLOW)
				return

		State.CHASE:
			if _IsValidTarget(_chaseTarget):
				_ChangeState(State.CHASE)
				return

		State.ATTACK_MOVE:
			if _HasActiveMovement():
				_ChangeState(State.ATTACK_MOVE)
				return

		State.ATTACK:
			if _IsValidTarget(_attackTarget):
				_ChangeState(State.ATTACK)
				return

	_EnterIdleInternal()


func _HasActiveMovement() -> bool:
	return (_unit != null and _unit.movement != null and _unit.movement.IsMoving())


func _EnterIdleInternal() -> void:
	_ClearTargets()
	_ChangeState(State.IDLE)


func _ClearTargets() -> void:
	_followTarget = null
	_chaseTarget = null
	_attackTarget = null
	attackReturnState = State.IDLE


func _ChangeState(nextState: State) -> void:
	if currentState == nextState:
		return

	var previousState: State = currentState
	currentState = nextState
	state_changed.emit(previousState, currentState)


func _IsValidTarget(target: Unit) -> bool:
	if target == null:
		return false

	if not is_instance_valid(target):
		return false

	if not target.is_inside_tree():
		return false

	if target == _unit:
		return false

	if target.fsm != null and target.fsm.currentState == State.DIE:
		return false

	return true
