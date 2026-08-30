class_name SkillCommand
extends UnitCommand

var skillId: StringName = &""
var target: SkillTarget


func _init(pUnitIds: PackedInt32Array, pSkillId: StringName, pTarget: SkillTarget) -> void:
	super(pUnitIds)
	skillId = pSkillId

	if is_instance_valid(pTarget):
		target = pTarget.Duplicate()
	else:
		push_error("SkillCommand에 유효한 SkillTarget이 없습니다.")
