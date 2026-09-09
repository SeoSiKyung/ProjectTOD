class_name DefenseCommandPostStatus
extends DefenseObjectStatus


func _init(pMaxHp: int) -> void:
	super(pMaxHp)


func IsDestroyed() -> bool:
	return IsHpDepleted()
