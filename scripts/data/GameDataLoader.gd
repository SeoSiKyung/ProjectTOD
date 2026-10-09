class_name GameDataLoader
extends RefCounted

const GAME_DATA_PATH: String = "res://data/gameData"
const ASSET_BASE_PATH: String = "res://assets"
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

		var characterTypeName: String = row["characterType"].strip_edges()
		var characterType: CharacterData.CharacterType
		match characterTypeName:
			"UNIT":
				characterType = CharacterData.CharacterType.UNIT
			"MACHINE":
				characterType = CharacterData.CharacterType.MACHINE
			"TRAP":
				characterType = CharacterData.CharacterType.TRAP
			"MONSTER":
				characterType = CharacterData.CharacterType.MONSTER
			"COMMAND_POST":
				characterType = CharacterData.CharacterType.COMMAND_POST
			_:
				push_error("CharacterTable characterType이 올바르지 않습니다. " + context)
				continue

		var targetPolicyId: String = row["targetPolicyId"].strip_edges()
		var movementPolicyId: String = row["movementPolicyId"].strip_edges()
		if characterType == CharacterData.CharacterType.MONSTER:
			if targetPolicyId.is_empty() or movementPolicyId.is_empty():
				push_error("GameDataLoader: MONSTER의 AI 정책이 누락되었습니다. " + context)
				continue
		else:
			if not targetPolicyId.is_empty() or not movementPolicyId.is_empty():
				push_error("GameDataLoader: MONSTER가 아닌 캐릭터에 AI 정책이 설정되었습니다. " + context)
				continue

		var resourceName: String = "Unit_" + str(characterKey)

		var iconPath: String = (
			ASSET_BASE_PATH
			.path_join("picture")
			.path_join("units")
			.path_join(characterTypeName)
			.path_join(resourceName + ".png")
		)
		var parchmentIconPath: String = (
			ASSET_BASE_PATH
			.path_join("picture")
			.path_join("ui")
			.path_join("parchment")
			.path_join(characterTypeName)
			.path_join(resourceName + ".png")
		)

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

		var stats: CharacterStats = CharacterStats.new(
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

		var characterData: CharacterData = CharacterData.new(
			characterKey,
			characterName,
			characterType,
			iconPath,
			parchmentIconPath,
			stats,
			targetPolicyId,
			movementPolicyId,
		)
		characterDataByKey[characterKey] = characterData

	characterDataByKey.make_read_only()
	return characterDataByKey


static func LoadMercenaryData() -> Dictionary[int, MercenaryData]:
	var tablePath: String = _GetTablePath("mercenary", "MercenaryTable")
	var rows: Array[Dictionary] = CSVLoader.Load(tablePath)

	var mercenaryDataByKey: Dictionary[int, MercenaryData] = { }
	var usedCharacterKeys: Dictionary[int, bool] = { }

	for row: Dictionary in rows:
		var mercenaryKey: int = _ReadInt(row, "mercenaryKey", 0, "MercenaryTable")
		if mercenaryKey == INVALID_INT:
			continue

		if mercenaryDataByKey.has(mercenaryKey):
			push_error("MercenaryTable에 중복 mercenaryKey가 있습니다. key: " + str(mercenaryKey))
			continue

		var context: String = "key: " + str(mercenaryKey)

		var characterKey: int = _ReadInt(row, "characterKey", 10000, "MercenaryTable", context)
		if characterKey == INVALID_INT:
			continue

		if usedCharacterKeys.has(characterKey):
			push_error(
				"MercenaryTable에 중복 characterKey가 있습니다. " + context
				+ ", characterKey: " + str(characterKey)
			)
			continue

		var name: String = row["name"].strip_edges()
		if name.is_empty():
			push_error("MercenaryTable name이 비어있습니다. " + context)
			continue

		var isHeroValue: Variant = _ReadBool(row, "isHero", "MercenaryTable", context)
		if isHeroValue == null:
			continue

		var isHero: bool = isHeroValue

		var resourceName: String = "MERCENARY_" + str(mercenaryKey)
		var iconPath: String = (
			ASSET_BASE_PATH
			.path_join("picture")
			.path_join("mercenaries")
			.path_join(resourceName + ".png")
		)
		var parchmentIconPath: String = (
			ASSET_BASE_PATH
			.path_join("picture")
			.path_join("ui")
			.path_join("parchment")
			.path_join("MERCENARY")
			.path_join(resourceName + ".png")
		)

		var mercenaryData: MercenaryData = MercenaryData.new(
			mercenaryKey,
			characterKey,
			name,
			isHero,
			iconPath,
			parchmentIconPath,
		)

		mercenaryDataByKey[mercenaryKey] = mercenaryData
		usedCharacterKeys[characterKey] = true

	mercenaryDataByKey.make_read_only()
	return mercenaryDataByKey


static func LoadMercenaryBuffData() -> Dictionary[int, Array]:
	var tablePath: String = _GetTablePath("mercenary", "MercenaryBuffTable")
	var rows: Array[Dictionary] = CSVLoader.Load(tablePath)

	var mercenaryBuffDataByKey: Dictionary[int, Array] = { }
	var usedStatTypesByMercenaryKey: Dictionary[int, Dictionary] = { }

	for row: Dictionary in rows:
		var mercenaryKey: int = _ReadInt(row, "mercenaryKey", 0, "MercenaryBuffTable")
		if mercenaryKey == INVALID_INT:
			continue

		var context: String = "key: " + str(mercenaryKey)

		var statTypeText: String = row["statType"].strip_edges()
		if statTypeText.is_empty():
			push_error("MercenaryBuffTable statType이 비어있습니다. " + context)
			continue

		if not CharacterStats.Type.has(statTypeText):
			push_error("MercenaryBuffTable statType이 올바르지 않습니다. " + context)
			continue

		var statType: CharacterStats.Type = CharacterStats.Type[statTypeText]
		if not CharacterStats.IsValidType(statType):
			push_error("MercenaryBuffTable statType이 올바르지 않습니다. " + context)
			continue

		if not usedStatTypesByMercenaryKey.has(mercenaryKey):
			usedStatTypesByMercenaryKey[mercenaryKey] = { }

		var usedStatTypes: Dictionary = usedStatTypesByMercenaryKey[mercenaryKey]
		if usedStatTypes.has(statType):
			push_error(
				"MercenaryBuffTable에 같은 용병의 중복 statType이 있습니다. "
				+ context + ", statType: " + statTypeText
			)
			continue

		usedStatTypes[statType] = true

		var flatValue: int = _ReadInt(row, "flatValue", 0, "MercenaryBuffTable", context)
		if flatValue == INVALID_INT:
			continue

		var ratioValue: int = _ReadInt(row, "ratioValue", 0, "MercenaryBuffTable", context)
		if ratioValue == INVALID_INT:
			continue

		var mercenaryBuffData: MercenaryBuffData = MercenaryBuffData.new(
			mercenaryKey,
			statType,
			flatValue,
			ratioValue,
		)

		if not mercenaryBuffDataByKey.has(mercenaryKey):
			var buffDataList: Array[MercenaryBuffData] = []
			mercenaryBuffDataByKey[mercenaryKey] = buffDataList

		var buffDataList: Array[MercenaryBuffData] = mercenaryBuffDataByKey[mercenaryKey]
		buffDataList.append(mercenaryBuffData)

	for mercenaryKey: int in mercenaryBuffDataByKey:
		mercenaryBuffDataByKey[mercenaryKey].make_read_only()

	mercenaryBuffDataByKey.make_read_only()
	return mercenaryBuffDataByKey


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

static func ValidateMercenaryBuffDataReferences(
	mercenaryBuffDataByKey: Dictionary[int, Array],
	mercenaryDataByKey: Dictionary[int, MercenaryData],
) -> bool:
	var isValid: bool = true

	for mercenaryKey: int in mercenaryBuffDataByKey:
		if mercenaryDataByKey.has(mercenaryKey):
			continue

		push_error("MercenaryBuffTable에 존재하지 않는 mercenaryKey가 있습니다. key: " + str(mercenaryKey))
		isValid = false

	return isValid


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


static func _ReadBool(
	row: Dictionary,
	fieldName: String,
	tableName: String,
	context: String = "",
) -> Variant:
	var text: String = row[fieldName].strip_edges()
	match text:
		"1":
			return true
		"0":
			return false
		_:
			var message: String = ("%s %s는 1/0이어야 합니다." % [tableName, fieldName])

			if not context.is_empty():
				message += " " + context

			push_error(message)
			return null


static func _CompareDefenseSpawnTime(a: DefenseSpawnData, b: DefenseSpawnData) -> bool:
	return a.spawnTimeMs < b.spawnTimeMs


static func _GetTablePath(category: String, tableName: String) -> String:
	return GAME_DATA_PATH.path_join(category).path_join(tableName + ".csv")

#endregion
