@tool
extends NavigationRegion2D

# Inspector에 PNG를 드래그
@export var navigation_mask: Texture2D

# RGB가 이 값 이상이면 "흰색 = 이동 가능"으로 판단
@export_range(0.0, 1.0, 0.01)
var white_threshold: float = 0.8

# 높을수록 폴리곤이 단순해짐
@export_range(0.1, 20.0, 0.1)
var simplify_epsilon: float = 3.0

# 캐릭터 반지름.
# 벽 가장자리에서 이만큼 안쪽으로 Navigation 영역이 줄어듦
@export_range(0.0, 100.0, 1.0)
var agent_radius: float = 16.0


# Inspector에서 이 값을 체크하면 생성
@export var generate_navigation: bool = false:
	set(value):
		if value:
			call_deferred("_generate_navigation")
		generate_navigation = false


func _generate_navigation() -> void:
	if navigation_mask == null:
		push_error("Navigation Mask PNG를 지정해주세요.")
		return

	var image: Image = navigation_mask.get_image()

	if image == null:
		push_error("이미지를 읽을 수 없습니다.")
		return

	# --------------------------
	# 1. 흰색 픽셀 -> true
	#    검은색 픽셀 -> false
	# --------------------------

	var bitmap := BitMap.new()
	bitmap.create(image.get_size())

	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)

			var brightness := (
				color.r +
				color.g +
				color.b
			) / 3.0

			bitmap.set_bit(
				x,
				y,
				brightness >= white_threshold
			)

	# --------------------------
	# 2. 비트맵에서 폴리곤 추출
	# --------------------------

	var polygons: Array[PackedVector2Array] = bitmap.opaque_to_polygons(
		Rect2i(Vector2i.ZERO, bitmap.get_size()),
		simplify_epsilon
	)

	if polygons.is_empty():
		push_error("이동 가능한 흰색 영역을 찾지 못했습니다.")
		return

	# --------------------------
	# 3. Navigation 데이터 생성
	# --------------------------

	var source_geometry := NavigationMeshSourceGeometryData2D.new()

	for i in range(polygons.size()):
		var polygon := polygons[i]

		if polygon.size() < 3:
			continue

		# 다른 폴리곤 안에 몇 번 들어있는지 확인한다.
		# 0 = 바깥 이동영역
		# 1 = 구멍/장애물
		# 2 = 장애물 안의 이동영역
		# ...
		var depth := _get_polygon_depth(i, polygons)

		if depth % 2 == 0:
			source_geometry.add_traversable_outline(polygon)
		else:
			source_geometry.add_obstruction_outline(polygon)

	# --------------------------
	# 4. NavigationPolygon Bake
	# --------------------------

	var nav_polygon := NavigationPolygon.new()

	nav_polygon.agent_radius = agent_radius
	nav_polygon.cell_size = 1.0

	NavigationServer2D.bake_from_source_geometry_data(
		nav_polygon,
		source_geometry
	)

	navigation_polygon = nav_polygon

	print(
		"Navigation 생성 완료 / Polygon 개수: ",
		polygons.size()
	)


func _get_polygon_depth(
	index: int,
	polygons: Array[PackedVector2Array]
) -> int:

	var polygon := polygons[index]

	if polygon.is_empty():
		return 0

	# 경계점 자체를 쓰면 판정이 애매할 수 있어서
	# 첫 몇 점의 평균을 샘플로 사용
	var sample := Vector2.ZERO
	var count := mini(3, polygon.size())

	for i in range(count):
		sample += polygon[i]

	sample /= float(count)

	var depth := 0

	for i in range(polygons.size()):
		if i == index:
			continue

		if Geometry2D.is_point_in_polygon(
			sample,
			polygons[i]
		):
			depth += 1

	return depth
