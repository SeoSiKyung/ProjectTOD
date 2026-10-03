class_name DefenseResultView
extends Control

signal Confirmed(result: DefenseResult)

@onready var _resultContainer: VBoxContainer = $Margin/ResultContainer
@onready var _resultLabel: Label = _resultContainer.get_node("ResultLabel")
@onready var _elapsedTimeLabel: Label = _resultContainer.get_node("ElapsedTime")
@onready var _cpStatusLabel: Label = _resultContainer.get_node("CPStatus")
@onready var _recruitedPopulationLabel: Label = _resultContainer.get_node("RecruitedPopulation")
@onready var _survivingPopulationLabel: Label = _resultContainer.get_node("SurvivingPopulation")
@onready var _deadPopulationLabel: Label = _resultContainer.get_node("DeadPopulation")
@onready var _confirmButton: Button = _resultContainer.get_node("ConfirmButton")

var _result: DefenseResult


func _ready() -> void:
	_confirmButton.pressed.connect(_OnConfirmButtonPressed)


func ShowResult(result: DefenseResult) -> void:
	if result == null:
		return

	_result = result
	_resultLabel.text = "승리" if result.isVictory else "패배"
	_SetElapsedTime(result.elapsedTimeMs)
	_cpStatusLabel.text = "지휘소: 파괴" if result.cpDestroyed else "지휘소: 생존"
	_recruitedPopulationLabel.text = "징집 인구: %d명" % result.recruitedPopulation
	_survivingPopulationLabel.text = "생존 인구: %d명" % result.survivingPopulation
	_deadPopulationLabel.text = "사망 인구: %d명" % result.deadPopulation

	_confirmButton.disabled = false
	visible = true


func HideResult() -> void:
	visible = false
	_result = null


func _SetElapsedTime(elapsedTimeMs: int) -> void:
	var elapsedSeconds: int = Math.DivideInt(elapsedTimeMs, 1000)
	var minutes: int = Math.DivideInt(elapsedSeconds, 60)
	var seconds: int = Math.RemainderInt(elapsedSeconds, 60)

	_elapsedTimeLabel.text = "전투 시간: %02d:%02d" % [minutes, seconds]


func _OnConfirmButtonPressed() -> void:
	if _result == null:
		return

	var result: DefenseResult = _result
	_result = null
	_confirmButton.disabled = true
	Confirmed.emit(result)
