extends Node2D


# =========================================================
# 현재 선택된 유닛
# 지금은 5명을 Inspector에서 직접 넣으면 됨
# =========================================================

@export var units: Array[RTSUnit]


# =========================================================
# 이동 명령 이펙트
# =========================================================

@export var move_click_effect_scene: PackedScene

@export var drag_update_distance: float = 10.0
@export var effect_interval: float = 0.5


# =========================================================
# 랜덤 최종 목적지 설정
# =========================================================

# 클릭 지점에서 이 반경 안에
# 랜덤 최종 목적지를 생성
@export var arrival_radius: float = 65.0

# 랜덤 목적지끼리 최소 간격
@export var arrival_min_distance: float = 38.0

# 랜덤 위치 생성 재시도 횟수
@export var arrival_max_attempts: int = 50

# 중앙 목적지에서 이 거리까지 접근하면
# 실제 랜덤 최종 목적지를 배정받기 시작
@export var arrival_trigger_distance: float = 100.0

# Navigation으로 보정했을 때 원래 후보 위치에서
# 너무 멀리 떨어졌다면 그 후보는 버림
@export var projection_tolerance: float = 30.0


# =========================================================
# 입력 상태
# =========================================================

var right_mouse_pressed: bool = false
var effect_timer: float = 0.0
var last_mouse_position: Vector2 = Vector2.ZERO


# =========================================================
# 현재 이동 명령
# =========================================================

var has_move_command: bool = false

# 플레이어가 실제로 찍은 중앙 목적지
var command_center: Vector2 = Vector2.ZERO


# =========================================================
# 랜덤 목적지
# =========================================================

# 클릭 위치 기준의 랜덤 오프셋.
#
# 우클릭을 처음 눌렀을 때 한 번 생성하고
# 드래그 중에는 형태를 유지한다.
var arrival_offsets: Array[Vector2] = []

# 최종 월드 좌표
var arrival_positions: Array[Vector2] = []

# 이미 다른 유닛이 가져간 목적지 index
var reserved_slots: Dictionary = {}


# =========================================================
# Random
# =========================================================

var rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()


# =========================================================
# 입력
# =========================================================

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:

		if event.button_index == MOUSE_BUTTON_RIGHT:

			if event.pressed:
				_start_move_command()

			else:
				right_mouse_pressed = false
				effect_timer = 0.0


# =========================================================
# 업데이트
# =========================================================

func _process(delta: float) -> void:

	# -----------------------------------------------------
	# 우클릭 드래그
	# -----------------------------------------------------

	if right_mouse_pressed:

		var mouse_position: Vector2 = get_global_mouse_position()

		effect_timer += delta

		if effect_timer >= effect_interval:
			_show_click_effect_move(mouse_position)
			effect_timer = 0.0


		if mouse_position.distance_to(
			last_mouse_position
		) >= drag_update_distance:

			last_mouse_position = mouse_position

			_update_command_center(mouse_position)


	# -----------------------------------------------------
	# 우클릭을 놓은 다음
	# 도착한 유닛부터 하나씩 목적지 배정
	# -----------------------------------------------------

	if has_move_command and not right_mouse_pressed:
		_assign_next_arriving_unit()


# =========================================================
# 새 이동 명령 시작
# =========================================================

func _start_move_command() -> void:

	right_mouse_pressed = true
	effect_timer = 0.0


	var mouse_position: Vector2 = get_global_mouse_position()

	last_mouse_position = mouse_position


	# -----------------------------------------------------
	# 새 이동 명령이므로 기존 예약 초기화
	# -----------------------------------------------------

	reserved_slots.clear()


	# -----------------------------------------------------
	# 이번 명령에서 사용할 랜덤 배치 생성
	#
	# 드래그한다고 다시 랜덤하게 바뀌지 않음.
	# -----------------------------------------------------

	arrival_offsets = _make_random_offsets(
		_get_valid_units().size()
	)


	_update_command_center(mouse_position)


	_show_click_effect_move(mouse_position)


# =========================================================
# 이동 명령 중심 업데이트
# =========================================================

func _update_command_center(
	target_position: Vector2
) -> void:

	command_center = _get_valid_navigation_position(
		target_position
	)

	has_move_command = true


	# -----------------------------------------------------
	# 랜덤 도착점도 새로운 중심 위치를 따라 이동
	# -----------------------------------------------------

	_update_arrival_positions()


	# -----------------------------------------------------
	# 아직 슬롯을 배정하지 않음.
	#
	# 모든 유닛은 우선 중앙 목적지를 향해 이동.
	# -----------------------------------------------------

	for unit: RTSUnit in units:

		if unit == null:
			continue

		unit.move_to_command_center(
			command_center
		)


# =========================================================
# 랜덤 오프셋 → 실제 월드 목적지로 변환
# =========================================================

func _update_arrival_positions() -> void:

	arrival_positions.clear()


	for offset: Vector2 in arrival_offsets:

		var raw_position: Vector2 = (
			command_center + offset
		)


		var valid_position: Vector2 = (
			_get_valid_navigation_position(
				raw_position
			)
		)


		arrival_positions.append(
			valid_position
		)


# =========================================================
# 목적지에 가장 먼저 접근한 유닛 하나를 찾음
# =========================================================

