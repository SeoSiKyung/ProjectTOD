class_name MonsterAI
extends Node

@export var targetPolicy: TargetPolicy
@export var movementPolicy: MovementPolicy


func GetTargetPolicy() -> TargetPolicy:
	return targetPolicy


func GetMovementPolicy() -> MovementPolicy:
	return movementPolicy
