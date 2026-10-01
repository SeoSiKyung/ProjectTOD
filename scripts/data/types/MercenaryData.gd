class_name MercenaryData
extends RefCounted

var mercenaryKey: int
var characterKey: int
var name: String
var isHero: bool

var iconPath: String
var parchmentIconPath: String


func _init(
	pMercenaryKey: int,
	pCharacterKey: int,
	pName: String,
	pIsHero: bool,
	pIconPath: String,
	pParchmentIconPath: String,
) -> void:
	mercenaryKey = pMercenaryKey
	characterKey = pCharacterKey
	name = pName
	isHero = pIsHero

	iconPath = pIconPath
	parchmentIconPath = pParchmentIconPath