func _assign_next_arriving_unit() -> void:

	var candidate_unit: RTSUnit = null

	var closest_distance: float = INF


	# -----------------------------------------------------
	# 목적지 범위 안에 들어온
	# 아직 슬롯 없는 유닛 중
	# 가장 중앙에 가까운 유닛을 고름.
	#
	# 즉 가장 먼저 도착한 놈이 우선권.
	# -----------------------------------------------------

	for unit: RTSUnit in units:

		if unit == null:
			continue


		if unit.has_arrival_slot:
			continue


		var distance: float = (
			unit.global_position.distance_to(
				command_center
			)
		)


		if distance > arrival_trigger_distance:
			continue


		if distance < closest_distance:

			closest_distance = distance
			candidate_unit = unit


	# 아직 아무도 도착하지 않음
	if candidate_unit == null:
		return


	# -----------------------------------------------------
	# 현재 선택된 모든 유닛의 중심점 계산
	# -----------------------------------------------------

	var group_center: Vector2 = (
		_get_selected_units_center()
	)


	# -----------------------------------------------------
	# 남은 랜덤 목적지 중
	# 그룹 중심에서 가장 먼 지점 선택
	# -----------------------------------------------------

	var slot_index: int = (
		_find_farthest_available_slot(
			group_center
		)
	)


	if slot_index < 0:
		return


	# -----------------------------------------------------
	# 해당 슬롯 예약
	# -----------------------------------------------------

	reserved_slots[slot_index] = (
		candidate_unit.get_instance_id()
	)


	candidate_unit.set_arrival_slot(
		arrival_positions[slot_index]
	)


# =========================================================
# 현재 선택된 모든 유닛의 중심점
# =========================================================

func _get_selected_units_center() -> Vector2:

	var valid_units: Array[RTSUnit] = (
		_get_valid_units()
	)


	if valid_units.is_empty():
		return command_center


	var center: Vector2 = Vector2.ZERO


	for unit: RTSUnit in valid_units:

		center += unit.global_position


	center /= float(valid_units.size())


	return center


# =========================================================
# 현재 그룹 중심에서 가장 먼 빈 목적지 찾기
# =========================================================

func _find_farthest_available_slot(
	group_center: Vector2
) -> int:

	var best_index: int = -1

	var best_distance: float = -1.0


	for i: int in range(
		arrival_positions.size()
	):

		# 이미 누가 가져간 목적지
		if reserved_slots.has(i):
			continue


		var distance: float = (
			group_center.distance_squared_to(
				arrival_positions[i]
			)
		)


		if distance > best_distance:

			best_distance = distance
			best_index = i


	return best_index


# =========================================================
# 랜덤 목적지 오프셋 생성
# =========================================================

func _make_random_offsets(
	count: int
) -> Array[Vector2]:

	var offsets: Array[Vector2] = []


	if count <= 0:
		return offsets


	for index: int in range(count):

		var found_position: bool = false


		for attempt: int in range(
			arrival_max_attempts
		):

			# 랜덤 방향
			var angle: float = (
				rng.randf_range(
					0.0,
					TAU
				)
			)


			# 원 안에 균등하게 퍼지도록 sqrt 사용
			var distance: float = (
				sqrt(rng.randf())
				* arrival_radius
			)


			var candidate: Vector2 = (
				Vector2.RIGHT.rotated(angle)
				* distance
			)


			if _is_offset_valid(
				candidate,
				offsets
			):

				offsets.append(candidate)

				found_position = true

				break


		# -------------------------------------------------
		# 랜덤 생성 실패 시
		# 원 둘레에 강제로 하나 배치
		# -------------------------------------------------

		if not found_position:

			var angle: float = (
				TAU
				* float(index)
				/ float(maxi(count, 1))
			)


			offsets.append(
				Vector2.RIGHT.rotated(angle)
				* arrival_radius
			)


	return offsets


# =========================================================
# 랜덤 목적지끼리 너무 붙어 있지 않은지 검사
# =========================================================

func _is_offset_valid(
	candidate: Vector2,
	existing_offsets: Array[Vector2]
) -> bool:

	for offset: Vector2 in existing_offsets:

		if candidate.distance_to(
			offset
		) < arrival_min_distance:

			return false


	return true


# =========================================================
# null이 아닌 유닛 배열
# =========================================================

func _get_valid_units() -> Array[RTSUnit]:

	var valid_units: Array[RTSUnit] = []


	for unit: RTSUnit in units:

		if unit != null:
			valid_units.append(unit)


	return valid_units


# =========================================================
# Navigation 위의 가장 가까운 위치
# =========================================================

func _get_valid_navigation_position(
	position: Vector2
) -> Vector2:

	var navigation_map: RID = (
		get_world_2d().navigation_map
	)


	return NavigationServer2D.map_get_closest_point(
		navigation_map,
		position
	)


# =========================================================
# 이동 명령 이펙트
# =========================================================

func _show_click_effect_move(
	target_position: Vector2
) -> void:

	if move_click_effect_scene == null:
		return


	var effect: Node2D = (
		move_click_effect_scene.instantiate()
	)


	get_tree().current_scene.add_child(
		effect
	)


	effect.global_position = target_position
