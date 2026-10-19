class_name NavigationPortalComparison
extends RefCounted

const REVISION: String = "portal-comparison-v1"
const LENGTH_TOLERANCE: float = 0.05


static func CreateCases() -> Array[Dictionary]:
	return [
		{
			"id": "CP_Max_Unit12",
			"label": "CP 직후 최대 요청 / 유닛 12",
			"start": Vector2(616.0526, 280.3444),
		},
		{
			"id": "Rebuild_Unit13",
			"label": "이동 중 재탐색 / 유닛 13",
			"start": Vector2(1028.697, 334.0511),
		},
		{ "id": "Rebuild_Unit5", "label": "이동 중 재탐색 / 유닛 5", "start": Vector2(1061.711, 366.0511) },
		{ "id": "Rebuild_Unit9", "label": "이동 중 재탐색 / 유닛 9", "start": Vector2(1096.416, 398.2109) },
		{ "id": "Rebuild_Unit24", "label": "이동 중 재탐색 / 유닛 24", "start": Vector2(1103.24, 443.8123) },
		{
			"id": "Rebuild_Unit12",
			"label": "이동 중 재탐색 / 유닛 12",
			"start": Vector2(1080.955, 385.2915),
		},
	]


static func RunPair(
	service: NavigationService,
	position: Vector2,
	individualFirst: bool,
) -> Dictionary:
	if not service.CanPlaceStatic(position, 16):
		return { "error": "로그 좌표에 반크기 16 유닛을 배치할 수 없습니다." }
	var previousMetrics: NavigationProfileMetrics = service.GetProfileMetrics()
	var batch: Dictionary
	var individual: Dictionary
	if individualFirst:
		individual = _Measure(service, position, true)
		batch = _Measure(service, position, false)
	else:
		batch = _Measure(service, position, false)
		individual = _Measure(service, position, true)
	service.ClearProfileMetrics()
	var validation: Dictionary = _Validate(
		service,
		position,
		batch["connections"],
		individual["connections"],
	)
	batch.erase("connections")
	individual.erase("connections")
	service.ClearBenchmarkRequestCache()
	service.SetProfileMetrics(previousMetrics)
	return {
		"order": "individual,batch" if individualFirst else "batch,individual",
		"batch": batch,
		"individual": individual,
		"validation": validation,
	}


static func _Measure(service: NavigationService, position: Vector2, individual: bool) -> Dictionary:
	service.ClearBenchmarkRequestCache()
	var metrics: NavigationProfileMetrics = NavigationProfileMetrics.new()
	metrics.capturePortalBatchDetails = true
	service.SetProfileMetrics(metrics)
	var started: int = Time.get_ticks_usec()
	var connections: Array[NavigationAnchorTypes.Connection] = service.BuildRegionConnectionsForBenchmark(
		position,
		16,
		0,
		individual,
	)
	var elapsed: int = Time.get_ticks_usec() - started
	service.ClearProfileMetrics()
	var lengthSum: float = 0.0
	for connection: NavigationAnchorTypes.Connection in connections:
		lengthSum += _PathLength(position, connection.path)
	return {
		"elapsed_usec": elapsed,
		"expanded": metrics.gridExpanded + metrics.anchorPortalBatchExpanded,
		"relaxed": metrics.gridRelaxed + metrics.anchorPortalBatchRelaxed,
		"anchor_count": connections.size(),
		"length_sum": lengthSum,
		"metrics": metrics.ToDictionary(),
		"portal_details": metrics.GetPortalBatchDetails(),
		"connections": connections,
	}


