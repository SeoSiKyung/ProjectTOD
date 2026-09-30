extends Node2D
class_name Unit

@export var unitId: int = 0
@export_range(8, 256, 2) var footprintSize: int = 32
@export var playerControllable: bool = true

signal MoveSpeedChanged(moveSpeed: int)
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
	if target == null or not target.HasCharacterStats():
		return 0

	return CalculateDamageAgainstDefense(
		target.GetStat(CharacterStats.Type.DEF),
		target.GetStat(CharacterStats.Type.MAGIC_DEF),
	)


func CalculateDamageAgainstDefense(defense: int, magicDefense: int) -> int:
	if not HasCharacterStats():
		return 0

	return Math.CalculateDamage(
		GetStat(CharacterStats.Type.ATK),
		defense,
		GetStat(CharacterStats.Type.MAGIC_ATK),
		magicDefense,
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
		_RebuildFinalStats(true)

	if fsm != null:
		fsm.ResetForReuse()


func _RebuildFinalStats(resetVitals: bool) -> void:
	if _baseStats == null:
		_finalStats.fill(0)
		return

	for type: CharacterStats.Type in range(CharacterStats.Type.COUNT):
		var baseStat: int = _baseStats.Get(type)
		_finalStats[type] = baseStat + _bonusStats.GetBonus(type, baseStat)

	moveSpeed = maxi(GetStat(CharacterStats.Type.MOVE_SPEED), 0)
	_RefreshVitalCapacity(resetVitals)


func _RefreshVitalCapacity(resetVitals: bool) -> void:
	var newMaxHp: int = _CalculateMaxHp()
	var newMaxMp: int = _CalculateMaxMp()

	if resetVitals:
		maxHp = newMaxHp
		currentHp = newMaxHp
		maxMp = newMaxMp
		currentMp = newMaxMp
		_OnVitalCapacityRefreshed(true)
		return

	var hpRecovery: int = _CalculateHpRecoveryOnCapacityIncrease(maxHp, newMaxHp)
	var mpRecovery: int = _CalculateMpRecoveryOnCapacityIncrease(maxMp, newMaxMp)

	maxHp = newMaxHp
	maxMp = newMaxMp
	currentHp = clampi(currentHp + hpRecovery, 0, maxHp)
	currentMp = clampi(currentMp + mpRecovery, 0, maxMp)
	_OnVitalCapacityRefreshed(false)


func _CalculateMaxHp() -> int:
	return maxi(GetStat(CharacterStats.Type.MAX_HP), 0)


func _CalculateMaxMp() -> int:
	return maxi(GetStat(CharacterStats.Type.MAX_MP), 0)


func _CalculateHpRecoveryOnCapacityIncrease(previousMaxHp: int, newMaxHp: int) -> int:
	return maxi(newMaxHp - previousMaxHp, 0)


func _CalculateMpRecoveryOnCapacityIncrease(previousMaxMp: int, newMaxMp: int) -> int:
	return maxi(newMaxMp - previousMaxMp, 0)


func _OnVitalCapacityRefreshed(_resetVitals: bool) -> void:
	pass
