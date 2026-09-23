class_name GameDataLoader
extends RefCounted

const GAME_DATA_PATH: String = "res://data/gameData"
const ICON_BASE_PATH: String = "res://picture"
const PREFAB_BASE_PATH: String = "res://prefabs"
const INVALID_INT: int = -100


#region Load

static func LoadCharacterData() -> Dictionary[int, CharacterData]:
	var tablePath: String = _GetTablePath("character", "CharacterTable")
	var rows: Array[Dictionary] = CSVLoader.Load(tablePath)

	var characterDataByKey: Dictionary[int, CharacterData] = { }

	for row: Dictionary in rows:
		var characterKeyText: String = row["characterKey"].strip_edges()
		if characterKeyText.is_empty():
			continue

		var characterKey: int = _ReadInt(row, "characterKey", 0, "CharacterTable")
		if characterKey == INVALID_INT:
			continue

		if characterDataByKey.has(characterKey):
			push_error("CharacterTable에 중복 characterKey가 있습니다. key: " + str(characterKey))
			continue

		var context: String = "key: " + str(characterKey)

		var characterName: String = row["characterName"]
		if characterName.is_empty():
			push_error("CharacterTable characterName이 비어있습니다. " + context)
			continue

		var characterType: CharacterData.CharacterType
		match row["characterType"].to_upper():
			"UNIT":
				characterType = CharacterData.CharacterType.UNIT

			"MONSTER":
				characterType = CharacterData.CharacterType.MONSTER

			_:
				push_error("CharacterTable characterType이 올바르지 않습니다. " + context)
				continue

		var relativePath: String = row["path"].strip_edges()
		if relativePath.is_empty():
			push_error("CharacterTable path가 비어있습니다. " + context)
			continue
		var iconPath: String = ICON_BASE_PATH.path_join(relativePath + ".png")
		var prefabPath: String = PREFAB_BASE_PATH.path_join(relativePath + ".tscn")

		var maxHp: int = _ReadInt(row, "maxHp", 1, "CharacterTable", context)
		if maxHp == INVALID_INT:
			continue

		var maxMp: int = _ReadInt(row, "maxMp", 0, "CharacterTable", context)
		if maxMp == INVALID_INT:
			continue

		var hpRegen: int = _ReadInt(row, "hpRegen", 0, "CharacterTable", context)
		if hpRegen == INVALID_INT:
			continue

		var mpRegen: int = _ReadInt(row, "mpRegen", 0, "CharacterTable", context)
		if mpRegen == INVALID_INT:
			continue

		var atk: int = _ReadInt(row, "atk", 0, "CharacterTable", context)
		if atk == INVALID_INT:
			continue

		var magicAtk: int = _ReadInt(row, "magicAtk", 0, "CharacterTable", context)
		if magicAtk == INVALID_INT:
			continue

		var def: int = _ReadInt(row, "def", 0, "CharacterTable", context)
		if def == INVALID_INT:
			continue

		var magicDef: int = _ReadInt(row, "magicDef", 0, "CharacterTable", context)
		if magicDef == INVALID_INT:
			continue

		var moveSpeed: int = _ReadInt(row, "moveSpeed", 0, "CharacterTable", context)
		if moveSpeed == INVALID_INT:
			continue

		var attackIntervalFrames: int = _ReadInt(
			row,
			"attackIntervalFrames",
			0,
			"CharacterTable",
			context,
		)
		if attackIntervalFrames == INVALID_INT:
			continue

		var atkRange: int = _ReadInt(row, "atkRange", 0, "CharacterTable", context)
		if atkRange == INVALID_INT:
			continue

		var acquisitionRange: int = _ReadInt(row, "acquisitionRange", 0, "CharacterTable", context)
		if acquisitionRange == INVALID_INT:
			continue

		var characterData: CharacterData = CharacterData.new(
			characterKey,
			characterName,
			characterType,
			iconPath,
			prefabPath,
			maxHp,
			maxMp,
			hpRegen,
			mpRegen,
			atk,
			magicAtk,
			def,
			magicDef,
			moveSpeed,
			attackIntervalFrames,
			atkRange,
			acquisitionRange,
		)

		characterDataByKey[characterKey] = characterData

	characterDataByKey.make_read_only()
	return characterDataByKey


