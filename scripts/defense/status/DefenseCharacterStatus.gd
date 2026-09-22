class_name DefenseCharacterStatus
extends DefenseObjectStatus

var characterKey: int
var characterType: CharacterData.CharacterType

var atk: int
var magicAtk: int
var def: int
var magicDef: int

var moveSpeed: int
var attackIntervalFrames: int

var atkRange: int
var acquisitionRange: int


func _init(characterData: CharacterData) -> void:
	super(characterData.maxHp, characterData.maxMp, characterData.hpRegen, characterData.mpRegen)

	characterKey = characterData.characterKey
	characterType = characterData.characterType

	atk = characterData.atk
	magicAtk = characterData.magicAtk
	def = characterData.def
	magicDef = characterData.magicDef

	moveSpeed = characterData.moveSpeed
	attackIntervalFrames = characterData.attackIntervalFrames

	atkRange = characterData.atkRange
	acquisitionRange = characterData.acquisitionRange


func IsDead() -> bool:
	return IsHpDepleted()


func CalculateDamage(targetStatus: DefenseCharacterStatus) -> int:
	if targetStatus == null:
		return 0

	return Math.CalculateDamage(atk, targetStatus.def, magicAtk, targetStatus.magicDef)
