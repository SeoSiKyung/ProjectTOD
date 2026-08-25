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

signal state_changed(previous_state: State, current_state: State)

var currentState: State = State.IDLE
var follow_target: Unit = null
var chase_target: Unit = null
var attack_target: Unit = null
var attack_return_state: State = State.IDLE
var stun_time_left: float = 0.0

var unit: Unit = null
var _state_before_stun: State = State.IDLE


func BindUnit(p_unit: Unit) -> void:
	unit = p_unit


func _physics_process(delta: float) -> void:
	match currentState:
		State.MOVE:
			_updateMove()
		State.FOLLOW:
			_updateFollow()
		State.CHASE:
			_updateChase()
		State.ATTACK_MOVE:
			_updateAttackMove()
		State.ATTACK:
			_updateAttack()
		State.STUN:
			_updateStun(delta)


func CanReceiveCommands() -> bool:
	return currentState != State.STUN and currentState != State.DIE


func RequestIdle() -> bool:
	if not CanReceiveCommands():
		return false

	_clearTargets()
	_changeState(State.IDLE)
	return true


func RequestMove() -> bool:
	if not CanReceiveCommands():
		return false

	_clearTargets()
	_changeState(State.MOVE)
	return true


func RequestFollow(target: Unit) -> bool:
	if not CanReceiveCommands():
		return false

	if not _isValidTarget(target):
		return false

	follow_target = target
	chase_target = null
	attack_target = null
	attack_return_state = State.IDLE
	_changeState(State.FOLLOW)
	return true


func RequestChase(target: Unit) -> bool:
	if not CanReceiveCommands():
		return false

	if not _isValidTarget(target):
		return false

	follow_target = null
	chase_target = target
	attack_target = null
	attack_return_state = State.IDLE
	_changeState(State.CHASE)
	return true


func RequestAttackMove() -> bool:
	if not CanReceiveCommands():
		return false

	_clearTargets()
	_changeState(State.ATTACK_MOVE)
	return true


func RequestAttack(target: Unit, return_state: State = State.IDLE) -> bool:
	if not CanReceiveCommands():
		return false

	if not _isValidTarget(target):
		return false

	if (
		return_state != State.IDLE and return_state != State.CHASE
		and return_state != State.ATTACK_MOVE
	):
		return_state = State.IDLE

	follow_target = null
	attack_target = target
	attack_return_state = return_state

	if return_state == State.CHASE:
		chase_target = target
	else:
		chase_target = null

	_changeState(State.ATTACK)
	return true


func ReturnFromAttackOutOfRange() -> void:
	if currentState != State.ATTACK:
		return

	if (attack_return_state == State.CHASE and _isValidTarget(chase_target)):
		attack_target = null
		_changeState(State.CHASE)
		return

	if (
		attack_return_state == State.ATTACK_MOVE and unit != null
		and unit.movement != null and unit.movement.is_moving()
	):
		attack_target = null
		_changeState(State.ATTACK_MOVE)
		return

	_enterIdleInternal()


func FinishAttack() -> void:
	if currentState != State.ATTACK:
		return

	if (attack_return_state == State.CHASE and _isValidTarget(chase_target)):
		attack_target = null
		_changeState(State.CHASE)
		return

	if (
		attack_return_state == State.ATTACK_MOVE and unit != null
		and unit.movement != null and unit.movement.is_moving()
	):
		attack_target = null
		_changeState(State.ATTACK_MOVE)
		return

	_enterIdleInternal()


func ApplyStun(duration: float) -> void:
	if currentState == State.DIE:
		return

	if duration <= 0.0:
		return

	if currentState == State.STUN:
		stun_time_left = maxf(stun_time_left, duration)
		return

	_state_before_stun = currentState
	stun_time_left = duration

	if unit != null and unit.movement != null:
		unit.movement.pause()

	_changeState(State.STUN)


func Die() -> void:
	if currentState == State.DIE:
		return

	stun_time_left = 0.0
	_state_before_stun = State.IDLE
	_clearTargets()

	if unit != null and unit.movement != null:
		unit.movement.stop()

	_changeState(State.DIE)


func _updateMove() -> void:
	if unit == null or unit.movement == null:
		_enterIdleInternal()
		return

	if unit.movement.IsIdle():
		_enterIdleInternal()


func _updateFollow() -> void:
	if not _isValidTarget(follow_target):
		_enterIdleInternal()


func _updateChase() -> void:
	if not _isValidTarget(chase_target):
		_enterIdleInternal()


func _updateAttackMove() -> void:
	if unit == null or unit.movement == null:
		_enterIdleInternal()
		return

	if unit.movement.IsIdle():
		_enterIdleInternal()


func _updateAttack() -> void:
	if not _isValidTarget(attack_target):
		_enterIdleInternal()


func _updateStun(delta: float) -> void:
	stun_time_left = maxf(stun_time_left - delta, 0.0)

	if stun_time_left > 0.0:
		return

	_resumeAfterStun()


func _resumeAfterStun() -> void:
	var resume_state: State = _state_before_stun
	_state_before_stun = State.IDLE

	if unit != null and unit.movement != null:
		unit.movement.resume()

	match resume_state:
		State.MOVE:
			if _hasActiveMovement():
				_changeState(State.MOVE)
				return
		State.FOLLOW:
			if _isValidTarget(follow_target):
				_changeState(State.FOLLOW)
				return
		State.CHASE:
			if _isValidTarget(chase_target):
				_changeState(State.CHASE)
				return
		State.ATTACK_MOVE:
			if _hasActiveMovement():
				_changeState(State.ATTACK_MOVE)
				return
		State.ATTACK:
			if _isValidTarget(attack_target):
				_changeState(State.ATTACK)
				return

	_enterIdleInternal()


func _hasActiveMovement() -> bool:
	return (unit != null and unit.movement != null and unit.movement.is_moving())


func _enterIdleInternal() -> void:
	_clearTargets()
	_changeState(State.IDLE)


func _clearTargets() -> void:
	follow_target = null
	chase_target = null
	attack_target = null
	attack_return_state = State.IDLE


func _changeState(next_state: State) -> void:
	if currentState == next_state:
		return

	var previous_state: State = currentState
	currentState = next_state
	state_changed.emit(previous_state, currentState)


func _isValidTarget(target: Unit) -> bool:
	if target == null:
		return false

	if not is_instance_valid(target):
		return false

	if not target.is_inside_tree():
		return false

	if target == unit:
		return false

	if target.fsm != null and target.fsm.currentState == State.DIE:
		return false

	return true
