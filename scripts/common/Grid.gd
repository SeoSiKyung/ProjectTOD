class_name Grid


static func IsCellInGrid(cell: Vector2i, gridWidth: int, gridHeight: int) -> bool:
	return (0 <= cell.x and cell.x < gridWidth) and (0 <= cell.y and cell.y < gridHeight)


static func CellToIndex(cell: Vector2i, gridWidth: int) -> int:
	return cell.y * gridWidth + cell.x


static func IndexToCell(index: int, gridWidth: int) -> Vector2i:
	return Vector2i(index % gridWidth, int(index / gridWidth))
