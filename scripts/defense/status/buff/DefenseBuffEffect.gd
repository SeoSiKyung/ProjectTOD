class_name DefenseBuffEffect
extends RefCounted

enum StatType {
	ATK,
	DEF,
	HP,
}

enum SourceType {
	MERCENARY,
	FACILITY,
	RESEARCH,
}

var statType: StatType

var flatValue: int
var ratioValue: int

var sourceType: SourceType
var sourceKey: int


func _init(
	pStatType: StatType,
	pFlatValue: int,
	pRatioValue: int,
	pSourceType: SourceType,
	pSourceKey: int,
) -> void:
	statType = pStatType

	flatValue = pFlatValue
	ratioValue = pRatioValue

	sourceType = pSourceType
	sourceKey = pSourceKey
