class_name UnitHitFlash
extends Node

const FLASH_MATERIAL: ShaderMaterial = preload("res://unit/view/UnitHitFlash.tres")

@export var visual: CanvasItem
@export_range(0.01, 1.0, 0.01) var flashDuration: float = 0.12
@export_range(0.0, 1.0, 0.05) var flashStrength: float = 0.85

var _unit: Unit
var _fsm: UnitFSM
var _flashTween: Tween


func _ready() -> void:
	_unit = get_parent() as Unit
	if _unit == null or visual == null:
		return

	_fsm = _unit.get_node_or_null("UnitFSM") as UnitFSM
	if _fsm == null:
		push_error("UnitHitFlash: UnitFSM이 없습니다.")
		return

	visual.material = FLASH_MATERIAL

	_unit.Damaged.connect(_OnDamaged)
	_unit.ReuseReset.connect(_ResetFlash)
	_fsm.state_changed.connect(_OnStateChanged)

	_ResetFlash()


func _OnDamaged(_damage: int) -> void:
	if _unit.currentHp <= 0:
		return

	if _fsm.currentState == UnitFSM.State.DIE:
		return

	_ResetFlash()
	_SetFlashAmount(flashStrength)

	_flashTween = create_tween()
	_flashTween.tween_method(_SetFlashAmount, flashStrength, 0.0, flashDuration)


func _OnStateChanged(_previousState: UnitFSM.State, currentState: UnitFSM.State) -> void:
	if currentState == UnitFSM.State.DIE:
		_ResetFlash()


func _ResetFlash() -> void:
	if _flashTween != null:
		if _flashTween.is_valid():
			_flashTween.kill()

		_flashTween = null

	_SetFlashAmount(0.0)


func _SetFlashAmount(amount: float) -> void:
	if not is_instance_valid(visual):
		return

	visual.set_instance_shader_parameter(&"flash_amount", amount)
