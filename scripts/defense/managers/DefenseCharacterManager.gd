class_name DefenseCharacterManager
extends RefCounted

signal CharacterDied(character: Unit, status: DefenseCharacterStatus)

var _statusByCharacter: Dictionary = { }


func Clear() -> void:
	_statusByCharacter.clear()


func UnbindCharacter(character: Unit) -> bool:
	if not _statusByCharacter.has(character):
		return false

	_statusByCharacter.erase(character)
	return true


func GetStatusByCharacter(character: Unit) -> DefenseCharacterStatus:
	return _statusByCharacter.get(character)


func GetCharacters() -> Array[Unit]:
	var characters: Array[Unit] = []
	for character: Unit in _statusByCharacter:
		characters.append(character)

	return characters


func GetActiveCount() -> int:
	return _statusByCharacter.size()


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

	_statusByCharacter[character] = status
	return true
