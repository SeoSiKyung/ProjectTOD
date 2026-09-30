class_name DefenseCharacterManager
extends RefCounted

signal CharacterDied(character: Unit)

var _characters: Array[Unit] = []
var _characterIndexByCharacter: Dictionary[Unit, int] = { }


func Clear() -> void:
	_characters.clear()
	_characterIndexByCharacter.clear()


func RegisterCharacter(character: Unit) -> bool:
	if character == null or not character.HasCharacterStats():
		return false

	if _characterIndexByCharacter.has(character):
		return false

	_characterIndexByCharacter[character] = _characters.size()
	_characters.append(character)
	return true


func UnregisterCharacter(character: Unit) -> bool:
	if not _characterIndexByCharacter.has(character):
		return false

	var index: int = _characterIndexByCharacter.get(character, -1)
	if index < 0:
		push_error("DefenseCharacterManager: Character index를 찾을 수 없습니다.")
		return false

	var lastIndex: int = _characters.size() - 1
	if index != lastIndex:
		var lastCharacter: Unit = _characters[lastIndex]
		_characters[index] = lastCharacter
		_characterIndexByCharacter[lastCharacter] = index

	_characters.pop_back()
	_characterIndexByCharacter.erase(character)
	return true


func HasCharacter(character: Unit) -> bool:
	return character != null and _characterIndexByCharacter.has(character)


func GetCharacterCount() -> int:
	return _characters.size()


func GetCharacterByIndex(index: int) -> Unit:
	return _characters[index]


func GetActiveCount() -> int:
	return _characters.size()


func TakeDamage(character: Unit, damage: int) -> bool:
	if not HasCharacter(character) or character.IsDead():
		return false

	character.TakeDamage(damage)
	if character.IsDead():
		CharacterDied.emit(character)

	return true
