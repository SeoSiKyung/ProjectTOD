class_name DefenseUnitGroupState
extends RefCounted

var recruitedPopulation: int
var survivingPopulation: int
var hpPerPerson: int = 0


func _init(pRecruitedPopulation: int) -> void:
	recruitedPopulation = pRecruitedPopulation
	survivingPopulation = pRecruitedPopulation


func BindUnit(unit: Unit) -> bool:
	if unit == null or recruitedPopulation <= 0:
		return false

	hpPerPerson = unit.GetStat(CharacterStats.Type.MAX_HP)
	if hpPerPerson <= 0:
		return false

	if not unit.SetHpCapacityMultiplier(recruitedPopulation, true):
		return false

	survivingPopulation = recruitedPopulation
	return true


func GetDeadPopulation() -> int:
	return recruitedPopulation - survivingPopulation


func IsDead() -> bool:
	return survivingPopulation <= 0


func UpdateAfterDamage(unit: Unit) -> void:
	if unit == null:
		survivingPopulation = 0
		return

	hpPerPerson = unit.GetStat(CharacterStats.Type.MAX_HP)
	if hpPerPerson <= 0:
		survivingPopulation = 0
		return

	if unit.currentHp <= 0:
		survivingPopulation = 0
		return

	survivingPopulation = mini(recruitedPopulation, Math.CeilDivide(unit.currentHp, hpPerPerson))
