extends Node2D
class_name Unit

@export var unitId: int = 0
@export_range(8, 256, 2) var footprintSize: int = 32
@export var playerControllable: bool = true

signal MoveSpeedChanged(moveSpeed: int)
signal MaxHpStatChanged(maxHpStat: int)
@export var moveSpeed: int = 96:
	set(value):
		if value < 0:
			push_error("Unit: moveSpeed는 0 이상의 값이어야 합니다.")
			return

		if moveSpeed == value:
			return

		moveSpeed = value
		MoveSpeedChanged.emit(moveSpeed)

@onready var fsm: UnitFSM = $UnitFSM

var characterKey: int = -1
var characterType: CharacterData.CharacterType = CharacterData.CharacterType.COUNT
var _baseStats: CharacterStats

var maxHp: int = 0
var currentHp: int = 0
var maxMp: int = 0
var currentMp: int = 0

var _bonusStats: BonusStats = BonusStats.new()
var _finalStats: PackedInt32Array = PackedInt32Array()
var _hpCapacityMultiplier: int = 1
var _unitRuntime: UnitRuntime


func _init() -> void:
	_finalStats.resize(CharacterStats.Type.COUNT)
	_finalStats.fill(0)


func _ready() -> void:
	fsm.BindUnit(self)
	add_to_group("unit")


func ConfigureCharacter(characterData: CharacterData) -> bool:
	if characterData == null or characterData.stats == null:
		push_error("Unit: CharacterData 또는 CharacterStats가 없습니다.")
		return false

	characterKey = characterData.characterKey
	characterType = characterData.characterType
	_baseStats = characterData.stats

	_bonusStats.Clear()
	_hpCapacityMultiplier = 1
	_RebuildFinalStats(true)
	return true


func HasCharacterStats() -> bool:
	return _baseStats != null


func GetBaseStat(type: CharacterStats.Type) -> int:
	if _baseStats == null:
		return 0

	return _baseStats.Get(type)


func GetStat(type: CharacterStats.Type) -> int:
	if not CharacterStats.IsValidType(type):
		return 0

	return _finalStats[type]


func AddStatBonus(type: CharacterStats.Type, flatValue: int, ratioValue: int) -> bool:
	if _baseStats == null or not _bonusStats.AddBonus(type, flatValue, ratioValue):
		return false

	_RebuildFinalStats(false)
	return true


func RemoveStatBonus(type: CharacterStats.Type, flatValue: int, ratioValue: int) -> bool:
	if _baseStats == null or not _bonusStats.RemoveBonus(type, flatValue, ratioValue):
		return false

	_RebuildFinalStats(false)
	return true


func ClearStatBonuses() -> void:
	if _baseStats == null:
		return

	_bonusStats.Clear()
	_RebuildFinalStats(false)


func SetHpCapacityMultiplier(multiplier: int, resetCurrentHp: bool = true) -> bool:
	if _baseStats == null or multiplier <= 0:
		return false

	_hpCapacityMultiplier = multiplier
	_RefreshVitalCapacity(resetCurrentHp)
	return true


func ResetVitals() -> void:
	if _baseStats == null:
		maxHp = 0
		currentHp = 0
		maxMp = 0
		currentMp = 0
		return

	_RefreshVitalCapacity(true)


func TakeDamage(damage: int) -> void:
	if damage <= 0 or IsDead():
		return

	currentHp = maxi(currentHp - damage, 0)


func IsDead() -> bool:
	return HasCharacterStats() and currentHp <= 0


func CalculateDamage(target: Unit) -> int:
	if target == null or not HasCharacterStats() or not target.HasCharacterStats():
		return 0

	return Math.CalculateDamage(
		GetStat(CharacterStats.Type.ATK),
		target.GetStat(CharacterStats.Type.DEF),
		GetStat(CharacterStats.Type.MAGIC_ATK),
		target.GetStat(CharacterStats.Type.MAGIC_DEF),
	)


func GetFootprintSize() -> int:
	return footprintSize


func GetHalfSize() -> int:
	return Math.DivideInt(footprintSize, 2)


func CanReceiveCommands() -> bool:
	return fsm != null and fsm.CanReceiveCommands()


func BindUnitRuntime(unitRuntime: UnitRuntime) -> void:
	_unitRuntime = unitRuntime


func IsMoving() -> bool:
	return is_instance_valid(_unitRuntime) and _unitRuntime.IsUnitMoving(unitId)


func PauseMovement() -> void:
	if is_instance_valid(_unitRuntime):
		_unitRuntime.PauseUnit(unitId)


func ResumeMovement() -> void:
	if is_instance_valid(_unitRuntime):
		_unitRuntime.ResumeUnit(unitId)


func StopMovement() -> void:
	if is_instance_valid(_unitRuntime):
		_unitRuntime.StopUnit(unitId)


func ApplyStun(duration: float) -> void:
	if fsm == null:
		return

	fsm.ApplyStun(duration)


func Die() -> void:
	if fsm == null:
		return

	fsm.Die()


func ResetForReuse() -> void:
	_unitRuntime = null

	if _baseStats != null:
		_bonusStats.Clear()
		_hpCapacityMultiplier = 1
		_RebuildFinalStats(true)

	if fsm != null:
		fsm.ResetForReuse()


func _RebuildFinalStats(resetVitals: bool) -> void:
	if _baseStats == null:
		_finalStats.fill(0)
		return

	var previousMaxHpStat: int = _finalStats[CharacterStats.Type.MAX_HP]

	for type: CharacterStats.Type in range(CharacterStats.Type.COUNT):
		var baseStat: int = _baseStats.Get(type)
		_finalStats[type] = baseStat + _bonusStats.GetBonus(type, baseStat)

	moveSpeed = maxi(GetStat(CharacterStats.Type.MOVE_SPEED), 0)
	_RefreshVitalCapacity(resetVitals)

	var maxHpStat: int = GetStat(CharacterStats.Type.MAX_HP)
	if previousMaxHpStat != maxHpStat:
		MaxHpStatChanged.emit(maxHpStat)


func _RefreshVitalCapacity(resetVitals: bool) -> void:
	var newMaxHp: int = maxi(GetStat(CharacterStats.Type.MAX_HP) * _hpCapacityMultiplier, 0)
	var newMaxMp: int = maxi(GetStat(CharacterStats.Type.MAX_MP), 0)

	if resetVitals:
		maxHp = newMaxHp
		currentHp = newMaxHp
		maxMp = newMaxMp
		currentMp = newMaxMp
		return

	var hpCapacityDelta: int = newMaxHp - maxHp
	var mpCapacityDelta: int = newMaxMp - maxMp
	var wasDead: bool = currentHp <= 0

	maxHp = newMaxHp
	maxMp = newMaxMp
	currentHp = 0 if wasDead else clampi(currentHp + hpCapacityDelta, 0, maxHp)
	currentMp = clampi(currentMp + mpCapacityDelta, 0, maxMp)
