class_name MercenaryData
extends RefCounted

var mercenaryKey: int
var characterKey: int
var name: String
var isHero: bool


func _init(pMercenaryKey: int, pCharacterKey: int, pName: String, pIsHero: bool) -> void:
	mercenaryKey = pMercenaryKey
	characterKey = pCharacterKey
	name = pName
	isHero = pIsHero
