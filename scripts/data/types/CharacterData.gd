class_name CharacterData
extends RefCounted

enum CharacterType {
	UNIT,
	MONSTER,
}

var characterKey: int
var characterName: String
var characterType: CharacterType
var path: String

var maxHp: int
var maxMp: int
var hpRegen: int
var mpRegen: int

var atk: int
var magicAtk: int
var def: int
var magicDef: int

var moveSpeed: int
var attackSpeed: int

var atkRange: int
var acquisitionRange: int


func _init(
	pCharacterKey: int,
	pCharacterName: String,
	pCharacterType: CharacterType,
	pPath: String,
	pMaxHp: int,
	pMaxMp: int,
	pHpRegen: int,
	pMpRegen: int,
	pAtk: int,
	pMagicAtk: int,
	pDef: int,
	pMagicDef: int,
	pMoveSpeed: int,
	pAttackSpeed: int,
	pAtkRange: int,
	pAcquisitionRange: int,
):
	characterKey = pCharacterKey
	characterName = pCharacterName
	characterType = pCharacterType
	path = pPath

	maxHp = pMaxHp
	maxMp = pMaxMp
	hpRegen = pHpRegen
	mpRegen = pMpRegen

	atk = pAtk
	magicAtk = pMagicAtk
	def = pDef
	magicDef = pMagicDef

	moveSpeed = pMoveSpeed
	attackSpeed = pAttackSpeed

	atkRange = pAtkRange
	acquisitionRange = pAcquisitionRange
