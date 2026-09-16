class_name DefenseCPStatus
extends DefenseObjectStatus


func _init(pMaxHp: int) -> void:
	super(pMaxHp, 0, 0, 0)


func IsDestroyed() -> bool:
	return IsHpDepleted()
