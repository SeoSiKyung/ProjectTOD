class_name GameDataLoader
extends RefCounted


static func LoadDefenseSpawnData() -> Dictionary:
	var path: String = "res://data/runtime/defense/DefenseSpawnTable.csv"
	var rows: Array[Dictionary] = CSVLoader.Load(path)

	var spawnDataByCycle: Dictionary = { }

	for row: Dictionary in rows:
		var cycle: int = row["cycle"].to_int()
		if cycle <= 0:
			push_error("DefenseSpawnTable cycle은 1 이상이어야 합니다.")
			continue

		var spawnTimeMs: int = row["spawnTimeMs"].to_int()
		if spawnTimeMs < 0:
			push_error("DefenseSpawnTable spawnTimeMs는 0 이상이어야 합니다.")
			continue

		var characterKey: int = row["characterKey"].to_int()
		if characterKey < 0:
			push_error("DefenseSpawnTable characterKey는 0 이상이어야 합니다.")
			continue

		var count: int = row["count"].to_int()
		if count <= 0:
			push_error("DefenseSpawnTable count는 1 이상이어야 합니다.")
			continue

		var spawnData: DefenseSpawnData = DefenseSpawnData.new(
			cycle,
			spawnTimeMs,
			characterKey,
			count,
		)

		if not spawnDataByCycle.has(cycle):
			spawnDataByCycle[cycle] = []
		spawnDataByCycle[cycle].append(spawnData)

	return spawnDataByCycle
