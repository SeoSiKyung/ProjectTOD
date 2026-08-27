extends Node

var campaign: CampaignState
var settlement: SettlementState
var story: StoryState


func _ready() -> void:
	if (campaign == null or settlement == null or story == null):
		StartNewGame()


func StartNewGame() -> void:
	_CreateStates()
	_SetInitialCampaignState()
	_SetInitialSettlementState()


func _CreateStates() -> void:
	campaign = CampaignState.new()
	settlement = SettlementState.new()
	story = StoryState.new()


func _SetInitialCampaignState() -> void:
	campaign.cycle = 1
	campaign.currentTurn = 0
	campaign.cycleTurnLimit = 0
	campaign.currentPhase = CampaignState.Phase.TYCOON


func _SetInitialSettlementState() -> void:
	settlement.gold = 500
	settlement.food = 100
	settlement.wood = 200
	settlement.stone = 0
	settlement.iron = 0
	settlement.magicStone = 0

	settlement.population = 10
	settlement.stability = 100

# =========================================================
# 저장 데이터에서 복원된 State 장착
# =========================================================


func LoadGame(
	campaignState: CampaignState,
	settlementState: SettlementState,
	storyState: StoryState,
) -> void:
	campaign = campaignState
	settlement = settlementState
	story = storyState


func ResetGame() -> void:
	StartNewGame()
