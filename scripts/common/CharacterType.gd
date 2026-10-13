class_name CharacterType

enum Type {
	ALLY,
	COMMAND_POST,
	TOWER,
	MACHINE,
	TRAP,
	ENEMY,
	COUNT,
}

const ALLY: Type = Type.ALLY
const COMMAND_POST: Type = Type.COMMAND_POST
const TOWER: Type = Type.TOWER
const MACHINE: Type = Type.MACHINE
const TRAP: Type = Type.TRAP
const ENEMY: Type = Type.ENEMY
const COUNT: Type = Type.COUNT


static func GetFaction(characterType: Type) -> Faction.Type:
	match characterType:
		ALLY, COMMAND_POST, TOWER, MACHINE, TRAP:
			return Faction.Type.ALLY

		ENEMY:
			return Faction.Type.ENEMY

		_:
			return Faction.Type.NONE
