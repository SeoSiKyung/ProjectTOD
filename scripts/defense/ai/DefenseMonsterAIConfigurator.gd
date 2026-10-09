class_name DefenseMonsterAIConfigurator
extends RefCounted


static func Configure(monster: Unit, characterData: CharacterData) -> bool:
	if monster == null or characterData == null:
		push_error("DefenseMonsterAIConfigurator: Unit 또는 CharacterData가 없습니다.")
		return false

	if characterData.characterType != CharacterData.CharacterType.MONSTER:
		push_error(
			"DefenseMonsterAIConfigurator: MONSTER 타입이 아닙니다. key: "
			+ str(characterData.characterKey)
		)
		return false

	if monster.characterKey != characterData.characterKey:
		push_error("DefenseMonsterAIConfigurator: 캐릭터 키가 일치하지 않습니다.")
		return false

	if monster.get_node_or_null("MonsterAI") != null:
		push_error("DefenseMonsterAIConfigurator: MonsterAI가 이미 존재합니다.")
		return false

	var targetPolicy: TargetPolicy = _CreateTargetPolicy(characterData.targetPolicyId)
	if targetPolicy == null:
		return false

	var movementPolicy: MovementPolicy = _CreateMovementPolicy(characterData.movementPolicyId)
	if movementPolicy == null:
		return false

	var monsterAI: MonsterAI = MonsterAI.new()
	monsterAI.name = "MonsterAI"
	monsterAI.targetPolicy = targetPolicy
	monsterAI.movementPolicy = movementPolicy

	monster.add_child(monsterAI)

	return true


static func _CreateTargetPolicy(policyId: String) -> TargetPolicy:
	match policyId:
		"DEFAULT":
			return DefaultMonsterTargetPolicy.new()
		"CP_RUSH":
			return CommandPostRushTargetPolicy.new()
		_:
			push_error("DefenseMonsterAIConfigurator: 알 수 없는 TargetPolicy입니다. id: " + policyId)
			return null


static func _CreateMovementPolicy(policyId: String) -> MovementPolicy:
	match policyId:
		"CHASE":
			return DefaultChaseMovementPolicy.new()
		_:
			push_error("DefenseMonsterAIConfigurator: 알 수 없는 MovementPolicy입니다. id: " + policyId)
			return null
