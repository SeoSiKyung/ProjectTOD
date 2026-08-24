class_name UnitFSM
extends Node


enum State {
	IDLE,
	MOVE,
	CHASE,
	ATTACK,
	STUN,
	DIE,
}


signal state_changed(previous_state: State, current_state: State)


var current_state: State = State.IDLE
var chase_target: Unit = null
var attack_target: Unit = null
var attack_return_state: State = State.IDLE
var stun_time_left: float = 0.0

var unit: Unit = null
var _state_before_stun: State = State.IDLE


func bind_unit(p_unit: Unit) -> void:
	unit = p_unit


func _physics_process(delta: float) -> void:
	match current_state:
		State.MOVE:
			_update_move()
		State.CHASE:
			_update_chase()
		State.ATTACK:
			_update_attack()
		State.STUN:
			_update_stun(delta)


func can_receive_commands() -> bool:
	return current_state != State.STUN and current_state != State.DIE


func can_act() -> bool:
	return current_state != State.STUN and current_state != State.DIE


func request_idle() -> bool:
	if not can_receive_commands():
		return false

	_clear_targets()
	_change_state(State.IDLE)
	return true


func request_move() -> bool:
	if not can_receive_commands():
		return false

	_clear_targets()
	_change_state(State.MOVE)
	return true


func request_chase(target: Unit) -> bool:
	if not can_receive_commands():
		return false

	if not _is_valid_target(target):
		return false

	chase_target = target
	attack_target = null
	attack_return_state = State.IDLE
	_change_state(State.CHASE)
	return true


func request_attack(
	target: Unit,
	return_state: State = State.IDLE
) -> bool:
	if not can_receive_commands():
		return false

	if not _is_valid_target(target):
		return false

	if return_state != State.IDLE and return_state != State.CHASE:
		return_state = State.IDLE

	attack_target = target
	attack_return_state = return_state

	if return_state == State.CHASE:
		chase_target = target
	else:
		chase_target = null

	_change_state(State.ATTACK)
	return true


func return_from_attack_out_of_range() -> void:
	if current_state != State.ATTACK:
		return

	if (
		attack_return_state == State.CHASE
		and _is_valid_target(chase_target)
	):
		attack_target = null
		_change_state(State.CHASE)
		return

	_enter_idle_internal()


func finish_attack() -> void:
	if current_state != State.ATTACK:
		return

	_enter_idle_internal()


func apply_stun(duration: float) -> void:
	if current_state == State.DIE:
		return

	if duration <= 0.0:
		return

	if current_state == State.STUN:
		stun_time_left = maxf(stun_time_left, duration)
		return

	_state_before_stun = current_state
	stun_time_left = duration

	if unit != null and unit.movement != null:
		unit.movement.pause()

	_change_state(State.STUN)


func die() -> void:
	if current_state == State.DIE:
		return

	stun_time_left = 0.0
	_state_before_stun = State.IDLE
	_clear_targets()

	if unit != null and unit.movement != null:
		unit.movement.stop()

	_change_state(State.DIE)


func _update_move() -> void:
	if unit == null or unit.movement == null:
		_enter_idle_internal()
		return

	if unit.movement.is_idle():
		_enter_idle_internal()


func _update_chase() -> void:
	if not _is_valid_target(chase_target):
		_enter_idle_internal()


func _update_attack() -> void:
	if not _is_valid_target(attack_target):
		_enter_idle_internal()


func _update_stun(delta: float) -> void:
	stun_time_left = maxf(stun_time_left - delta, 0.0)

	if stun_time_left > 0.0:
		return

	_resume_after_stun()


func _resume_after_stun() -> void:
	var resume_state: State = _state_before_stun
	_state_before_stun = State.IDLE

	if unit != null and unit.movement != null:
		unit.movement.resume()

	match resume_state:
		State.MOVE:
			if (
				unit != null
				and unit.movement != null
				and unit.movement.is_moving()
			):
				_change_state(State.MOVE)
				return
		State.CHASE:
			if _is_valid_target(chase_target):
				_change_state(State.CHASE)
				return
		State.ATTACK:
			if _is_valid_target(attack_target):
				_change_state(State.ATTACK)
				return

	_enter_idle_internal()


func _enter_idle_internal() -> void:
	_clear_targets()
	_change_state(State.IDLE)


func _clear_targets() -> void:
	chase_target = null
	attack_target = null
	attack_return_state = State.IDLE


func _change_state(next_state: State) -> void:
	if current_state == next_state:
		return

	var previous_state: State = current_state
	current_state = next_state
	state_changed.emit(previous_state, current_state)


func _is_valid_target(target: Unit) -> bool:
	if target == null:
		return false

	if not is_instance_valid(target):
		return false

	if not target.is_inside_tree():
		return false

	if target == unit:
		return false

	if target.fsm != null and target.fsm.current_state == State.DIE:
		return false

	return true
