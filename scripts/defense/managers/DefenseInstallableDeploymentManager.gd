class_name DefenseInstallableDeploymentManager
extends RefCounted


class DefenseInstallableDeployment:
	var characterKey: int


	func _init(pCharacterKey: int) -> void:
		characterKey = pCharacterKey


var _deployments: Dictionary[Vector2i, DefenseInstallableDeployment] = { }

var _availableCountByCharacterKey: Dictionary[int, int] = { }
var _deployedCountByCharacterKey: Dictionary[int, int] = { }


func Initialize(availableCountByCharacterKey: Dictionary[int, int]) -> bool:
	_deployments.clear()
	_availableCountByCharacterKey.clear()
	_deployedCountByCharacterKey.clear()

	for characterKey: int in availableCountByCharacterKey:
		var count: int = availableCountByCharacterKey[characterKey]
		if count < 0:
			push_error(
				"DefenseInstallableDeploymentManager: 보유 수량이 음수입니다. key: " + str(characterKey)
			)
			return false

		var characterData: CharacterData = GameDataManager.GetCharacterData(characterKey)
		if characterData == null:
			push_error(
				"DefenseInstallableDeploymentManager: CharacterData가 없습니다. key: "
				+ str(characterKey)
			)
			return false

		if not _IsInstallableType(characterData.characterType):
			push_error(
				"DefenseInstallableDeploymentManager: MACHINE/TRAP이 아닙니다. key: " + str(characterKey)
			)
			return false

		_availableCountByCharacterKey[characterKey] = count
		_deployedCountByCharacterKey[characterKey] = 0

	return true


func GetDeploymentCells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []

	for cell: Vector2i in _deployments:
		cells.append(cell)

	return cells


func GetDeploymentByCell(cell: Vector2i) -> DefenseInstallableDeployment:
	return _deployments.get(cell)


func GetAvailableCount(characterKey: int) -> int:
	return _availableCountByCharacterKey.get(characterKey, 0)


func GetDeployedCount(characterKey: int) -> int:
	return _deployedCountByCharacterKey.get(characterKey, 0)


func GetRemainingCount(characterKey: int) -> int:
	return (GetAvailableCount(characterKey) - GetDeployedCount(characterKey))


func AddDeployment(cell: Vector2i, characterKey: int) -> bool:
	if _deployments.has(cell):
		return false

	if GetRemainingCount(characterKey) <= 0:
		return false

	if not _availableCountByCharacterKey.has(characterKey):
		return false

	_deployments[cell] = DefenseInstallableDeployment.new(characterKey)

	_deployedCountByCharacterKey[characterKey] = (GetDeployedCount(characterKey) + 1)

	return true


func RemoveDeployment(cell: Vector2i) -> bool:
	var deployment: DefenseInstallableDeployment = _deployments.get(cell)
	if deployment == null:
		return false

	var characterKey: int = deployment.characterKey

	_deployments.erase(cell)

	_deployedCountByCharacterKey[characterKey] = maxi(GetDeployedCount(characterKey) - 1, 0)

	return true


func UpdateDeployment(cell: Vector2i, characterKey: int) -> bool:
	var deployment: DefenseInstallableDeployment = _deployments.get(cell)
	if deployment == null:
		return false

	if deployment.characterKey == characterKey:
		return true

	if GetRemainingCount(characterKey) <= 0:
		return false

	if not _availableCountByCharacterKey.has(characterKey):
		return false

	var previousCharacterKey: int = deployment.characterKey

	_deployedCountByCharacterKey[previousCharacterKey] = maxi(
		GetDeployedCount(previousCharacterKey) - 1,
		0,
	)

	_deployedCountByCharacterKey[characterKey] = (GetDeployedCount(characterKey) + 1)

	deployment.characterKey = characterKey

	return true


func HasDeployment() -> bool:
	return not _deployments.is_empty()


func _IsInstallableType(characterType: CharacterData.CharacterType) -> bool:
	return (
		characterType == CharacterData.CharacterType.MACHINE
		or characterType == CharacterData.CharacterType.TRAP
	)
