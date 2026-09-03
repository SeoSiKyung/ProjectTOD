class_name SkillTarget
extends RefCounted

enum TargetType {
	SELF,
	UNIT,
	POSITION,
	DIRECTION
}

const INVALID_UNIT_ID: int = -1

var targetType: TargetType = TargetType.SELF
var targetUnitId: int = INVALID_UNIT_ID
var targetWorld: Vector2 = Vector2.ZERO
var targetDirection: Vector2 = Vector2.ZERO


static func CreateSelf() -> SkillTarget:
	return SkillTarget.new()


static func CreateForUnit(unitId: int) -> SkillTarget:
	var target: SkillTarget = SkillTarget.new()

	target.targetType = TargetType.UNIT
	target.targetUnitId = unitId
	return target


static func CreateAtPosition(worldPosition: Vector2) -> SkillTarget:
	var target: SkillTarget = SkillTarget.new()

	target.targetType = TargetType.POSITION
	target.targetWorld = worldPosition
	return target


static func CreateInDirection(direction: Vector2) -> SkillTarget:
	var target: SkillTarget = SkillTarget.new()

	target.targetType = TargetType.DIRECTION
	target.targetDirection = direction
	return target


func Duplicate() -> SkillTarget:
	var duplicatedTarget: SkillTarget = SkillTarget.new()

	duplicatedTarget.targetType = targetType
	duplicatedTarget.targetUnitId = targetUnitId
	duplicatedTarget.targetWorld = targetWorld
	duplicatedTarget.targetDirection = targetDirection
	return duplicatedTarget
