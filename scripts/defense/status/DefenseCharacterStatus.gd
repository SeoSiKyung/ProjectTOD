class_name DefenseCharacterStatus
extends DefenseObjectStatus

var characterKey: int
var characterName: String
var characterType: CharacterData.CharacterType
var path: String

var atk: int
var magicAtk: int
var def: int
var magicDef: int

var moveSpeed: int
var attackSpeed: int

var atkRange: int
var acquisitionRange: int

var nextAttackTimeMs: int = 0 # jhw, 추후 작업 필요


func _init(characterData: CharacterData) -> void:
	super(characterData.maxHp, characterData.maxMp, characterData.hpRegen, characterData.mpRegen)

	characterKey = characterData.characterKey
	characterName = characterData.characterName
	characterType = characterData.characterType
	path = characterData.path

	atk = characterData.atk
	magicAtk = characterData.magicAtk
	def = characterData.def
	magicDef = characterData.magicDef

	moveSpeed = characterData.moveSpeed
	attackSpeed = characterData.attackSpeed

	atkRange = characterData.atkRange
	acquisitionRange = characterData.acquisitionRange


func IsDead() -> bool:
	return IsHpDepleted()


func CalculateDamage(targetStatus: DefenseCharacterStatus) -> int:
	if targetStatus == null:
		return 0

	return Math.CalculateDamage(atk, targetStatus.def, magicAtk, targetStatus.magicDef)


func IsAttackReady(elapsedTimeMs: int) -> bool:
	return elapsedTimeMs >= nextAttackTimeMs


func StartAttackCooldown(elapsedTimeMs: int, attackIntervalMs: int) -> void:
	nextAttackTimeMs = elapsedTimeMs + maxi(attackIntervalMs, 0)
