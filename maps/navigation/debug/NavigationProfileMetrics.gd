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

#region Command

var commandTargetCorrectionUsec: int = 0
var commandBuildPathsUsec: int = 0
var commandAssignmentUsec: int = 0

#endregion

#region Group Build

var groupJoinPointUsec: int = 0
var groupSharedPathUsec: int = 0
var groupUnitPathsUsec: int = 0

var groupJoinSegmentAttempts: int = 0
var groupJoinSegmentSuccesses: int = 0

var groupJoinWaypointAttempts: int = 0
var groupJoinWaypointSuccesses: int = 0

var groupJoinFallbackCalls: int = 0
var groupJoinFallbackSuccesses: int = 0

#endregion

#region Phase Time

var startAnchorConnectionUsec: int = 0
var targetAnchorConnectionUsec: int = 0
var anchorGraphUsec: int = 0
var fallbackGridUsec: int = 0

#endregion

#region Static Query

var segmentClearQueryUsec: int = 0
var segmentClearQueryCalls: int = 0
var staticSegmentChecks: int = 0

#endregion

#region Optional Static Query Details

var captureStaticQueryDetails: bool = false
var staticQueryTick: int = 0 # 0: 명령 처리 또는 Path Build, 1 이상: 이동 틱.
var staticDetailCalls: int = 0
var staticDetailClearCalls: int = 0
var staticDetailInvalidEndCalls: int = 0
var staticDetailRecoveryCalls: int = 0
var staticDetailEndpointUsec: int = 0
var staticDetailSweepUsec: int = 0
var staticDetailBroadCalls: int = 0
var staticDetailBroadCells: int = 0
var staticDetailBroadBlocked: int = 0
var staticDetailPrefixEmptyCalls: int = 0
var staticDetailRowsVisited: int = 0
var staticDetailIntersectionChecks: int = 0
var staticDetailWorstUsec: int = -1
var staticDetailWorstEndpointUsec: int = 0
var staticDetailWorstSweepUsec: int = 0
var staticDetailWorstStart: Vector2 = Vector2.ZERO
var staticDetailWorstEnd: Vector2 = Vector2.ZERO
var staticDetailWorstHalfSize: int = 0
var staticDetailWorstClear: bool = false
var staticDetailWorstTick: int = 0
var staticDetailWorstBroadCells: int = 0
var staticDetailWorstBroadBlocked: int = 0
var staticDetailWorstIntersectionChecks: int = 0

#endregion

#region Optional Portal Batch Details

var capturePortalBatchDetails: bool = false
var portalBatchTick: int = 0
var portalDetailCalls: int = 0
var portalDetailGridCalls: int = 0
var portalDetailPreparationUsec: int = 0
var portalDetailGridUsec: int = 0
var portalDetailFinalizationUsec: int = 0
var portalDetailGridPreparationUsec: int = 0
var portalDetailGridSearchUsec: int = 0
var portalDetailGridReconstructionUsec: int = 0
var portalDetailGridReconstructionCalls: int = 0
var portalDetailGridReturnedPaths: int = 0
var portalDetailGridReconstructedWaypoints: int = 0
var portalDetailWorstUsec: int = -1
var portalDetailWorstPreparationUsec: int = 0
var portalDetailWorstGridUsec: int = 0
var portalDetailWorstFinalizationUsec: int = 0
var portalDetailWorstStart: Vector2 = Vector2.ZERO
var portalDetailWorstRegion: int = -1
var portalDetailWorstTick: int = 0
var portalDetailWorstTargetCount: int = 0
var portalDetailWorstExpanded: int = 0
var portalDetailWorstRelaxed: int = 0
var portalDetailWorstSearchArea: int = 0
var portalDetailWorstGridPreparationUsec: int = 0
var portalDetailWorstGridSearchUsec: int = 0
var portalDetailWorstGridReconstructionUsec: int = 0
var portalDetailWorstGridReconstructionCalls: int = 0
var portalDetailWorstGridReturnedPaths: int = 0
var portalDetailWorstGridReconstructedWaypoints: int = 0

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


