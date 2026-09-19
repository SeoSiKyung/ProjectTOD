extends RefCounted

const DIRECTORY: String = "user://benchmark_screenshots"


static func BuildDirectory(modeName: String) -> String:
	var dateTime: Dictionary = Time.get_datetime_dict_from_system()
	var timestamp: String = "%04d%02d%02d_%02d%02d%02d" % [
		int(dateTime["year"]),
		int(dateTime["month"]),
		int(dateTime["day"]),
		int(dateTime["hour"]),
		int(dateTime["minute"]),
		int(dateTime["second"]),
	]
	return "%s/%s_%s" % [DIRECTORY, timestamp, modeName]


static func SanitizeFileName(fileName: String) -> String:
	var sanitized: String = fileName
	for invalidCharacter: String in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]:
		sanitized = sanitized.replace(invalidCharacter, "_")
	return sanitized


static func SavePanel(panel: Control, path: String) -> Error:
	var viewport: Viewport = panel.get_viewport()
	var viewportImage: Image = viewport.get_texture().get_image()
	var viewportSize: Vector2 = viewport.get_visible_rect().size
	var imageSize: Vector2i = viewportImage.get_size()

	if viewportSize.x <= 0.0 or viewportSize.y <= 0.0:
		return ERR_INVALID_DATA

	var scale: Vector2 = Vector2(
		float(imageSize.x) / viewportSize.x,
		float(imageSize.y) / viewportSize.y,
	)
	var panelRect: Rect2 = panel.get_global_rect()
	var cropPosition: Vector2i = Vector2i(
		floori(panelRect.position.x * scale.x),
		floori(panelRect.position.y * scale.y),
	)
	var cropEnd: Vector2i = Vector2i(
		ceili(panelRect.end.x * scale.x),
		ceili(panelRect.end.y * scale.y),
	)
	var cropRect: Rect2i = Rect2i(cropPosition, cropEnd - cropPosition)
	cropRect = cropRect.intersection(Rect2i(Vector2i.ZERO, imageSize))

	if cropRect.size.x <= 0 or cropRect.size.y <= 0:
		return ERR_INVALID_DATA

	return viewportImage.get_region(cropRect).save_png(path)
