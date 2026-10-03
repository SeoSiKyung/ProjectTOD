class_name DefenseBattleHUDView
extends Control

signal pause_pressed

@onready var _battleHUDContainer: VBoxContainer = $HUDPanel/BattleHUDContainer
@onready var _elapsedTime: Label = _battleHUDContainer.get_node("BattleHeader/ElapsedTime")
@onready var _pauseButton: BasicButton = _battleHUDContainer.get_node("BattleHeader/PauseButton")

@onready var _cpHUD: VBoxContainer = _battleHUDContainer.get_node("CPHUD")
@onready var _cpHp: HBoxContainer = _cpHUD.get_node("Hp")
@onready var _cpHpLabel: Label = _cpHp.get_node("HpLabel")
@onready var _cpHpBar: ProgressBar = _cpHp.get_node("HpBar")
@onready var _cpMp: HBoxContainer = _cpHUD.get_node("Mp")
@onready var _cpMpLabel: Label = _cpMp.get_node("MpLabel")
@onready var _cpMpBar: ProgressBar = _cpMp.get_node("MpBar")

@onready var _population: HBoxContainer = _battleHUDContainer.get_node("Population")
@onready var _recruitedPopulation: Label = _population.get_node("Recruited/Value")
@onready var _survivingPopulation: Label = _population.get_node("Surviving/Value")
@onready var _deadPopulation: Label = _population.get_node("Dead/Value")

var _displayedBattleTimeSeconds: int = -1

var _displayedCPHp: int = -1
var _displayedCPMaxHp: int = -1
var _displayedCPMp: int = -1
var _displayedCPMaxMp: int = -1

var _displayedRecruitedPopulation: int = -1
var _displayedSurvivingPopulation: int = -1
var _displayedDeadPopulation: int = -1


func _ready() -> void:
	_pauseButton.pressed.connect(_OnPauseButtonPressed)


func ShowBattle() -> void:
	_ResetDisplayCache()
	SetPaused(false)
	SetPauseDisabled(false)
	visible = true


func HideBattle() -> void:
	visible = false


func SetPaused(isPaused: bool) -> void:
	_pauseButton.textKey = "계속" if isPaused else "일시정지"


func SetPauseDisabled(isDisabled: bool) -> void:
	_pauseButton.SetDisabled(isDisabled)


func UpdateBattleTime(elapsedTimeMs: int) -> void:
	var elapsedSeconds: int = Math.DivideInt(elapsedTimeMs, 1000)
	if elapsedSeconds == _displayedBattleTimeSeconds:
		return

	_displayedBattleTimeSeconds = elapsedSeconds

	var minutes: int = Math.DivideInt(elapsedSeconds, 60)
	var seconds: int = Math.RemainderInt(elapsedSeconds, 60)
	_elapsedTime.text = "%02d:%02d" % [minutes, seconds]


func UpdateCP(currentHp: int, maxHp: int, currentMp: int, maxMp: int) -> void:
	if currentHp != _displayedCPHp or maxHp != _displayedCPMaxHp:
		_displayedCPHp = currentHp
		_displayedCPMaxHp = maxHp

		_cpHpBar.max_value = maxHp
		_cpHpBar.value = currentHp
		_cpHpLabel.text = "%d / %d" % [currentHp, maxHp]

	if maxMp <= 0:
		_cpMp.visible = false
		_displayedCPMp = currentMp
		_displayedCPMaxMp = maxMp
		return

	_cpMp.visible = true
	if currentMp == _displayedCPMp and maxMp == _displayedCPMaxMp:
		return

	_displayedCPMp = currentMp
	_displayedCPMaxMp = maxMp

	_cpMpBar.max_value = maxMp
	_cpMpBar.value = currentMp
	_cpMpLabel.text = "%d / %d" % [currentMp, maxMp]


func UpdatePopulation(
	recruitedPopulation: int,
	survivingPopulation: int,
	deadPopulation: int,
) -> void:
	if (
		recruitedPopulation == _displayedRecruitedPopulation
		and survivingPopulation == _displayedSurvivingPopulation
		and deadPopulation == _displayedDeadPopulation
	):
		return

	_displayedRecruitedPopulation = recruitedPopulation
	_displayedSurvivingPopulation = survivingPopulation
	_displayedDeadPopulation = deadPopulation

	_recruitedPopulation.text = "%d명" % recruitedPopulation
	_survivingPopulation.text = "%d명" % survivingPopulation
	_deadPopulation.text = "%d명" % deadPopulation


func _ResetDisplayCache() -> void:
	_displayedBattleTimeSeconds = -1

	_displayedCPHp = -1
	_displayedCPMaxHp = -1
	_displayedCPMp = -1
	_displayedCPMaxMp = -1

	_displayedRecruitedPopulation = -1
	_displayedSurvivingPopulation = -1
	_displayedDeadPopulation = -1


func _OnPauseButtonPressed() -> void:
	pause_pressed.emit()