func RecordPortalBatchDetails(
	start: Vector2,
	regionId: int,
	preparationUsec: int,
	gridUsec: int,
	finalizationUsec: int,
	targetCount: int = 0,
	expanded: int = 0,
	relaxed: int = 0,
	searchArea: int = 0,
	gridCalled: bool = false,
	gridPreparationUsec: int = 0,
	gridSearchUsec: int = 0,
	gridReconstructionUsec: int = 0,
	reconstructionCalls: int = 0,
	returnedPaths: int = 0,
	reconstructedWaypoints: int = 0,
) -> void:
	portalDetailCalls += 1
	if gridCalled:
		portalDetailGridCalls += 1
	portalDetailPreparationUsec += preparationUsec
	portalDetailGridUsec += gridUsec
	portalDetailFinalizationUsec += finalizationUsec
	portalDetailGridPreparationUsec += gridPreparationUsec
	portalDetailGridSearchUsec += gridSearchUsec
	portalDetailGridReconstructionUsec += gridReconstructionUsec
	portalDetailGridReconstructionCalls += reconstructionCalls
	portalDetailGridReturnedPaths += returnedPaths
	portalDetailGridReconstructedWaypoints += reconstructedWaypoints
	var elapsed: int = preparationUsec + gridUsec + finalizationUsec
	if elapsed > portalDetailWorstUsec:
		portalDetailWorstUsec = elapsed
		portalDetailWorstPreparationUsec = preparationUsec
		portalDetailWorstGridUsec = gridUsec
		portalDetailWorstFinalizationUsec = finalizationUsec
		portalDetailWorstStart = start
		portalDetailWorstRegion = regionId
		portalDetailWorstTick = portalBatchTick
		portalDetailWorstTargetCount = targetCount
		portalDetailWorstExpanded = expanded
		portalDetailWorstRelaxed = relaxed
		portalDetailWorstSearchArea = searchArea
		portalDetailWorstGridPreparationUsec = gridPreparationUsec
		portalDetailWorstGridSearchUsec = gridSearchUsec
		portalDetailWorstGridReconstructionUsec = gridReconstructionUsec
		portalDetailWorstGridReconstructionCalls = reconstructionCalls
		portalDetailWorstGridReturnedPaths = returnedPaths
		portalDetailWorstGridReconstructedWaypoints = reconstructedWaypoints


func GetPortalBatchDetails() -> Dictionary:
	if not capturePortalBatchDetails:
		return { }
	var worst: Dictionary = { }
	if portalDetailCalls > 0:
		worst = {
			"elapsed_usec": portalDetailWorstUsec,
			"preparation_usec": portalDetailWorstPreparationUsec,
			"grid_batch_usec": portalDetailWorstGridUsec,
			"finalization_usec": portalDetailWorstFinalizationUsec,
			"start": [portalDetailWorstStart.x, portalDetailWorstStart.y],
			"region_id": portalDetailWorstRegion,
			"tick": portalDetailWorstTick,
			"target_count": portalDetailWorstTargetCount,
			"expanded": portalDetailWorstExpanded,
			"relaxed": portalDetailWorstRelaxed,
			"search_area": portalDetailWorstSearchArea,
			"grid_internal": {
				"preparation_usec": portalDetailWorstGridPreparationUsec,
				"search_excluding_reconstruction_usec": portalDetailWorstGridSearchUsec,
				"reconstruction_usec": portalDetailWorstGridReconstructionUsec,
				"reconstruction_calls": portalDetailWorstGridReconstructionCalls,
				"returned_paths": portalDetailWorstGridReturnedPaths,
				"reconstructed_waypoints": portalDetailWorstGridReconstructedWaypoints,
			},
		}
	return {
		"calls": portalDetailCalls,
		"grid_calls": portalDetailGridCalls,
		"skipped_before_grid": portalDetailCalls - portalDetailGridCalls,
		"preparation_usec": portalDetailPreparationUsec,
		"grid_batch_usec": portalDetailGridUsec,
		"finalization_usec": portalDetailFinalizationUsec,
		"measured_total_usec": portalDetailPreparationUsec + portalDetailGridUsec
		+ portalDetailFinalizationUsec,
		"worst_batch": worst,
		"grid_internal": {
			"calls": portalDetailGridCalls,
			"preparation_usec": portalDetailGridPreparationUsec,
			"search_excluding_reconstruction_usec": portalDetailGridSearchUsec,
			"reconstruction_usec": portalDetailGridReconstructionUsec,
			"reconstruction_calls": portalDetailGridReconstructionCalls,
			"returned_paths": portalDetailGridReturnedPaths,
			"reconstructed_waypoints": portalDetailGridReconstructedWaypoints,
		},
	}


