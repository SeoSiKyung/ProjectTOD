class_name DefenseCharacterStatus
extends DefenseObjectStatus

var characterKey: int
var characterType: CharacterData.CharacterType

var atk: int
var magicAtk: int
var def: int
var magicDef: int

var nextAttackTimeMs: int = 0 # jhw, 추후 작업 필요


func _init(characterData: CharacterData) -> void:
	super(characterData.maxHp)

	characterKey = characterData.characterKey
	characterType = characterData.characterType

	atk = characterData.atk
	magicAtk = characterData.magicAtk
	def = characterData.def
	magicDef = characterData.magicDef


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
