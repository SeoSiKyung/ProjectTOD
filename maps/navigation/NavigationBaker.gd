@tool
class_name NavigationBaker
extends Node

@export var navigationMask: Texture2D
@export var cellSize: int = 8
@export var worldOrigin: Vector2 = Vector2.ZERO

@export_range(0.0, 1.0, 0.01)
var blockedThreshold: float = 0.5

@export_dir var outputDirectory: String = "res://maps"

@export_tool_button("Bake Navigation")
var bakeButton: Callable = BakeNavigation


func BakeNavigation() -> void:
	if not Engine.is_editor_hint():
		return

	var outputPath: String = _GetOutputPath()

	if outputPath.is_empty():
		push_error("현재 맵 씬의 파일 경로를 찾을 수 없습니다. 씬을 먼저 저장하세요.")
		return

	if navigationMask == null:
		push_error("Navigation Mask가 지정되지 않았습니다.")
		return

	if cellSize <= 0:
		push_error("cell_size는 1 이상이어야 합니다.")
		return

	var image: Image = navigationMask.get_image()

	if image == null or image.is_empty():
		push_error("Navigation Mask 이미지를 읽을 수 없습니다.")
		return

	var imageWidth: int = image.get_width()
	var imageHeight: int = image.get_height()

	if imageWidth <= 0 or imageHeight <= 0:
		push_error("Navigation Mask 크기가 잘못되었습니다.")
		return

	if imageWidth % cellSize != 0:
		push_error("Navigation Mask 가로 크기는 cell_size의 배수여야 합니다. 현재: %d" % imageWidth)
		return

	if imageHeight % cellSize != 0:
		push_error("Navigation Mask 세로 크기는 cell_size의 배수여야 합니다. 현재: %d" % imageHeight)
		return

	var gridWidth: int = imageWidth / cellSize
	var gridHeight: int = imageHeight / cellSize

	var blocked: PackedByteArray = PackedByteArray()
	blocked.resize(gridWidth * gridHeight)
	blocked.fill(0)

	for gridY: int in range(gridHeight):
		for gridX: int in range(gridWidth):
			var isBlocked: bool = false

			var startX: int = gridX * cellSize
			var startY: int = gridY * cellSize

			for pixelY: int in range(startY, startY + cellSize):
				if isBlocked:
					break

				for pixelX: int in range(startX, startX + cellSize):
					var color: Color = image.get_pixel(pixelX, pixelY)

					if _IsBlockedPixel(color):
						isBlocked = true
						break

			var index: int = (gridY * gridWidth + gridX)

			blocked[index] = 1 if isBlocked else 0

	var prefixWidth: int = gridWidth + 1
	var prefixHeight: int = gridHeight + 1

	var prefixSum: PackedInt32Array = PackedInt32Array()
	prefixSum.resize(prefixWidth * prefixHeight)
	prefixSum.fill(0)

	for y: int in range(gridHeight):
		var rowSum: int = 0

		for x: int in range(gridWidth):
			var blockedIndex: int = (y * gridWidth + x)

			rowSum += blocked[blockedIndex]

			var prefixIndex: int = ((y + 1) * prefixWidth + (x + 1))

			var previousRowIndex: int = (y * prefixWidth + (x + 1))

			prefixSum[prefixIndex] = (prefixSum[previousRowIndex] + rowSum)

	var data: NavigationData = NavigationData.new()

	data.cellSize = cellSize
	data.gridSize = Vector2i(gridWidth, gridHeight)
	data.worldOrigin = worldOrigin
	data.blocked = blocked
	data.prefixSum = prefixSum

	var directory: String = outputPath.get_base_dir()

	var absoluteDirectory: String = (ProjectSettings.globalize_path(directory))

	var dirError: Error = (DirAccess.make_dir_recursive_absolute(absoluteDirectory))

	if (dirError != OK and dirError != ERR_ALREADY_EXISTS):
		push_error("Navigation 저장 폴더 생성 실패: %s" % directory)
		return

	var saveError: Error = ResourceSaver.save(data, outputPath)

	if saveError != OK:
		push_error("Navigation Data 저장 실패: %s" % error_string(saveError))
		return

	print(
		"Navigation Bake 완료 | Image: ",
		imageWidth,
		"x",
		imageHeight,
		" | Grid: ",
		gridWidth,
		"x",
		gridHeight,
		" | Cell: ",
		cellSize,
		" | ",
		outputPath,
	)


func _IsBlockedPixel(color: Color) -> bool:
	var brightness: float = (color.r + color.g + color.b) / 3.0

	return brightness < blockedThreshold


func _GetOutputPath() -> String:
	if navigationMask == null:
		return ""

	var texture_path: String = navigationMask.resource_path

	if texture_path.is_empty():
		return ""

	var file_name: String = (texture_path.get_file().get_basename())

	return outputDirectory.path_join(file_name + "_navigation.res")
