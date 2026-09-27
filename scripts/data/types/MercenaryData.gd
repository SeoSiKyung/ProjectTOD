class_name MercenaryData
extends RefCounted

var mercenaryKey: int
var characterKey: int
var name: String
var isHero: bool

var atkBonus: int
var defBonus: int
var hpBonus: int


func _init(
	pMercenaryKey: int,
	pCharacterKey: int,
	pName: String,
	pIsHero: bool,
	pAtkBonus: int,
	pDefBonus: int,
	pHpBonus: int,
) -> void:
	mercenaryKey = pMercenaryKey
	characterKey = pCharacterKey
	name = pName
	isHero = pIsHero

	atkBonus = pAtkBonus
	defBonus = pDefBonus
	hpBonus = pHpBonus
