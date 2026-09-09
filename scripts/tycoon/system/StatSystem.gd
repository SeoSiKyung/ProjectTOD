class_name StatSystem
extends Node

var _facilityCatalog: FacilityCatalog


func Setup(facilityCatalog: FacilityCatalog) -> void:
	_facilityCatalog = facilityCatalog


func Calculate(settlement: SettlementState) -> DerivedStats:
	var stats := DerivedStats.new()

	if _facilityCatalog == null:
		push_error("StatSystem: FacilityCatalog이 설정되지 않았습니다.")
		return stats

	for facilityState in settlement.facilities:
		# 아직 완공되지 않은 시설은 효과 없음
		if not facilityState.IsBuilt():
			continue

		var facilityData := _facilityCatalog.GetFacilityData(facilityState.facilityId)

		if facilityData == null:
			push_warning("StatSystem: 시설 데이터를 찾을 수 없습니다: %s" % facilityState.facilityId)
			continue

		# 레벨 시설:
		#   현재 레벨에 해당하는 FacilityLevelData 반환
		#
		# 비레벨 시설:
		#   base_data 반환
		var effectData := facilityData.GetEffectData(facilityState.level)

		if effectData == null:
			# 생산 / 발전 / 방어시설은 반드시
			# 현재 레벨에 해당하는 데이터가 있어야 함
			if facilityData.IsLevelBased():
				push_warning(
					"StatSystem: 효과 데이터를 찾을 수 없습니다: %s Lv.%d"
					% [facilityState.facilityId, facilityState.level]
				)

			# 기본 / 기능시설은 효과가 없는 시설일 수도 있으므로
			# base_data가 없어도 그냥 넘어감
			continue

		for effect in effectData.effects:
			_ApplyEffect(stats, effect)

	return stats


func _ApplyEffect(stats: DerivedStats, effect: FacilityEffectData) -> void:
	match effect.type:
		FacilityEffectData.EffectType.GOLD_INCOME:
			stats.goldIncome += effect.value

		FacilityEffectData.EffectType.FOOD_DELTA:
			stats.foodDelta += effect.value

		FacilityEffectData.EffectType.WOOD_INCOME:
			stats.woodIncome += effect.value

		FacilityEffectData.EffectType.STONE_INCOME:
			stats.stoneIncome += effect.value

		FacilityEffectData.EffectType.IRON_INCOME:
			stats.ironIncome += effect.value

		FacilityEffectData.EffectType.MAGIC_STONE_INCOME:
			stats.magicStoneIncome += effect.value

		FacilityEffectData.EffectType.TECHNOLOGY:
			stats.technology += effect.value

		FacilityEffectData.EffectType.MAX_POPULATION:
			stats.maxPopulation += int(effect.value)

		FacilityEffectData.EffectType.DEVELOPMENT:
			stats.development += effect.value

		FacilityEffectData.EffectType.STABILITY_MINIMUM:
			stats.stabilityMinimum = max(stats.stabilityMinimum, effect.value)
