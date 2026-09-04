class_name GameFlowController
extends Node

signal OffenseSceneRequested(startData: OffenseStartData)

signal DefenseSceneRequested(startData: DefenseStartData)

signal TycoonReturnRequested()

signal NextCycleRequested(cycle: int)

signal GameOverRequested(result: DefenseResult)

signal CampaignCompleted()

var _campaign: CampaignState
var _campaignData: CampaignData

var _tycoonController: TycoonController

# =========================================================
# 초기화
# =========================================================


func Setup(
	campaign: CampaignState,
	tycoonController: TycoonController,
	campaignData: CampaignData,
) -> void:
	_campaign = campaign
	_tycoonController = tycoonController
	_campaignData = campaignData

	_ConnectSignals()


func _ConnectSignals() -> void:
	if _tycoonController == null:
		return

	var offenseCallable := Callable(self, "_OnOffenseRequested")

	if not _tycoonController.OffenseRequested.is_connected(offenseCallable):
		_tycoonController.OffenseRequested.connect(offenseCallable)

	var defenseCallable := Callable(self, "_OnDefenseRequested")

	if not _tycoonController.DefenseRequested.is_connected(defenseCallable):
		_tycoonController.DefenseRequested.connect(defenseCallable)

# =========================================================
# Cycle
# =========================================================


func StartCurrentCycle() -> bool:
	if (_campaign == null or _campaignData == null or _tycoonController == null):
		return false

	if (_campaign.currentPhase != CampaignState.Phase.TYCOON):
		push_warning("GameFlowController: Tycoon Phase에서만 Cycle을 시작할 수 있습니다.")
		return false

	var cycleData := _campaignData.GetCycleData(_campaign.cycle)

	if cycleData == null:
		push_warning("GameFlowController: Cycle %d 데이터를 찾을 수 없습니다." % _campaign.cycle)
		return false

	if cycleData.turnLimit <= 0:
		push_warning("GameFlowController: Cycle의 turnLimit은 1 이상이어야 합니다.")
		return false

	return _tycoonController.StartCycle(cycleData.turnLimit)

# =========================================================
# Tycoon → 다른 Phase
# =========================================================


func _OnOffenseRequested(startData: OffenseStartData) -> void:
	OffenseSceneRequested.emit(startData)


func _OnDefenseRequested(startData: DefenseStartData) -> void:
	DefenseSceneRequested.emit(startData)

# =========================================================
# Offense → Tycoon
# =========================================================


func SubmitOffenseResult(result: OffenseResult) -> bool:
	if (_campaign == null or _tycoonController == null):
		return false

	if result == null:
		push_warning("GameFlowController: OffenseResult가 없습니다.")
		return false

	if (_campaign.currentPhase != CampaignState.Phase.OFFENSE):
		push_warning("GameFlowController: 현재 Offense Phase가 아닙니다.")
		return false

	_tycoonController.ApplyOffenseResult(result)

	TycoonReturnRequested.emit()

	return true

# =========================================================
# Defense 결과
# =========================================================


func SubmitDefenseResult(result: DefenseResult) -> bool:
	if (_campaign == null or _campaignData == null or _tycoonController == null):
		return false

	if result == null:
		push_warning("GameFlowController: DefenseResult가 없습니다.")
		return false

	if (_campaign.currentPhase != CampaignState.Phase.DEFENSE):
		push_warning("GameFlowController: 현재 Defense Phase가 아닙니다.")
		return false

	# =====================================================
	# Defense 패배
	# =====================================================
	if (not result.victory or result.commandPostDestroyed):
		GameOverRequested.emit(result)

		return true

	# =====================================================
	# 다음 Cycle 존재 여부 확인
	#
	# TycoonController.PrepareNextCycle()을 먼저 호출하면
	# 마지막 Cycle에서도 cycle 값이 증가해버리기 때문에
	# 여기서 먼저 검사.
	# =====================================================
	var nextCycle: int = (_campaign.cycle + 1)

	var nextCycleData := _campaignData.GetCycleData(nextCycle)

	# =====================================================
	# 다음 Cycle이 없으면 Campaign 종료
	# =====================================================
	if nextCycleData == null:
		CampaignCompleted.emit()

		return true

	# =====================================================
	# 다음 Cycle 준비
	# =====================================================
	_tycoonController.PrepareNextCycle()

	# =====================================================
	# CampaignData에 정의된 turnLimit으로
	# 다음 Cycle 실제 시작
	# =====================================================
	var cycleStarted := (_tycoonController.StartCycle(nextCycleData.turnLimit))

	if not cycleStarted:
		push_error("GameFlowController: 다음 Cycle 시작에 실패했습니다.")
		return false

	# =====================================================
	# 외부 Scene 계층에 Tycoon 전환 요청
	# =====================================================
	NextCycleRequested.emit(_campaign.cycle)

	return true
