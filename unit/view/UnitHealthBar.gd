class_name UnitHealthBar
extends Node2D

@export var barSize: Vector2 = Vector2(80.0, 12.0)
@export var heightMargin: float = 8.0
@export_range(0.1, 10.0, 0.1) var damageDisplayTime: float = 2.0

@export var backgroundColor: Color = Color(0.16, 0.10, 0.07, 1.0)
@export var fillColor: Color = Color(0.65, 0.22, 0.16, 1.0)
@export var borderColor: Color = Color(0.78, 0.64, 0.39, 1.0)

var _unit: Unit
var _fsm: UnitFSM
var _healthRatio: float = 0.0
var _isSelected: bool = false
var _damageTimeLeft: float = 0.0


func _ready() -> void:
	set_process(false)

	_unit = get_parent() as Unit
	if _unit == null:
		push_error("UnitHealthBar: 부모 노드는 Unit이어야 합니다.")
		hide()
		return

	_fsm = _unit.get_node_or_null("UnitFSM") as UnitFSM
	if _fsm == null:
		push_error("UnitHealthBar: UnitFSM이 없습니다.")
		hide()
		return

	_unit.HealthChanged.connect(_OnHealthChanged)
	_unit.Damaged.connect(_OnDamaged)
	_unit.ReuseReset.connect(_ResetDisplay)
	_fsm.state_changed.connect(_OnStateChanged)

	_ResetDisplay()


func SetSelected(selected: bool) -> void:
	_isSelected = selected
	_UpdateVisibility()


func _process(delta: float) -> void:
	_damageTimeLeft = maxf(_damageTimeLeft - delta, 0.0)
	if _damageTimeLeft > 0.0:
		return

	set_process(false)
	_UpdateVisibility()


func _draw() -> void:
	var barRect: Rect2 = Rect2(Vector2(-barSize.x * 0.5, -barSize.y), barSize)

	draw_rect(barRect.grow(1.0), borderColor)
	draw_rect(barRect, backgroundColor)

	if _healthRatio <= 0.0:
		return

	var fillRect: Rect2 = Rect2(barRect.position, Vector2(barSize.x * _healthRatio, barSize.y))

	draw_rect(fillRect, fillColor)


func _OnHealthChanged(currentHp: int, maxHp: int) -> void:
	_healthRatio = 0.0

	if maxHp > 0:
		_healthRatio = clampf(float(currentHp) / float(maxHp), 0.0, 1.0)

	position = Vector2(0.0, -float(_unit.GetHalfSize()) - heightMargin)

	queue_redraw()
	_UpdateVisibility()


func _OnDamaged(_damage: int) -> void:
	if _unit.currentHp <= 0:
		return

	_damageTimeLeft = damageDisplayTime
	set_process(true)
	_UpdateVisibility()


func _OnStateChanged(_previousState: UnitFSM.State, currentState: UnitFSM.State) -> void:
	if currentState == UnitFSM.State.DIE:
		_damageTimeLeft = 0.0
		_isSelected = false
		set_process(false)

	_UpdateVisibility()


func _ResetDisplay() -> void:
	_isSelected = false
	_damageTimeLeft = 0.0
	set_process(false)

	_OnHealthChanged(_unit.currentHp, _unit.maxHp)


func _UpdateVisibility() -> void:
	if not is_instance_valid(_unit) or not is_instance_valid(_fsm):
		hide()
		return

	visible = (
		_unit.maxHp > 0 and _unit.currentHp > 0 and _fsm.currentState != UnitFSM.State.DIE
		and (_isSelected or _damageTimeLeft > 0.0)
	)
