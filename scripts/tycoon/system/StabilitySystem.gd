class_name StabilitySystem
extends Node

const STABILITY_LOSS_PER_FOOD_SHORTAGE: int = 1
const MAX_STABILITY: int = 100

# =========================================================
# 턴 시작 안정도 처리
# =========================================================


func ProcessTurnStart(settlement: SettlementState, context: TurnContext) -> void:
	if context.stats == null:
		push_error("StabilitySystem: TurnContext에 DerivedStats가 없습니다.")
		return

	var previousStability: int = settlement.stability

	# =====================================================
	# 식량 부족으로 인한 안정도 감소
	# =====================================================
	var foodShortagePenalty: int = (context.foodShortage * STABILITY_LOSS_PER_FOOD_SHORTAGE)

	var targetStability: int = (settlement.stability - foodShortagePenalty)

	# =====================================================
	# 시설 효과 등에 의한 안정도 최저치
	# =====================================================
	var minimumStability: int = maxi(int(context.stats.stabilityMinimum), 0)

	# =====================================================
	# 범위 적용
	# =====================================================
	settlement.stability = clampi(targetStability, minimumStability, MAX_STABILITY)

	# =====================================================
	# 실제 적용된 변화량 기록
	# =====================================================
	context.stabilityChange = (settlement.stability - previousStability)
