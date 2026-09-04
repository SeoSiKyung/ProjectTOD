class_name DefenseUnitGroupManager
extends RefCounted


class DefenseUnitGroupState:
	var characterKey: int

	var initialSoldierCount: int
	var aliveSoldierCount: int

	var hpPerSoldier: int
	var maxHp: int
	var currentHp: int


	func _init(pCharacterKey: int, pSoldierCount: int, pHpPerSoldier: int) -> void:
		characterKey = pCharacterKey

		initialSoldierCount = pSoldierCount
		aliveSoldierCount = pSoldierCount

		hpPerSoldier = pHpPerSoldier
		maxHp = hpPerSoldier * initialSoldierCount
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

		var state: DefenseUnitGroupState = _CreateUnitGroupState(deployment, population)
		if state == null:
			continue

		_unitGroupStates[cell] = state


func GetUnitGroupState(cell: Vector2i) -> DefenseUnitGroupState:
	return _unitGroupStates.get(cell)


func GetTotalDeadSoldierCount() -> int:
	var totalDeadSoldierCount: int = 0
	for cell: Vector2i in _unitGroupStates:
		var unitGroupState: DefenseUnitGroupState = _unitGroupStates[cell]
		totalDeadSoldierCount += unitGroupState.initialSoldierCount - unitGroupState.aliveSoldierCount

	return totalDeadSoldierCount


func _CreateUnitGroupState(
	deployment: DefenseDeploymentManager.DefenseDeployment,
	population: int,
) -> DefenseUnitGroupState:
	var soldierCount: int = Math.ApplyRatio(population, deployment.recruitRatio)
	if soldierCount <= 0:
		return null

	var characterData: CharacterData = GameDataManager.GetCharacterData(deployment.characterKey)
	if characterData == null:
		push_error(
			"DefenseUnitGroupManager: 존재하지 않는 characterKey입니다. key: " + str(deployment.characterKey)
		)
		return null

	if characterData.characterType != CharacterData.CharacterType.UNIT:
		push_error(
			"DefenseUnitGroupManager: UNIT 타입이 아닌 캐릭터가 배치되었습니다. key: "
			+ str(deployment.characterKey)
		)
		return null

	return DefenseUnitGroupState.new(deployment.characterKey, soldierCount, characterData.maxHp)
