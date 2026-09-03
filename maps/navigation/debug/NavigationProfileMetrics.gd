class_name NavigationProfileMetrics
extends RefCounted

# NavigationService의 단일 FindPath 요청을 계측하기 위한 런타임 프로파일 데이터.
#
# NavigationService는 metrics가 설정된 경우에만 값을 기록하며,
# 측정 데이터의 생성 / 집계 / 출력은 NavigationBenchmark가 담당한다.
#
# 주요 목적:
# - FindPath 전체 단계별 소요 시간 확인
# - Grid / Anchor / Graph 탐색량 확인
# - Anchor Connection 내부 병목 분석
# - 최악의 단일 Portal Batch 탐색 특성 확인
#
# 일반 게임 실행에서는 metrics가 null이므로 계측하지 않는다.

#region Request
var targetCorrectionCount: int = 0 # jhw, 작업 필요

#endregion

#region Phase Time
var resolveTargetUsec: int = 0 # jhw, 작업 필요
var startAnchorConnectionUsec: int = 0
var targetAnchorConnectionUsec: int = 0
var anchorGraphUsec: int = 0
var fallbackGridUsec: int = 0

#endregion

#region Static Query
var segmentClearQueryCalls: int = 0
var staticSegmentChecks: int = 0

#endregion

#region Grid A*
# _FindGridPathInternal() 전체 계측.
# Complete Grid fallback뿐 아니라 Local Path / Component Probe에서 발생한 Grid A*도 모두 포함한다.
var gridSearchCalls: int = 0
var gridExpanded: int = 0
var gridRelaxed: int = 0

#endregion

#region Anchor Connection
#region Direct
var anchorDirectCheckUsec: int = 0
var anchorDirectCheckCount: int = 0
var anchorDirectSuccessCount: int = 0

#endregion

#region Component Probe
var anchorProbeUsec: int = 0
var anchorProbeCount: int = 0
var anchorProbeSuccessCount: int = 0

#endregion

#region Portal Batch
var anchorPortalBatchUsec: int = 0
var anchorPortalBatchSearchCalls: int = 0
var anchorPortalBatchExpanded: int = 0
var anchorPortalBatchRelaxed: int = 0

#endregion

#region Individual Fallback
var anchorIndividualFallbackUsec: int = 0
var anchorIndividualFallbackCount: int = 0
var anchorIndividualFallbackSuccessCount: int = 0

#endregion

#region Cache
# Region Anchor Connection request cache 계측.
# NavigationBenchmark에서는 각 측정 전에 request cache를 비우므로, baseline 측정에서는 Hit=0이 정상이다.
var anchorCacheHits: int = 0
var anchorCacheMisses: int = 0

#endregion
#endregion

#region Anchor Graph
var anchorGraphSearchCalls: int = 0
var anchorGraphExpanded: int = 0
var anchorGraphRelaxed: int = 0

#endregion

#region Worst Anchor Batch
var anchorBatchMaxUsec: int = 0
var anchorBatchMaxExpanded: int = 0
var anchorBatchMaxRelaxed: int = 0
var anchorBatchMaxTargetCount: int = 0
var anchorBatchMaxSearchArea: int = 0

#endregion

func ToDictionary() -> Dictionary:
	return {
		# Request
		"target_correction_count": targetCorrectionCount,
		# Phase Time
		"resolve_target_usec": resolveTargetUsec,
		"start_anchor_connection_usec": startAnchorConnectionUsec,
		"target_anchor_connection_usec": targetAnchorConnectionUsec,
		"anchor_graph_usec": anchorGraphUsec,
		"fallback_grid_usec": fallbackGridUsec,
		# Static Query
		"segment_clear_query_calls": segmentClearQueryCalls,
		"static_segment_checks": staticSegmentChecks,
		# Grid A*
		"grid_search_calls": gridSearchCalls,
		"grid_expanded": gridExpanded,
		"grid_relaxed": gridRelaxed,
		# Anchor Direct
		"anchor_direct_check_usec": anchorDirectCheckUsec,
		"anchor_direct_check_count": anchorDirectCheckCount,
		"anchor_direct_success_count": anchorDirectSuccessCount,
		# Anchor Probe
		"anchor_probe_usec": anchorProbeUsec,
		"anchor_probe_count": anchorProbeCount,
		"anchor_probe_success_count": anchorProbeSuccessCount,
		# Anchor Portal Batch
		"anchor_portal_batch_usec": anchorPortalBatchUsec,
		"anchor_portal_batch_search_calls": anchorPortalBatchSearchCalls,
		"anchor_portal_batch_expanded": anchorPortalBatchExpanded,
		"anchor_portal_batch_relaxed": anchorPortalBatchRelaxed,
		# Anchor Individual Fallback
		"anchor_individual_fallback_usec": anchorIndividualFallbackUsec,
		"anchor_individual_fallback_count": anchorIndividualFallbackCount,
		"anchor_individual_fallback_success_count": anchorIndividualFallbackSuccessCount,
		# Cache
		"anchor_cache_hits": anchorCacheHits,
		"anchor_cache_misses": anchorCacheMisses,
		# Anchor Graph
		"anchor_graph_search_calls": anchorGraphSearchCalls,
		"anchor_graph_expanded": anchorGraphExpanded,
		"anchor_graph_relaxed": anchorGraphRelaxed,
		# Worst Batch
		"anchor_batch_max_usec": anchorBatchMaxUsec,
		"anchor_batch_max_expanded": anchorBatchMaxExpanded,
		"anchor_batch_max_relaxed": anchorBatchMaxRelaxed,
		"anchor_batch_max_target_count": anchorBatchMaxTargetCount,
		"anchor_batch_max_search_area": anchorBatchMaxSearchArea,
	}
