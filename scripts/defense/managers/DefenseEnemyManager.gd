class_name DefenseEnemyManager
extends DefenseCharacterManager


func AddEnemy(enemy: Enemy, characterData: CharacterData) -> bool:
	if enemy == null or characterData == null:
		return false

	if (
		characterData.characterType != CharacterData.CharacterType.ENEMY
		or enemy.characterType != CharacterData.CharacterType.ENEMY
		or enemy.characterKey != characterData.characterKey
	):
		push_error("DefenseEnemyManager: Enemy 데이터가 일치하지 않습니다.")
		return false

	if enemy.GetTargetPolicy() == null:
		push_error("DefenseEnemyManager: Enemy의 TargetPolicy가 없습니다.")
		return false

	return RegisterCharacter(enemy)
