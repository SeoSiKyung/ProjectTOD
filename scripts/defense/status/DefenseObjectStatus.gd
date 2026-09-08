class_name DefenseObjectStatus
extends RefCounted

var maxHp: int
var currentHp: int


func _init(pMaxHp: int) -> void:
	maxHp = pMaxHp
	currentHp = maxHp


func TakeDamage(damage: int) -> void:
	if damage <= 0 or IsHpDepleted():
		return

	currentHp = maxi(currentHp - damage, 0)


func IsHpDepleted() -> bool:
	return currentHp <= 0
