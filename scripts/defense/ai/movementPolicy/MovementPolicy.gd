class_name MovementPolicy
extends Resource


func ShouldMove(monster: Unit, _target: Unit, distance: float) -> bool:
	var attackRange: float = float(monster.GetStat(CharacterStats.Type.ATK_RANGE))
	return distance > attackRange


func GetDestination(_monster: Unit, _target: Unit, _distance: float) -> Vector2:
	return Vector2.INF
