class_name Tower
extends Unit

var _recruitedPopulation: int = 0
var _survivingPopulation: int = 0


func InitializePopulation(recruitedPopulation: int) -> bool:
	if not HasCharacterStats() or recruitedPopulation <= 0:
		return false

	_recruitedPopulation = recruitedPopulation
	_survivingPopulation = recruitedPopulation
	_RefreshVitalCapacity(true)
	return true


func GetRecruitedPopulation() -> int:
	return _recruitedPopulation


func GetSurvivingPopulation() -> int:
	return _survivingPopulation


func GetDeadPopulation() -> int:
	return _recruitedPopulation - _survivingPopulation


func TakeDamage(damage: int) -> void:
	super.TakeDamage(damage)
	_UpdateSurvivingPopulation()


func CalculateDamageAgainstDefense(defense: int, magicDefense: int) -> int:
	if not HasCharacterStats() or _survivingPopulation <= 0:
		return 0

	return Math.CalculateDamage(
		GetStat(CharacterStats.Type.ATK) * _survivingPopulation,
		defense,
		GetStat(CharacterStats.Type.MAGIC_ATK) * _survivingPopulation,
		magicDefense,
	)


func ResetForReuse() -> void:
	_recruitedPopulation = 0
	_survivingPopulation = 0
	super.ResetForReuse()


func _CalculateMaxHp() -> int:
	var hpPerPerson: int = super._CalculateMaxHp()
	if _recruitedPopulation <= 0:
		return hpPerPerson

	return hpPerPerson * _recruitedPopulation


func _CalculateHpRecoveryOnCapacityIncrease(previousMaxHp: int, newMaxHp: int) -> int:
	if _recruitedPopulation <= 0 or _survivingPopulation <= 0:
		return super._CalculateHpRecoveryOnCapacityIncrease(previousMaxHp, newMaxHp)

	var previousHpPerPerson: int = Math.DivideInt(previousMaxHp, _recruitedPopulation)
	var newHpPerPerson: int = Math.DivideInt(newMaxHp, _recruitedPopulation)
	var hpIncreasePerPerson: int = maxi(newHpPerPerson - previousHpPerPerson, 0)
	return hpIncreasePerPerson * _survivingPopulation


func _OnVitalCapacityRefreshed(resetVitals: bool) -> void:
	if _recruitedPopulation <= 0:
		return

	if resetVitals:
		_survivingPopulation = _recruitedPopulation
		return

	_UpdateSurvivingPopulation()


func _UpdateSurvivingPopulation() -> void:
	if _recruitedPopulation <= 0:
		_survivingPopulation = 0
		return

	var hpPerPerson: int = GetStat(CharacterStats.Type.MAX_HP)
	if hpPerPerson <= 0 or currentHp <= 0:
		_survivingPopulation = 0
		return

	var calculatedPopulation: int = mini(
		_recruitedPopulation,
		Math.CeilDivide(currentHp, hpPerPerson),
	)
	_survivingPopulation = mini(_survivingPopulation, calculatedPopulation)
