class_name CommandPostStatus
extends UnitStatus

var def: int = 0
var magicDef: int = 0

var _baseMaxHp: int
var _baseDef: int
var _baseMagicDef: int
var _bonusStats: BonusStats = BonusStats.new()


func _init(pMaxHp: int, pDef: int, pMagicDef: int) -> void:
	super(pMaxHp, 0, 0, 0)
	_baseMaxHp = pMaxHp
	_baseDef = pDef
	_baseMagicDef = pMagicDef
	_RefreshStats(false)


func AddStatBonus(type: CharacterStats.Type, flatValue: int, ratioValue: int) -> bool:
	if not _IsSupportedStat(type):
		return false

	if not _bonusStats.AddBonus(type, flatValue, ratioValue):
		return false

	_RefreshStats(true)
	return true


func IsDestroyed() -> bool:
	return IsHpDepleted()


# 임시 방어용.. 추후 CP 스텟 개선 필요
func _IsSupportedStat(type: CharacterStats.Type) -> bool:
	return (
		type == CharacterStats.Type.MAX_HP or type == CharacterStats.Type.DEF
		or type == CharacterStats.Type.MAGIC_DEF
	)


func _RefreshStats(preserveCurrentHp: bool) -> void:
	var newMaxHp: int = maxi(
		_baseMaxHp + _bonusStats.GetBonus(CharacterStats.Type.MAX_HP, _baseMaxHp),
		0,
	)
	def = maxi(_baseDef + _bonusStats.GetBonus(CharacterStats.Type.DEF, _baseDef), 0)
	magicDef = maxi(
		_baseMagicDef + _bonusStats.GetBonus(CharacterStats.Type.MAGIC_DEF, _baseMagicDef),
		0,
	)

	if preserveCurrentHp:
		var hpRecovery: int = maxi(newMaxHp - maxHp, 0)
		maxHp = newMaxHp
		currentHp = clampi(currentHp + hpRecovery, 0, maxHp)
	else:
		maxHp = newMaxHp
		currentHp = newMaxHp
