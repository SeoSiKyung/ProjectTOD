class_name DefaultChaseMovementPolicy
extends MovementPolicy


func GetDestination(_monster: Unit, target: Unit, _distance: float) -> Vector2:
	return target.global_position
