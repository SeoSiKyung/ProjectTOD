class_name Faction

enum Type {
	NONE = 0,
	ALLY = 1,
	ENEMY = 2,
	ALL = 3,
}


static func GetOppositeType(type: int) -> int:
	return Type.ALL & ~type
