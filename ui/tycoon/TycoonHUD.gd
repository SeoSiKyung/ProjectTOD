class_name TycoonHUD
extends PanelContainer

signal EndTurnRequested

@onready var _cycleLabel: Label = %CycleLabel
@onready var _turnLabel: Label = %TurnLabel
@onready var _goldLabel: Label = %GoldLabel
@onready var _foodLabel: Label = %FoodLabel
@onready var _woodLabel: Label = %WoodLabel
@onready var _stoneLabel: Label = %StoneLabel
@onready var _ironLabel: Label = %IronLabel
@onready var _magicStoneLabel: Label = %MagicStoneLabel
@onready var _populationLabel: Label = %PopulationLabel
@onready var _stabilityLabel: Label = %StabilityLabel
@onready var _endTurnButton: BasicButton = %EndTurnButton


func _ready() -> void:
	_endTurnButton.action_pressed.connect(_OnEndTurnPressed)


func Refresh(campaign: CampaignState, settlement: SettlementState) -> void:
	_cycleLabel.text = "Cycle %d" % campaign.cycle
	_turnLabel.text = "Turn %d / %d" % [campaign.currentTurn, campaign.cycleTurnLimit]
	_goldLabel.text = "Gold  %d" % settlement.gold
	_foodLabel.text = "Food  %d" % settlement.food
	_woodLabel.text = "Wood  %d" % settlement.wood
	_stoneLabel.text = "Stone  %d" % settlement.stone
	_ironLabel.text = "Iron  %d" % settlement.iron
	_magicStoneLabel.text = "MagicStone  %d" % settlement.magicStone
	_populationLabel.text = "Population  %d" % settlement.population
	_stabilityLabel.text = "Stability  %d" % settlement.stability


func SetEndTurnEnabled(enabled: bool) -> void:
	_endTurnButton.SetDisabled(not enabled)


func _OnEndTurnPressed(_actionKey: StringName) -> void:
	EndTurnRequested.emit()
