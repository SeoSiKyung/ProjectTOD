class_name DefenseCharacterManager
extends RefCounted

signal CharacterDied(character: Unit, status: DefenseCharacterStatus)

var _statusByCharacter: Dictionary[Unit, DefenseCharacterStatus] = { }
var _characters: Array[Unit] = []
var _characterIndexByCharacter: Dictionary[Unit, int] = { }


func Clear() -> void:
	_statusByCharacter.clear()
	_characters.clear()
	_characterIndexByCharacter.clear()


func UnbindCharacter(character: Unit) -> bool:
	if not _statusByCharacter.has(character):
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
	_statusByCharacter.erase(character)

	return true


func GetStatusByCharacter(character: Unit) -> DefenseCharacterStatus:
	return _statusByCharacter.get(character)


func GetCharacterCount() -> int:
	return _characters.size()


func GetCharacterByIndex(index: int) -> Unit:
	return _characters[index]


func GetActiveCount() -> int:
	return _characters.size()


func TakeDamage(character: Unit, damage: int) -> bool:
	var status: DefenseCharacterStatus = GetStatusByCharacter(character)
	if status == null or status.IsDead():
		return false

	status.TakeDamage(damage)
	if status.IsDead():
		CharacterDied.emit(character, status)

	return true


func _BindStatus(character: Unit, status: DefenseCharacterStatus) -> bool:
	if character == null or status == null:
		return false

	if _statusByCharacter.has(character):
		return false

	character.moveSpeed = status.moveSpeed

	_statusByCharacter[character] = status

	_characterIndexByCharacter[character] = _characters.size()
	_characters.append(character)

	return true