static func _Validate(
	service: NavigationService,
	position: Vector2,
	batch: Array[NavigationAnchorTypes.Connection],
	individual: Array[NavigationAnchorTypes.Connection],
) -> Dictionary:
	var invalidBatch: int = service.ValidateRegionConnectionsForBenchmark(position, 16, 0, batch)
	var invalidIndividual: int = service.ValidateRegionConnectionsForBenchmark(
		position,
		16,
		0,
		individual,
	)
	var batchByKey: Dictionary[Vector2i, NavigationAnchorTypes.Connection] = { }
	var individualByKey: Dictionary[Vector2i, NavigationAnchorTypes.Connection] = { }
	for connection: NavigationAnchorTypes.Connection in batch:
		batchByKey[connection.nodeKey] = connection
	for connection: NavigationAnchorTypes.Connection in individual:
		individualByKey[connection.nodeKey] = connection
	var sameSet: bool = batchByKey.size() == individualByKey.size() and not batchByKey.is_empty()
	var longer: int = 0
	var shorter: int = 0
	var maxIncrease: float = 0.0
	var maxAbsoluteDifference: float = 0.0
	var pairs: Array[Dictionary] = []
	for key: Vector2i in batchByKey:
		if not individualByKey.has(key):
			sameSet = false
			continue
		var batchLength: float = _PathLength(position, batchByKey[key].path)
		var individualLength: float = _PathLength(position, individualByKey[key].path)
		var difference: float = individualLength - batchLength
		maxIncrease = maxf(maxIncrease, difference)
		maxAbsoluteDifference = maxf(maxAbsoluteDifference, absf(difference))
		if difference > LENGTH_TOLERANCE:
			longer += 1
		if difference < -LENGTH_TOLERANCE:
			shorter += 1
		pairs.append(
			{
				"anchor": [key.x, key.y],
				"batch_length": batchLength,
				"individual_length": individualLength,
				"difference": difference,
			}
		)
	return {
		"same_anchor_set": sameSet,
		"nonempty_results": not batch.is_empty() and not individual.is_empty(),
		"invalid_batch_paths": invalidBatch,
		"invalid_individual_paths": invalidIndividual,
		"longer_paths": longer,
		"shorter_paths": shorter,
		"max_length_increase": maxIncrease,
		"max_absolute_length_difference": maxAbsoluteDifference,
		"length_pairs": pairs,
		"passed": sameSet and invalidBatch == 0 and invalidIndividual == 0 and longer == 0,
	}


static func _PathLength(start: Vector2, path: PackedVector2Array) -> float:
	var length: float = 0.0
	var previous: Vector2 = start
	for point: Vector2 in path:
		length += previous.distance_to(point)
		previous = point
	return length


static func Summarize(
	caseData: Dictionary,
	runs: Array[Dictionary],
	warmups: int,
	error: String,
) -> Dictionary:
	var summary: Dictionary = {
		"id": caseData["id"],
		"label": caseData["label"],
		"start": [caseData["start"].x, caseData["start"].y],
		"region": 0,
		"half_size": 16,
		"warmup_pairs": warmups,
		"measurement_pairs": runs.size(),
		"error": error,
		"runs": runs,
		"same_set_pairs": 0,
		"valid_pairs": 0,
		"passed_pairs": 0,
		"longer_paths": 0,
		"shorter_paths": 0,
		"max_length_increase": 0.0,
		"max_absolute_length_difference": 0.0,
	}
	for variant: String in ["batch", "individual"]:
		var times: Array[int] = []
		var expanded: int = 0
		var relaxed: int = 0
		var anchorCount: int = 0
		var lengthSum: float = 0.0
		for run: Dictionary in runs:
			var sample: Dictionary = run[variant]
			times.append(sample["elapsed_usec"])
			expanded += int(sample["expanded"])
			relaxed += int(sample["relaxed"])
			anchorCount += int(sample["anchor_count"])
			lengthSum += float(sample["length_sum"])
		var statistics: Dictionary = _Statistics(times)
		var count: int = maxi(1, runs.size())
		statistics["expanded_avg"] = float(expanded) / count
		statistics["relaxed_avg"] = float(relaxed) / count
		statistics["anchors_avg"] = float(anchorCount) / count
		statistics["length_sum_avg"] = lengthSum / count
		summary[variant] = statistics
	for run: Dictionary in runs:
		var check: Dictionary = run["validation"]
		if check["same_anchor_set"]:
			summary["same_set_pairs"] += 1
		if (
			check["nonempty_results"] and check["invalid_batch_paths"] == 0
			and check["invalid_individual_paths"] == 0
		):
			summary["valid_pairs"] += 1
		if check["passed"]:
			summary["passed_pairs"] += 1
		summary["longer_paths"] += int(check["longer_paths"])
		summary["shorter_paths"] += int(check["shorter_paths"])
		summary["max_length_increase"] = maxf(
			summary["max_length_increase"],
			check["max_length_increase"],
		)
		summary["max_absolute_length_difference"] = maxf(
			summary["max_absolute_length_difference"],
			check["max_absolute_length_difference"],
		)
	return summary


