class_name DefenseUnitGroupManager
extends RefCounted


class DefenseUnitGroupState:
	var unitType: int

	var initialSoldierCount: int
	var aliveSoldierCount: int

	var hpPerSoldier: int = 0
	var maxHp: int = 0
	var currentHp: int = 0


	func _init(pUnitType: int, pSoldierCount: int, pHpPerSoldier: int):
		unitType = pUnitType

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
		var deployment := deploymentManager.GetDeployment(cell)

		var soldierCount: int = Math.ApplyRatio(population, deployment.recruitRatio)

		# unitType으로 hp 조회
		# DefenseUnitGroupState 생성
