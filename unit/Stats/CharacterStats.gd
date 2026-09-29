class_name CharacterStats
extends RefCounted

enum Type {
	MAX_HP,
	MAX_MP,
	HP_REGEN,
	MP_REGEN,
	ATK,
	MAGIC_ATK,
	DEF,
	MAGIC_DEF,
	MOVE_SPEED,
	ATTACK_INTERVAL_FRAMES,
	ATK_RANGE,
	ACQUISITION_RANGE,
	COUNT,
}

var _values: PackedInt32Array = PackedInt32Array()


func _init(
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
	_values.resize(Type.COUNT)

	_values[Type.MAX_HP] = pMaxHp
	_values[Type.MAX_MP] = pMaxMp
	_values[Type.HP_REGEN] = pHpRegen
	_values[Type.MP_REGEN] = pMpRegen
	_values[Type.ATK] = pAtk
	_values[Type.MAGIC_ATK] = pMagicAtk
	_values[Type.DEF] = pDef
	_values[Type.MAGIC_DEF] = pMagicDef
	_values[Type.MOVE_SPEED] = pMoveSpeed
	_values[Type.ATTACK_INTERVAL_FRAMES] = pAttackIntervalFrames
	_values[Type.ATK_RANGE] = pAtkRange
	_values[Type.ACQUISITION_RANGE] = pAcquisitionRange


static func IsValidType(type: int) -> bool:
	return 0 <= type and type < Type.COUNT


func Get(type: Type) -> int:
	if not IsValidType(type):
		push_error("CharacterStats: 올바르지 않은 StatType입니다. type: " + str(type))
		return 0

	return _values[type]


func CopyValues() -> PackedInt32Array:
	return _values.duplicate()
