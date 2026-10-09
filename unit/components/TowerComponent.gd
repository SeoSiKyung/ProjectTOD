class_name TowerComponent
extends RefCounted

var _recruitedPopulation: int = 0
var _survivingPopulation: int = 0


func InitializePopulation(recruitedPopulation: int) -> bool:
	if recruitedPopulation <= 0:
		return false

	_recruitedPopulation = recruitedPopulation
	_survivingPopulation = recruitedPopulation
	return true


func GetRecruitedPopulation() -> int:
	return _recruitedPopulation


func GetSurvivingPopulation() -> int:
	return _survivingPopulation


func GetDeadPopulation() -> int:
	return _recruitedPopulation - _survivingPopulation


func CalculateMaxHp(hpPerPerson: int) -> int:
	if _recruitedPopulation <= 0:
		return hpPerPerson

	return hpPerPerson * _recruitedPopulation


func CalculateDamageAgainstDefense(atk: int, magicAtk: int, defense: int, magicDefense: int) -> int:
	if _survivingPopulation <= 0:
		return 0

	return Math.CalculateDamage(
		atk * _survivingPopulation,
		defense,
		magicAtk * _survivingPopulation,
		magicDefense,
	)


func CalculateHpRecoveryOnCapacityIncrease(previousMaxHp: int, newMaxHp: int) -> int:
	if _recruitedPopulation <= 0 or _survivingPopulation <= 0:
		return maxi(newMaxHp - previousMaxHp, 0)

	var previousHpPerPerson: int = Math.DivideInt(previousMaxHp, _recruitedPopulation)
	var newHpPerPerson: int = Math.DivideInt(newMaxHp, _recruitedPopulation)

	var hpIncreasePerPerson: int = maxi(newHpPerPerson - previousHpPerPerson, 0)

	return hpIncreasePerPerson * _survivingPopulation


func OnVitalCapacityRefreshed(resetVitals: bool, currentHp: int, hpPerPerson: int) -> void:
	if _recruitedPopulation <= 0:
		return

	if resetVitals:
		_survivingPopulation = _recruitedPopulation
		return

	UpdateSurvivingPopulation(currentHp, hpPerPerson)


func UpdateSurvivingPopulation(currentHp: int, hpPerPerson: int) -> void:
	if _recruitedPopulation <= 0:
		_survivingPopulation = 0
		return

	if hpPerPerson <= 0 or currentHp <= 0:
		_survivingPopulation = 0
		return

	var calculatedPopulation: int = mini(
		_recruitedPopulation,
		Math.CeilDivide(currentHp, hpPerPerson),
	)

	_survivingPopulation = mini(_survivingPopulation, calculatedPopulation)


func ResetForReuse() -> void:
	_recruitedPopulation = 0
	_survivingPopulation = 0
