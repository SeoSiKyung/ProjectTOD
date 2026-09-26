class_name CharacterData
extends RefCounted

enum CharacterType {
	UNIT,
	MONSTER,
	COUNT,
}

var characterKey: int
var characterName: String
var characterType: CharacterType
var iconPath: String
var prefabPath: String

var maxHp: int
var maxMp: int
var hpRegen: int
var mpRegen: int

var atk: int
var magicAtk: int
var def: int
var magicDef: int

var moveSpeed: int
var attackIntervalFrames: int

var atkRange: int
var acquisitionRange: int


func _init(
	pCharacterKey: int,
	pCharacterName: String,
	pCharacterType: CharacterType,
	pIconPath: String,
	pPrefabPath: String,
	pMaxHp: int,
	pMaxMp: int,
	pHpRegen: int,
	pMpRegen: int,
	pAtk: int,
	pMagicAtk: int,
	pDef: int,
	pMagicDef: int,
	pMoveSpeed: int,
	pAttackIntervalFrames: int,
	pAtkRange: int,
	pAcquisitionRange: int,
) -> void:
	characterKey = pCharacterKey
	characterName = pCharacterName
	characterType = pCharacterType
	iconPath = pIconPath
	prefabPath = pPrefabPath

	maxHp = pMaxHp
	maxMp = pMaxMp
	hpRegen = pHpRegen
	mpRegen = pMpRegen

	atk = pAtk
	magicAtk = pMagicAtk
	def = pDef
	magicDef = pMagicDef

	moveSpeed = pMoveSpeed
	attackIntervalFrames = pAttackIntervalFrames

	atkRange = pAtkRange
	acquisitionRange = pAcquisitionRange
