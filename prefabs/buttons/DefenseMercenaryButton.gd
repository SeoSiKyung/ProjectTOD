class_name DefenseMercenaryButton
extends Button

@onready var _nameLabel: Label = $MarginContainer/VBoxContainer/NameLabel
@onready var _bonusLabel: Label = $MarginContainer/VBoxContainer/BonusLabel


func Initialize(mercenaryData: MercenaryData, buffDataList: Array[MercenaryBuffData]) -> void:
	_nameLabel.text = mercenaryData.name

	var bonusLines: PackedStringArray = []
	for buffData: MercenaryBuffData in buffDataList:
		var bonusLine: String = _FormatBuffData(buffData)
		if not bonusLine.is_empty():
			bonusLines.append(bonusLine)

	_bonusLabel.text = "효과 없음" if bonusLines.is_empty() else "\n".join(bonusLines)


func _FormatBuffData(buffData: MercenaryBuffData) -> String:
	if buffData == null or (buffData.flatValue == 0 and buffData.ratioValue == 0):
		return ""

	var statName: String = _GetStatName(buffData.statType)
	var values: PackedStringArray = []

	if buffData.flatValue != 0:
		values.append("+%d" % buffData.flatValue)

	if buffData.ratioValue != 0:
		values.append("+%d%%" % Math.RatioToPercent(buffData.ratioValue))

	return "%s %s" % [statName, " / ".join(values)]


func _GetStatName(type: CharacterStats.Type) -> String:
	match type:
		CharacterStats.Type.ATK:
			return "공격"
		CharacterStats.Type.DEF:
			return "방어"
		CharacterStats.Type.MAX_HP:
			return "체력"
		_:
			return str(CharacterStats.Type.keys()[type])
