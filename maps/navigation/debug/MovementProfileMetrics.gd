class_name MovementProfileMetrics
extends RefCounted

# MovementSimulator의 실제 이동 틱을 계측하기 위한 런타임 프로파일 데이터.
#
# 일반 게임 실행에서는 metrics가 null이므로 계측하지 않는다.
# NavigationBenchmark의 Movement 모드에서만 설정한다.

var simulationTickCount: int = 0

var captureTickUsec: int = 0
var collisionResolveUsec: int = 0
var commitTickUsec: int = 0
var arrivalResolveUsec: int = 0

var collisionCandidateQueries: int = 0
var dynamicBlockedCandidates: int = 0
var alternateCandidateQueries: int = 0
var stalledAgentTicks: int = 0

var settledAgentCount: int = 0


func ToDictionary() -> Dictionary:
	return {
		"simulation_tick_count": simulationTickCount,
		"capture_tick_usec": captureTickUsec,
		"collision_resolve_usec": collisionResolveUsec,
		"commit_tick_usec": commitTickUsec,
		"arrival_resolve_usec": arrivalResolveUsec,
		"collision_candidate_queries": collisionCandidateQueries,
		"dynamic_blocked_candidates": dynamicBlockedCandidates,
		"alternate_candidate_queries": alternateCandidateQueries,
		"stalled_agent_ticks": stalledAgentTicks,
		"settled_agent_count": settledAgentCount,
	}
