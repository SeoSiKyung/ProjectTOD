class_name GameDataLoader
extends RefCounted

const GAME_DATA_PATH: String = "res://data/gameData"


static func LoadCharacterData() -> Dictionary:
	var tablePath: String = _GetTablePath("character", "CharacterTable")
	var rows: Array[Dictionary] = CSVLoader.Load(tablePath)

	var characterDataByKey: Dictionary = { }

	for row: Dictionary in rows:
		var characterKey: int = row["characterKey"].to_int()
		if characterKey < 0:
			push_error("CharacterTable characterKey는 0 이상이어야 합니다.")
			continue
		if characterDataByKey.has(characterKey):
			push_error("CharacterTable에 중복 characterKey가 있습니다. key: " + str(characterKey))
			continue

		var characterName: String = row["characterName"]
		if characterName.is_empty():
			push_error("CharacterTable characterName이 비어있습니다. key: " + str(characterKey))
			continue

		var characterType: CharacterData.CharacterType
		match row["characterType"].to_upper():
			"UNIT":
				characterType = CharacterData.CharacterType.UNIT

			"MONSTER":
				characterType = CharacterData.CharacterType.MONSTER

			_:
				push_error("CharacterTable characterType이 올바르지 않습니다. key: " + str(characterKey))
				continue

		var path: String = row["path"]
		# if path.is_empty():
		# 	push_error("CharacterTable path가 비어있습니다. key: " + str(characterKey))
		# 	continue
		var maxHp: int = row["maxHp"].to_int()
		if maxHp < 1:
			push_error("CharacterTable maxHp는 1 이상이어야 합니다. key: " + str(characterKey))
			continue

		var maxMp: int = row["maxMp"].to_int()
		if maxMp < 0:
			push_error("CharacterTable maxMp는 0 이상이어야 합니다. key: " + str(characterKey))
			continue

		var hpRegen: int = row["hpRegen"].to_int()
		if hpRegen < 0:
			push_error("CharacterTable hpRegen은 0 이상이어야 합니다. key: " + str(characterKey))
			continue

		var mpRegen: int = row["mpRegen"].to_int()
		if mpRegen < 0:
			push_error("CharacterTable mpRegen은 0 이상이어야 합니다. key: " + str(characterKey))
			continue

		var atk: int = row["atk"].to_int()
		if atk < 0:
			push_error("CharacterTable atk는 0 이상이어야 합니다. key: " + str(characterKey))
			continue

		var magicAtk: int = row["magicAtk"].to_int()
		if magicAtk < 0:
			push_error("CharacterTable magicAtk는 0 이상이어야 합니다. key: " + str(characterKey))
			continue

		var def: int = row["def"].to_int()
		if def < 0:
			push_error("CharacterTable def는 0 이상이어야 합니다. key: " + str(characterKey))
			continue

		var magicDef: int = row["magicDef"].to_int()
		if magicDef < 0:
			push_error("CharacterTable magicDef는 0 이상이어야 합니다. key: " + str(characterKey))
			continue

		var moveSpeed: int = row["moveSpeed"].to_int()
		if moveSpeed < 0:
			push_error("CharacterTable moveSpeed는 0 이상이어야 합니다. key: " + str(characterKey))
			continue

		var attackSpeed: int = row["attackSpeed"].to_int()
		if attackSpeed < 0:
			push_error("CharacterTable attackSpeed는 0 이상이어야 합니다. key: " + str(characterKey))
			continue

		var atkRange: int = row["atkRange"].to_int()
		if atkRange < 0:
			push_error("CharacterTable atkRange는 0 이상이어야 합니다. key: " + str(characterKey))
			continue

		var acquisitionRange: int = row["acquisitionRange"].to_int()
		if acquisitionRange < 0:
			push_error("CharacterTable acquisitionRange는 0 이상이어야 합니다. key: " + str(characterKey))
			continue

		var characterData: CharacterData = CharacterData.new(
			characterKey,
			characterName,
			characterType,
			path,
			maxHp,
			maxMp,
			hpRegen,
			mpRegen,
			atk,
			magicAtk,
			def,
			magicDef,
			moveSpeed,
			attackSpeed,
			atkRange,
			acquisitionRange,
		)

		characterDataByKey[characterKey] = characterData

	return characterDataByKey


static func LoadDefenseSpawnData() -> Dictionary:
	var tablePath: String = _GetTablePath("defense", "DefenseSpawnTable")
	var rows: Array[Dictionary] = CSVLoader.Load(tablePath)

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


static func _GetTablePath(category: String, tableName: String) -> String:
	return GAME_DATA_PATH.path_join(category).path_join(tableName + ".csv")
