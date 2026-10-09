class_name Enemy
extends Unit

var _targetPolicy: TargetPolicy


func ConfigureCharacter(characterData: CharacterData) -> bool:
	if characterData == null:
		return false

	if characterData.characterType != CharacterData.CharacterType.ENEMY:
		push_error("Enemy: ENEMY 타입이 아닙니다.")
		return false

	if not super.ConfigureCharacter(characterData):
		return false

	_targetPolicy = _CreateTargetPolicy(characterData.targetPolicyId)
	return _targetPolicy != null


func GetTargetPolicy() -> TargetPolicy:
	return _targetPolicy


func _CreateTargetPolicy(targetPolicyId: CharacterData.TargetPolicyId) -> TargetPolicy:
	match targetPolicyId:
		CharacterData.TargetPolicyId.DEFAULT:
			return DefaultEnemyTargetPolicy.new()
		CharacterData.TargetPolicyId.CP_RUSH:
			return CommandPostRushTargetPolicy.new()
		_:
			push_error("Enemy: TargetPolicy가 정의되지 않았습니다. key: " + str(characterKey))
			return null
