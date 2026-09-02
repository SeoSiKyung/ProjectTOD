class_name CSVLoader
extends RefCounted


static func Load(path: String) -> Array[Dictionary]:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("CSV 파일을 열 수 없습니다: " + path)
		return []

	if file.get_length() == 0:
		push_error("CSV 파일이 비어있습니다: " + path)
		return []

	var headers: PackedStringArray = file.get_csv_line()
	var rows: Array[Dictionary] = []
	if headers.size() == 0:
		return rows

	# UTF-8 BOM 대응
	headers[0] = headers[0].trim_prefix("\uFEFF")

	while file.get_position() < file.get_length():
		var values: PackedStringArray = file.get_csv_line()
		if values.size() == 0 or (values.size() == 1 and values[0].strip_edges().is_empty()):
			continue

		if values.size() != headers.size():
			push_error(
				"CSV 컬럼 수가 맞지 않습니다: " + path + " / expected: "
				+ str(headers.size()) + " / actual: " + str(values.size())
			)
			continue

		var row: Dictionary = { }
		for i: int in range(headers.size()):
			row[headers[i].strip_edges()] = values[i].strip_edges()

		rows.append(row)

	return rows
