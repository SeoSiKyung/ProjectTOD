class_name DefenseUnitGroupManager
extends RefCounted


class DefenseUnitGroupState:
	var characterKey: int

	var initialSoldierCount: int
	var aliveSoldierCount: int

	var hpPerSoldier: int = 0
	var maxHp: int = 0
	var currentHp: int = 0


	func _init(pCharacterKey: int, pSoldierCount: int, pHpPerSoldier: int):
		characterKey = pCharacterKey

		initialSoldierCount = pSoldierCount
		aliveSoldierCount = pSoldierCount

		hpPerSoldier = pHpPerSoldier
		maxHp = hpPerSoldier * aliveSoldierCount
		currentHp = maxHp


	func GetDeadSoldierCount() -> int:
		return initialSoldierCount - aliveSoldierCount


	func TakeDamage(damage: int) -> void:
		if damage <= 0:
			return

		currentHp = maxi(currentHp - damage, 0)
		_UpdateAliveSoldierCount()


	func _UpdateAliveSoldierCount() -> void:
		if currentHp <= 0:
			aliveSoldierCount = 0
			return

		aliveSoldierCount = Math.CeilDivide(currentHp, hpPerSoldier)


var _unitGroupStates: Dictionary = { }


func Initialize(deploymentManager: DefenseDeploymentManager, population: int) -> void:
	_unitGroupStates.clear()

	var cells: Array[Vector2i] = deploymentManager.GetDeploymentCells()
	for cell: Vector2i in cells:
		var deployment: DefenseDeploymentManager.DefenseDeployment = deploymentManager.GetDeployment(
			cell
		)

		var soldierCount: int = Math.ApplyRatio(population, deployment.recruitRatio)
		if soldierCount <= 0:
			continue

		var characterData: CharacterData = GameDataManager.GetCharacterData(deployment.characterKey)
		if characterData == null:
			push_error(
				"DefenseUnitGroupManager: 존재하지 않는 characterKey입니다. key: "
				+ str(deployment.characterKey)
			)
			continue

		if characterData.characterType != CharacterData.CharacterType.UNIT:
			push_error(
				"DefenseUnitGroupManager: UNIT 타입이 아닌 캐릭터가 배치되었습니다. key: "
				+ str(deployment.characterKey)
			)
			continue

		var state: DefenseUnitGroupState = DefenseUnitGroupState.new(
			deployment.characterKey,
			soldierCount,
			characterData.maxHp,
		)

		_unitGroupStates[cell] = state


func GetUnitGroupCells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []

	for cell: Vector2i in _unitGroupStates.keys():
		cells.append(cell)

	return cells


func GetUnitGroupState(cell: Vector2i) -> DefenseUnitGroupState:
	return _unitGroupStates.get(cell)


func GetTotalDeadSoldierCount() -> int:
	var total: int = 0

	for state: DefenseUnitGroupState in _unitGroupStates.values():
		total += state.GetDeadSoldierCount()

	return total
