extends Node

var campaign: CampaignState
var settlement: SettlementState
var story: StoryState
var event: EventState


func _ready() -> void:
	if (campaign == null or settlement == null or story == null or event == null):
		StartNewGame()


func StartNewGame() -> void:
	_CreateStates()
	_SetInitialCampaignState()
	_SetInitialSettlementState()
	_CreateInitialFacilities()


func _CreateStates() -> void:
	campaign = CampaignState.new()
	settlement = SettlementState.new()
	story = StoryState.new()
	event = EventState.new()


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
# 초기 시설
# =========================================================


func _CreateInitialFacilities() -> void:
	_AddInitialFacility(&"lord_manor")

	_AddInitialFacility(&"tavern")

	_AddInitialFacility(&"command_post")


func _AddInitialFacility(facilityId: StringName) -> void:
	var facilityState := FacilityState.new()

	facilityState.facilityId = facilityId
	facilityState.level = 0
	facilityState.status = FacilityState.Status.BUILT

	settlement.facilities.append(facilityState)

# =========================================================
# 저장 데이터에서 복원된 State 장착
# =========================================================


func LoadGame(
	campaignState: CampaignState,
	settlementState: SettlementState,
	storyState: StoryState,
	eventState: EventState,
) -> void:
	campaign = campaignState
	settlement = settlementState
	story = storyState
	event = eventState


func ResetGame() -> void:
	StartNewGame()
