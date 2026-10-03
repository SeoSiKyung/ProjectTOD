class_name DefenseResultView
extends Control

signal Confirmed(result: DefenseResult)

const VICTORY_COLOR: Color = Color(0.45, 0.28, 0.07, 1.0)
const DEFEAT_COLOR: Color = Color(0.48, 0.16, 0.11, 1.0)

@onready var _resultContainer: VBoxContainer = $ResultPanel/ResultContainer
@onready var _resultLabel: Label = _resultContainer.get_node("ResultLabel")
@onready var _stats: GridContainer = _resultContainer.get_node("Stats")
@onready var _elapsedTimeLabel: Label = _stats.get_node("ElapsedTime")
@onready var _cpStatusLabel: Label = _stats.get_node("CPStatus")
@onready var _recruitedPopulationLabel: Label = _stats.get_node("RecruitedPopulation")
@onready var _survivingPopulationLabel: Label = _stats.get_node("SurvivingPopulation")
@onready var _deadPopulationLabel: Label = _stats.get_node("DeadPopulation")
@onready var _confirmButton: BasicButton = _resultContainer.get_node("ConfirmCenter/ConfirmButton")

var _result: DefenseResult


func _ready() -> void:
	_confirmButton.pressed.connect(_OnConfirmButtonPressed)


func ShowResult(result: DefenseResult) -> void:
	if result == null:
		return

	_result = result
	_resultLabel.text = "승리" if result.isVictory else "패배"
	_resultLabel.add_theme_color_override(
		"font_color",
		VICTORY_COLOR if result.isVictory else DEFEAT_COLOR,
	)

	_SetElapsedTime(result.elapsedTimeMs)
	_cpStatusLabel.text = "파괴" if result.cpDestroyed else "생존"
	_cpStatusLabel.add_theme_color_override(
		"font_color",
		DEFEAT_COLOR if result.cpDestroyed else VICTORY_COLOR,
	)
	_recruitedPopulationLabel.text = "%d명" % result.recruitedPopulation
	_survivingPopulationLabel.text = "%d명" % result.survivingPopulation
	_deadPopulationLabel.text = "%d명" % result.deadPopulation

	_confirmButton.SetDisabled(false)
	visible = true


func HideResult() -> void:
	visible = false
	_result = null


func _SetElapsedTime(elapsedTimeMs: int) -> void:
	var elapsedSeconds: int = Math.DivideInt(elapsedTimeMs, 1000)
	var minutes: int = Math.DivideInt(elapsedSeconds, 60)
	var seconds: int = Math.RemainderInt(elapsedSeconds, 60)

	_elapsedTimeLabel.text = "%02d:%02d" % [minutes, seconds]


func _OnConfirmButtonPressed() -> void:
	if _result == null:
		return

	var result: DefenseResult = _result
	_result = null
	_confirmButton.SetDisabled(true)
	Confirmed.emit(result)
