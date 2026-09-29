class_name MercenaryBuffData
extends RefCounted

var mercenaryKey: int
var statType: CharacterStats.Type
var flatValue: int
var ratioValue: int


func _init(pMercenaryKey: int, pStatType: CharacterStats.Type, pFlatValue: int, pRatioValue: int) -> void:
	mercenaryKey = pMercenaryKey
	statType = pStatType
	flatValue = pFlatValue
	ratioValue = pRatioValue
