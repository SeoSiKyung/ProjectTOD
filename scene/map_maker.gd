@tool
extends NavigationRegion2D


# ============================================================
# 설정
# ============================================================

# 흰색 = 이동 가능
# 검은색 = 이동 불가능
@export var navigation_mask: Texture2D


@export_range(0.0, 1.0, 0.01)
var white_threshold: float = 0.8


# 높을수록 PNG 외곽선의 점 개수가 줄어든다.
@export_range(0.1, 20.0, 0.1)
var simplify_epsilon: float = 3.0


# Navigation을 벽에서 얼마나 떨어뜨릴지 결정
@export_range(0.0, 100.0, 1.0)
var agent_radius: float = 16.0


# 자동 생성되는 맵 물리 충돌 Layer
# 1 = 맵
@export_range(1, 32, 1)
var map_collision_layer: int = 1


# Inspector에서 체크하면
# Navigation + Collision을 동시에 생성
@export var generate_map: bool = false:
	set(value):
		generate_map = false

		if value:
			_generate_map()


const GENERATED_COLLISION_NAME: String = "GeneratedMapCollision"


# ============================================================
# 메인 생성 함수
# ============================================================

func _generate_map() -> void:
	print("--------------------------------")
	print("맵 생성 시작")

	if navigation_mask == null:
		push_error("Navigation Mask PNG가 지정되지 않았습니다.")
		return

	var image: Image = navigation_mask.get_image()

	if image == null or image.is_empty():
		push_error("이미지를 읽을 수 없습니다.")
		return

	print(
		"이미지 크기: ",
		image.get_width(),
		" x ",
		image.get_height()
	)

	# --------------------------------------------------------
	# 1. 흰색 / 검은색 BitMap 생성
	# --------------------------------------------------------

	var white_bitmap: BitMap = BitMap.new()
	white_bitmap.create(image.get_size())

	var black_bitmap: BitMap = BitMap.new()
	black_bitmap.create(image.get_size())


	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):

			var color: Color = image.get_pixel(x, y)

			var brightness: float = (
				color.r +
				color.g +
				color.b
			) / 3.0

			var is_white: bool = brightness >= white_threshold

			white_bitmap.set_bit(
				x,
				y,
				is_white
			)

			black_bitmap.set_bit(
				x,
				y,
				not is_white
			)


	print("비트맵 생성 완료")


	# --------------------------------------------------------
	# 2. 흰색 영역 폴리곤 생성
	# --------------------------------------------------------

	var white_polygons: Array[PackedVector2Array] = \
		white_bitmap.opaque_to_polygons(
			Rect2i(
				Vector2i.ZERO,
				image.get_size()
			),
			simplify_epsilon
		)


	if white_polygons.is_empty():
		push_error("흰색 이동 영역을 찾지 못했습니다.")
		return


	print(
		"흰색 폴리곤 개수: ",
		white_polygons.size()
	)


	# --------------------------------------------------------
	# 3. 검은색 영역 폴리곤 생성
	# --------------------------------------------------------

	var black_polygons: Array[PackedVector2Array] = \
		black_bitmap.opaque_to_polygons(
			Rect2i(
				Vector2i.ZERO,
				image.get_size()
			),
			simplify_epsilon
		)


	print(
		"검은색 폴리곤 개수: ",
		black_polygons.size()
	)


	# --------------------------------------------------------
	# 4. 흰색 내부의 검은 장애물만 골라낸다.
	#
	# 이미지 외부 검은색은 장애물이 아니라
	# 흰색 영역의 바깥이므로 제외한다.
	# --------------------------------------------------------

	var internal_obstacles: Array[PackedVector2Array] = []


	for polygon: PackedVector2Array in black_polygons:

		if polygon.size() < 3:
			continue

		# 이미지 테두리에 닿은 검정은 외부 영역
		if _touches_image_border(
			polygon,
			image.get_size()
		):
			continue

		var center: Vector2 = \
			_get_polygon_center(polygon)

		# 흰색 영역 안에 들어있는 검정만 장애물
		if _is_inside_any_polygon(
			center,
			white_polygons
		):
			internal_obstacles.append(polygon)


	print(
		"내부 장애물 개수: ",
		internal_obstacles.size()
	)


	# --------------------------------------------------------
	# 5. Navigation 생성
	# --------------------------------------------------------

	_generate_navigation(
		white_polygons,
		internal_obstacles
	)


	# --------------------------------------------------------
	# 6. 물리 Collision 생성
	# --------------------------------------------------------

	_generate_collision(
		white_polygons,
		internal_obstacles
	)


	print("--------------------------------")
	print("맵 생성 완료")
	print("--------------------------------")


# ============================================================
# Navigation 생성
# ============================================================

