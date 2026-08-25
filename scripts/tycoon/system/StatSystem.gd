class_name StatSystem
extends Node


var facility_catalog: FacilityCatalog


func setup(p_facility_catalog: FacilityCatalog) -> void:
	facility_catalog = p_facility_catalog


func calculate(settlement: SettlementState) -> DerivedStats:
	var stats := DerivedStats.new()

	if facility_catalog == null:
		push_error("StatSystem: FacilityCatalog이 설정되지 않았습니다.")
		return stats


	for facility_state in settlement.facilities:

		# 아직 완공되지 않은 시설은 효과 없음
		if not facility_state.is_built():
			continue


		var facility_data := facility_catalog.get_facility_data(
			facility_state.facility_id
		)

		if facility_data == null:
			push_warning(
				"StatSystem: 시설 데이터를 찾을 수 없습니다: %s"
				% facility_state.facility_id
			)
			continue


		# 레벨 시설:
		#   현재 레벨에 해당하는 FacilityLevelData 반환
		#
		# 비레벨 시설:
		#   base_data 반환
		var effect_data := facility_data.get_effect_data(
			facility_state.level
		)


		if effect_data == null:
			# 생산 / 발전 / 방어시설은 반드시
			# 현재 레벨에 해당하는 데이터가 있어야 함
			if facility_data.is_level_based():
				push_warning(
					"StatSystem: 효과 데이터를 찾을 수 없습니다: %s Lv.%d"
					% [
						facility_state.facility_id,
						facility_state.level
					]
				)

			# 기본 / 기능시설은 효과가 없는 시설일 수도 있으므로
			# base_data가 없어도 그냥 넘어감
			continue


		for effect in effect_data.effects:
			_apply_effect(stats, effect)


	return stats


func _apply_effect(
	stats: DerivedStats,
	effect: FacilityEffectData
) -> void:

	match effect.type:

		FacilityEffectData.EffectType.GOLD_INCOME:
			stats.gold_income += effect.value


		FacilityEffectData.EffectType.FOOD_DELTA:
			stats.food_delta += effect.value


		FacilityEffectData.EffectType.WOOD_INCOME:
			stats.wood_income += effect.value


		FacilityEffectData.EffectType.STONE_INCOME:
			stats.stone_income += effect.value


		FacilityEffectData.EffectType.IRON_INCOME:
			stats.iron_income += effect.value


		FacilityEffectData.EffectType.MAGIC_STONE_INCOME:
			stats.magic_stone_income += effect.value


		FacilityEffectData.EffectType.TECHNOLOGY:
			stats.technology += effect.value


		FacilityEffectData.EffectType.MAX_POPULATION:
			stats.max_population += int(effect.value)


		FacilityEffectData.EffectType.DEVELOPMENT:
			stats.development += effect.value


		FacilityEffectData.EffectType.DEFENSE_PHYSICAL_ATTACK_BONUS:
			stats.defense_physical_attack_bonus += effect.value


		FacilityEffectData.EffectType.STABILITY_MINIMUM:
			stats.stability_minimum = max(
				stats.stability_minimum,
				effect.value
			)