func GetStaticQueryDetails() -> Dictionary:
	if not captureStaticQueryDetails:
		return { }
	var worst: Dictionary = { }
	if staticDetailCalls > 0:
		worst = {
			"elapsed_usec": staticDetailWorstUsec,
			"endpoint_checks_usec": staticDetailWorstEndpointUsec,
			"sweep_usec": staticDetailWorstSweepUsec,
			"start": [staticDetailWorstStart.x, staticDetailWorstStart.y],
			"end": [staticDetailWorstEnd.x, staticDetailWorstEnd.y],
			"half_size": staticDetailWorstHalfSize,
			"clear": staticDetailWorstClear,
			"tick": staticDetailWorstTick,
			"broad_cell_count": staticDetailWorstBroadCells,
			"broad_blocked_count": staticDetailWorstBroadBlocked,
			"intersection_checks": staticDetailWorstIntersectionChecks,
		}
	return {
		"calls": staticDetailCalls,
		"clear_calls": staticDetailClearCalls,
		"invalid_end_calls": staticDetailInvalidEndCalls,
		"recovery_calls": staticDetailRecoveryCalls,
		"endpoint_checks_usec": staticDetailEndpointUsec,
		"sweep_usec": staticDetailSweepUsec,
		"broad_calls": staticDetailBroadCalls,
		"broad_cell_count": staticDetailBroadCells,
		"broad_blocked_count": staticDetailBroadBlocked,
		"prefix_empty_calls": staticDetailPrefixEmptyCalls,
		"rows_visited": staticDetailRowsVisited,
		"intersection_checks": staticDetailIntersectionChecks,
		"worst_query": worst,
	}


func ToDictionary() -> Dictionary:
	return {
		# Command
		"command_target_correction_usec": commandTargetCorrectionUsec,
		"command_build_paths_usec": commandBuildPathsUsec,
		"command_assignment_usec": commandAssignmentUsec,
		# Group Build
		"group_join_point_usec": groupJoinPointUsec,
		"group_shared_path_usec": groupSharedPathUsec,
		"group_unit_paths_usec": groupUnitPathsUsec,
		"group_join_segment_attempts": groupJoinSegmentAttempts,
		"group_join_segment_successes": groupJoinSegmentSuccesses,
		"group_join_waypoint_attempts": groupJoinWaypointAttempts,
		"group_join_waypoint_successes": groupJoinWaypointSuccesses,
		"group_join_fallback_calls": groupJoinFallbackCalls,
		"group_join_fallback_successes": groupJoinFallbackSuccesses,
		# Phase Time
		"start_anchor_connection_usec": startAnchorConnectionUsec,
		"target_anchor_connection_usec": targetAnchorConnectionUsec,
		"anchor_graph_usec": anchorGraphUsec,
		"fallback_grid_usec": fallbackGridUsec,
		# Static Query
		"segment_clear_query_usec": segmentClearQueryUsec,
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