func _generate_navigation(
	white_polygons: Array[PackedVector2Array],
	internal_obstacles: Array[PackedVector2Array]
) -> void:

	var source_geometry: NavigationMeshSourceGeometryData2D = \
		NavigationMeshSourceGeometryData2D.new()


	# 흰색 = 이동 가능
	for polygon: PackedVector2Array in white_polygons:

		if polygon.size() < 3:
			continue

		source_geometry.add_traversable_outline(
			polygon
		)


	# 내부 검정 = 이동 불가능
	for polygon: PackedVector2Array in internal_obstacles:

		if polygon.size() < 3:
			continue

		source_geometry.add_obstruction_outline(
			polygon
		)


	var nav_polygon: NavigationPolygon = \
		NavigationPolygon.new()


	nav_polygon.agent_radius = agent_radius
	nav_polygon.cell_size = 1.0


	NavigationServer2D.bake_from_source_geometry_data(
		nav_polygon,
		source_geometry
	)


	navigation_polygon = nav_polygon


	print(
		"Navigation 생성 완료 / Polygon: ",
		nav_polygon.get_polygon_count()
	)


# ============================================================
# Collision 생성
# ============================================================

func _generate_collision(
	white_polygons: Array[PackedVector2Array],
	internal_obstacles: Array[PackedVector2Array]
) -> void:

	# --------------------------------------------------------
	# 기존 자동 생성 Collision 삭제
	# --------------------------------------------------------

	var old_collision: Node = \
		get_node_or_null(GENERATED_COLLISION_NAME)


	if old_collision != null:
		remove_child(old_collision)
		old_collision.queue_free()


	# --------------------------------------------------------
	# StaticBody2D 생성
	# --------------------------------------------------------

	var collision_body: StaticBody2D = \
		StaticBody2D.new()


	collision_body.name = GENERATED_COLLISION_NAME

	# Godot Collision Layer는 비트값이므로
	# Layer 1 -> bit 0
	# Layer 2 -> bit 1
	collision_body.collision_layer = \
		1 << (map_collision_layer - 1)

	# StaticBody 자체가 다른 물체를 검사할 필요는 없음
	collision_body.collision_mask = 0


	add_child(collision_body)


	# 에디터에서 생성한 노드가
	# Scene 저장 시 같이 저장되도록 owner 설정
	if Engine.is_editor_hint():

		var scene_root: Node = \
			get_tree().edited_scene_root

		if scene_root != null:
			collision_body.owner = scene_root


	var collision_count: int = 0


	# --------------------------------------------------------
	# 흰색 이동 가능 영역의 외곽선을 벽으로 생성
	#
	# 이것 덕분에 Navigation 밖으로 유닛이
	# 밀려나가는 것을 실제 Physics가 막는다.
	# --------------------------------------------------------

	for polygon: PackedVector2Array in white_polygons:

		if polygon.size() < 3:
			continue

		_add_collision_outline(
			collision_body,
			polygon
		)

		collision_count += 1


	# --------------------------------------------------------
	# 흰색 내부의 검은 장애물 경계 생성
	#
	# 예:
	#   흰색 방 안의 검은 바위
	#   흰색 길 안의 검은 기둥
	# --------------------------------------------------------

	for polygon: PackedVector2Array in internal_obstacles:

		if polygon.size() < 3:
			continue

		_add_collision_outline(
			collision_body,
			polygon
		)

		collision_count += 1


	print(
		"Collision 생성 완료 / CollisionPolygon2D: ",
		collision_count
	)


# ============================================================
# CollisionPolygon2D 하나 생성
# ============================================================

func _add_collision_outline(
	parent: StaticBody2D,
	polygon: PackedVector2Array
) -> void:

	var collision_polygon: CollisionPolygon2D = \
		CollisionPolygon2D.new()


	# SOLIDS가 아니라 SEGMENTS.
	#
	# 즉 검은색 전체를 거대한 고체로 만드는 것이 아니라
	# 이동 가능 / 불가능 경계선만 벽으로 사용한다.
	collision_polygon.build_mode = \
		CollisionPolygon2D.BUILD_SEGMENTS


	collision_polygon.polygon = polygon


	parent.add_child(collision_polygon)


	if Engine.is_editor_hint():

		var scene_root: Node = \
			get_tree().edited_scene_root

		if scene_root != null:
			collision_polygon.owner = scene_root


# ============================================================
# 이미지 테두리에 닿았는지 검사
# ============================================================

func _touches_image_border(
	polygon: PackedVector2Array,
	image_size: Vector2i
) -> bool:

	for point: Vector2 in polygon:

		if point.x <= 1.0:
			return true

		if point.y <= 1.0:
			return true

		if point.x >= float(image_size.x - 1):
			return true

		if point.y >= float(image_size.y - 1):
			return true


	return false


# ============================================================
# 폴리곤 중심점 계산
# ============================================================

func _get_polygon_center(
	polygon: PackedVector2Array
) -> Vector2:

	if polygon.is_empty():
		return Vector2.ZERO


	var center: Vector2 = Vector2.ZERO


	for point: Vector2 in polygon:
		center += point


	center /= float(polygon.size())


	return center


# ============================================================
# 특정 점이 흰색 폴리곤 중 하나 안에 있는지 검사
# ============================================================

func _is_inside_any_polygon(
	point: Vector2,
	polygons: Array[PackedVector2Array]
) -> bool:

	for polygon: PackedVector2Array in polygons:

		if Geometry2D.is_point_in_polygon(
			point,
			polygon
		):
			return true


	return false
