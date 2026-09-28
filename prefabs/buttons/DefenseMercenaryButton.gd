class_name DefenseMercenaryButton
extends Button

@onready var _nameLabel: Label = $MarginContainer/VBoxContainer/NameLabel
@onready var _bonusLabel: Label = $MarginContainer/VBoxContainer/BonusLabel


func Initialize(mercenaryData: MercenaryData) -> void:
	_nameLabel.text = mercenaryData.name

	_bonusLabel.text = "공격 +%d\n방어 +%d\n체력 +%d" % [
		mercenaryData.atkBonus,
		mercenaryData.defBonus,
		mercenaryData.hpBonus,
	]