static func _Statistics(times: Array[int]) -> Dictionary:
	if times.is_empty():
		return { "average_usec": 0.0, "p50_usec": 0, "p95_usec": 0, "max_usec": 0 }
	var sorted: Array[int] = times.duplicate()
	sorted.sort()
	var total: int = 0
	for time: int in times:
		total += time
	return {
		"average_usec": float(total) / times.size(),
		"p50_usec": sorted[ceili((sorted.size() - 1) * 0.50)],
		"p95_usec": sorted[ceili((sorted.size() - 1) * 0.95)],
		"max_usec": sorted[-1],
	}


static func FormatResult(result: Dictionary) -> String:
	if not str(result["error"]).is_empty():
		return "[b]측정 중단[/b]\n" + str(result["error"])
	var batch: Dictionary = result["batch"]
	var individual: Dictionary = result["individual"]
	var output: String = "[b]%s[/b]\n시작 %s / Region 0 / 반크기 16\n" % [
		result["label"],
		result["start"],
	]
	output += "준비 %d쌍 · 측정 %d쌍 · A/B 순서 교대\n\n" % [
		result["warmup_pairs"],
		result["measurement_pairs"],
	]
	output += "[table=3][cell][b]시작 Region 연결[/b][/cell][cell][b]기존 Batch[/b][/cell][cell][b]목표별 개별 탐색[/b][/cell]"
	for row: Array in [
		["평균", "average_usec"],
		["P50", "p50_usec"],
		["P95", "p95_usec"],
		["최대", "max_usec"],
	]:
		output += "[cell]%s[/cell][cell]%.3f ms[/cell][cell]%.3f ms[/cell]" % [
			row[0],
			float(batch[row[1]]) / 1000.0,
			float(individual[row[1]]) / 1000.0,
		]
	for row: Array in [
		["평균 확장 수", "expanded_avg"],
		["평균 갱신 수", "relaxed_avg"],
		["반환 Anchor", "anchors_avg"],
		["경로 길이 합계", "length_sum_avg"],
	]:
		output += "[cell]%s[/cell][cell]%.2f[/cell][cell]%.2f[/cell]" % [
			row[0],
			batch[row[1]],
			individual[row[1]],
		]
	output += "[/table]\n\n[b]경로 검증[/b]\n"
	output += "Anchor 집합 일치 %d/%d쌍 · 양쪽 경로 유효 %d/%d쌍\n" % [
		result["same_set_pairs"],
		result["measurement_pairs"],
		result["valid_pairs"],
		result["measurement_pairs"],
	]
	output += "개별 탐색의 길이 증가 %d건 · 감소 %d건 (반복 합계)\n" % [
		result["longer_paths"],
		result["shorter_paths"],
	]
	output += "최대 길이 증가 %.4f px · 최대 절대 차이 %.4f px\n" % [
		result["max_length_increase"],
		result["max_absolute_length_difference"],
	]
	output += "집합 일치 + 유효 + 길이 증가 없음: %d/%d쌍\n\n" % [
		result["passed_pairs"],
		result["measurement_pairs"],
	]
	output += "복수 목표 가중치 1.0 · 동일 탐색 경계 · 길이 허용 오차 0.05px\n"
	output += "각 방식 실행 전 요청 캐시 초기화 · 사전 계산/연결 구조 유지\n"
	output += "로그의 반올림 좌표로 만든 비교 실험 / 실제 이동 완료는 별도 검증\n"
	output += "%s / commit %s" % [
		REVISION,
		str(result.get("source_commit", "UNAVAILABLE")).substr(0, 12),
	]
	return output
