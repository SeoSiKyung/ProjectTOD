extends CharacterBody2D
class_name RTSUnit


# =========================================================
# 이동
# =========================================================

@export var move_speed: float = 200.0


# =========================================================
# Navigation
# =========================================================

@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D


# =========================================================
# 이동 상태
# =========================================================

var is_moving: bool = false

var command_center: Vector2 = Vector2.ZERO
var current_goal: Vector2 = Vector2.ZERO

var has_arrival_slot: bool = false


# =========================================================
# 초기화
# =========================================================

func _ready() -> void:

	# -----------------------------------------------------
	# 모든 유닛의 Avoidance를 코드에서 자동 활성화
	# -----------------------------------------------------

	navigation_agent.avoidance_enabled = true


	# -----------------------------------------------------
	# 공통 Avoidance 설정
	# -----------------------------------------------------

	navigation_agent.radius = 16.0

	navigation_agent.neighbor_distance = 100.0

	navigation_agent.max_neighbors = 10

	navigation_agent.time_horizon_agents = 0.7

	navigation_agent.max_speed = move_speed


	# -----------------------------------------------------
	# 경로 관련 설정
	# -----------------------------------------------------

	navigation_agent.path_desired_distance = 4.0

	navigation_agent.target_desired_distance = 4.0


	# -----------------------------------------------------
	# Avoidance 계산 결과를 받을 Signal
	# -----------------------------------------------------

	navigation_agent.velocity_computed.connect(
		_on_velocity_computed
	)


# =========================================================
# 중앙 목적지로 이동
# =========================================================

func move_to_command_center(
	target_position: Vector2
) -> void:

	command_center = target_position

	current_goal = target_position


	has_arrival_slot = false

	is_moving = true


	navigation_agent.target_position = (
		current_goal
	)


# =========================================================
# 최종 랜덤 목적지 배정
# =========================================================

func set_arrival_slot(
	slot_position: Vector2
) -> void:

	current_goal = slot_position

	has_arrival_slot = true

	is_moving = true


	navigation_agent.target_position = (
		current_goal
	)


# =========================================================
# 이동
# =========================================================

func _physics_process(
	_delta: float
) -> void:

	if not is_moving:

		velocity = Vector2.ZERO

		navigation_agent.velocity = (
			Vector2.ZERO
		)

		return


	# -----------------------------------------------------
	# 목적지 도착
	# -----------------------------------------------------

	if navigation_agent.is_navigation_finished():

		_stop_move()

		return


	# -----------------------------------------------------
	# Navigation 경로의 다음 위치
	# -----------------------------------------------------

	var next_position: Vector2 = (
		navigation_agent.get_next_path_position()
	)


	var direction: Vector2 = (
		global_position.direction_to(
			next_position
		)
	)


	if direction.length_squared() <= 0.001:

		navigation_agent.velocity = (
			Vector2.ZERO
		)

		return


	# -----------------------------------------------------
	# 내가 원하는 속도
	#
	# 여기서는 아직 CharacterBody를 이동시키지 않는다.
	# Avoidance에게 먼저 전달한다.
	# -----------------------------------------------------

	var desired_velocity: Vector2 = (
		direction * move_speed
	)


	navigation_agent.velocity = (
		desired_velocity
	)


# =========================================================
# Avoidance가 계산한 안전한 속도
# =========================================================

func _on_velocity_computed(
	safe_velocity: Vector2
) -> void:

	if not is_moving:
		return


	velocity = safe_velocity

	move_and_slide()


# =========================================================
# 정지
# =========================================================

func _stop_move() -> void:

	is_moving = false

	velocity = Vector2.ZERO

	navigation_agent.velocity = Vector2.ZERO
