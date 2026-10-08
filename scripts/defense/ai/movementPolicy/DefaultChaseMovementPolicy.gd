class_name DefaultChaseMovementPolicy
extends MovementPolicy


func GetDestination(_monster: Unit, target: Unit) -> Vector2:
	return target.global_position