static func LoadDefenseSpawnData() -> Dictionary[int, Array]:
	var tablePath: String = _GetTablePath("defense", "DefenseSpawnTable")
	var rows: Array[Dictionary] = CSVLoader.Load(tablePath)

	var spawnDataByCycle: Dictionary[int, Array] = { }

	for row: Dictionary in rows:
		var cycle: int = _ReadInt(row, "cycle", 1, "DefenseSpawnTable")
		if cycle == INVALID_INT:
			continue

		var cycleContext: String = "cycle: " + str(cycle)

		var spawnTimeMs: int = _ReadInt(row, "spawnTimeMs", 0, "DefenseSpawnTable", cycleContext)
		if spawnTimeMs == INVALID_INT:
			continue

		var spawnPointKey: int = _ReadInt(
			row,
			"spawnPointKey",
			0,
			"DefenseSpawnTable",
			cycleContext,
		)
		if spawnPointKey == INVALID_INT:
			continue

		var characterKey: int = _ReadInt(row, "characterKey", 0, "DefenseSpawnTable", cycleContext)
		if characterKey == INVALID_INT:
			continue

		var count: int = _ReadInt(
			row,
			"count",
			1,
			"DefenseSpawnTable",
			"cycle: %d, key: %d" % [cycle, characterKey],
		)
		if count == INVALID_INT:
			continue

		var spawnData: DefenseSpawnData = DefenseSpawnData.new(
			spawnTimeMs,
			spawnPointKey,
			characterKey,
			count,
		)

		if not spawnDataByCycle.has(cycle):
			var spawnDataList: Array[DefenseSpawnData] = []
			spawnDataByCycle[cycle] = spawnDataList

		var spawnDataList: Array[DefenseSpawnData] = spawnDataByCycle[cycle]
		spawnDataList.append(spawnData)

	for cycle: int in spawnDataByCycle:
		var spawnDataList: Array[DefenseSpawnData] = spawnDataByCycle[cycle]
		spawnDataList.sort_custom(_CompareDefenseSpawnTime)
		spawnDataList.make_read_only()

	spawnDataByCycle.make_read_only()

	return spawnDataByCycle

#endregion


#region Validate

static func ValidateDefenseSpawnDataReferences(
	spawnDataByCycle: Dictionary[int, Array],
	characterDataByKey: Dictionary[int, CharacterData],
) -> bool:
	var isValid: bool = true

	for cycle: int in spawnDataByCycle:
		var spawnDataList: Array[DefenseSpawnData] = spawnDataByCycle[cycle]

		for spawnData: DefenseSpawnData in spawnDataList:
			var characterData: CharacterData = characterDataByKey.get(spawnData.characterKey)
			if characterData == null:
				push_error(
					"DefenseSpawnTable에 존재하지 않는 characterKey가 있습니다. cycle: "
					+ str(cycle) + ", key: " + str(spawnData.characterKey)
				)
				isValid = false
				continue

			if characterData.characterType != CharacterData.CharacterType.MONSTER:
				push_error(
					"DefenseSpawnTable에는 MONSTER 타입만 등록할 수 있습니다. cycle: "
					+ str(cycle) + ", key: " + str(spawnData.characterKey)
				)
				isValid = false

	return isValid

#endregion


#region Utility

static func _ReadInt(
	row: Dictionary,
	fieldName: String,
	minValue: int,
	tableName: String,
	context: String = "",
) -> int:
	var text: String = row[fieldName]

	if not text.is_valid_int():
		var message: String = "%s %s는 정수여야 합니다." % [tableName, fieldName]
		if not context.is_empty():
			message += " " + context

		push_error(message)
		return INVALID_INT

	var value: int = text.to_int()
	if value < minValue:
		var message: String = "%s %s는 %d 이상이어야 합니다." % [tableName, fieldName, minValue]
		if not context.is_empty():
			message += " " + context

		push_error(message)
		return INVALID_INT

	return value


static func _CompareDefenseSpawnTime(a: DefenseSpawnData, b: DefenseSpawnData) -> bool:
	return a.spawnTimeMs < b.spawnTimeMs


static func _GetTablePath(category: String, tableName: String) -> String:
	return GAME_DATA_PATH.path_join(category).path_join(tableName + ".csv")

#endregion
