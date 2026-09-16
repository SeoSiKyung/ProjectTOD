class_name DefenseObjectStatus
extends RefCounted

var maxHp: int
var currentHp: int
var hpRegen: int

var maxMp: int
var currentMp: int
var mpRegen: int


func _init(pMaxHp: int, pMaxMp: int, pHpRegen: int, pMpRegen: int) -> void:
	maxHp = pMaxHp
	currentHp = maxHp
	hpRegen = pHpRegen

	maxMp = pMaxMp
	currentMp = maxMp
	mpRegen = pMpRegen


func TakeDamage(damage: int) -> void:
	if damage <= 0 or IsHpDepleted():
		return

	currentHp = maxi(currentHp - damage, 0)


func IsHpDepleted() -> bool:
	return currentHp <= 0
