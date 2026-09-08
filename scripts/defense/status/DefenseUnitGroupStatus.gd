class_name DefenseUnitGroupStatus
extends DefenseCharacterStatus

var recruitedPopulation: int
var survivingPopulation: int

var hpPerPerson: int


func _init(pRecruitedPopulation: int, characterData: CharacterData) -> void:
	super(characterData)

	recruitedPopulation = pRecruitedPopulation
	survivingPopulation = pRecruitedPopulation

	hpPerPerson = characterData.maxHp
	maxHp = hpPerPerson * recruitedPopulation
	currentHp = maxHp


func GetDeadPopulation() -> int:
	return recruitedPopulation - survivingPopulation


func TakeDamage(damage: int) -> void:
	if damage <= 0 or IsDead():
		return

	super.TakeDamage(damage)
	_UpdateSurvivingPopulation()


func CalculateDamage(targetStatus: DefenseCharacterStatus) -> int:
	var damagePerPerson: int = super.CalculateDamage(targetStatus)
	return damagePerPerson * survivingPopulation


func _UpdateSurvivingPopulation() -> void:
	if currentHp <= 0:
		survivingPopulation = 0
		return

	survivingPopulation = Math.CeilDivide(currentHp, hpPerPerson)
