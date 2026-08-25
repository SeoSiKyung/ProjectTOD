@tool
class_name NavigationBaker
extends Node

@export var navigation_mask: Texture2D
@export var cell_size: int = 8
@export var world_origin: Vector2 = Vector2.ZERO

@export_range(0.0, 1.0, 0.01)
var blocked_threshold: float = 0.5

@export_dir var output_directory: String = "res://maps"

@export_tool_button("Bake Navigation")
var bake_button: Callable = BakeNavigation


func BakeNavigation() -> void:
	if not Engine.is_editor_hint():
		return

	var output_path: String = _getOutputPath()

	if output_path.is_empty():
		push_error("현재 맵 씬의 파일 경로를 찾을 수 없습니다. 씬을 먼저 저장하세요.")
		return

	if navigation_mask == null:
		push_error("Navigation Mask가 지정되지 않았습니다.")
		return

	if cell_size <= 0:
		push_error("cell_size는 1 이상이어야 합니다.")
		return

	var image: Image = navigation_mask.get_image()

	if image == null or image.is_empty():
		push_error("Navigation Mask 이미지를 읽을 수 없습니다.")
		return

	var image_width: int = image.get_width()
	var image_height: int = image.get_height()

	if image_width <= 0 or image_height <= 0:
		push_error("Navigation Mask 크기가 잘못되었습니다.")
		return

	if image_width % cell_size != 0:
		push_error("Navigation Mask 가로 크기는 cell_size의 배수여야 합니다. 현재: %d" % image_width)
		return

	if image_height % cell_size != 0:
		push_error("Navigation Mask 세로 크기는 cell_size의 배수여야 합니다. 현재: %d" % image_height)
		return

	var grid_width: int = image_width / cell_size
	var grid_height: int = image_height / cell_size

	var blocked: PackedByteArray = PackedByteArray()
	blocked.resize(grid_width * grid_height)
	blocked.fill(0)

	for grid_y: int in range(grid_height):
		for grid_x: int in range(grid_width):
			var is_blocked: bool = false

			var start_x: int = grid_x * cell_size
			var start_y: int = grid_y * cell_size

			for pixel_y: int in range(start_y, start_y + cell_size):
				if is_blocked:
					break

				for pixel_x: int in range(start_x, start_x + cell_size):
					var color: Color = image.get_pixel(pixel_x, pixel_y)

					if _isBlockedPixel(color):
						is_blocked = true
						break

			var index: int = (grid_y * grid_width + grid_x)

			blocked[index] = 1 if is_blocked else 0

	var prefix_width: int = grid_width + 1
	var prefix_height: int = grid_height + 1

	var prefix_sum: PackedInt32Array = PackedInt32Array()
	prefix_sum.resize(prefix_width * prefix_height)
	prefix_sum.fill(0)

	for y: int in range(grid_height):
		var row_sum: int = 0

		for x: int in range(grid_width):
			var blocked_index: int = (y * grid_width + x)

			row_sum += blocked[blocked_index]

			var prefix_index: int = ((y + 1) * prefix_width + (x + 1))

			var previous_row_index: int = (y * prefix_width + (x + 1))

			prefix_sum[prefix_index] = (prefix_sum[previous_row_index] + row_sum)

	var data: NavigationData = NavigationData.new()

	data.cell_size = cell_size
	data.grid_size = Vector2i(grid_width, grid_height)
	data.world_origin = world_origin
	data.blocked = blocked
	data.prefix_sum = prefix_sum

	var directory: String = output_path.get_base_dir()

	var absolute_directory: String = (ProjectSettings.globalize_path(directory))

	var dir_error: Error = (DirAccess.make_dir_recursive_absolute(absolute_directory))

	if (dir_error != OK and dir_error != ERR_ALREADY_EXISTS):
		push_error("Navigation 저장 폴더 생성 실패: %s" % directory)
		return

	var save_error: Error = ResourceSaver.save(data, output_path)

	if save_error != OK:
		push_error("Navigation Data 저장 실패: %s" % error_string(save_error))
		return

	print(
		"Navigation Bake 완료 | Image: ",
		image_width,
		"x",
		image_height,
		" | Grid: ",
		grid_width,
		"x",
		grid_height,
		" | Cell: ",
		cell_size,
		" | ",
		output_path,
	)


func _isBlockedPixel(color: Color) -> bool:
	var brightness: float = (color.r + color.g + color.b) / 3.0

	return brightness < blocked_threshold


func _getOutputPath() -> String:
	if navigation_mask == null:
		return ""

	var texture_path: String = navigation_mask.resource_path

	if texture_path.is_empty():
		return ""

	var file_name: String = (texture_path.get_file().get_basename())

	return output_directory.path_join(file_name + "_navigation.res")
