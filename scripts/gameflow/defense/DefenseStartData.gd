class_name DefenseStartData
extends RefCounted

var cycle: int = 0
var population: int = 0

var cpMaxHp: int = 0

# characterKey -> 보유 수량, MACHINE + TRAP
var installableCountByCharacterKey: Dictionary[int, int] = { }

var availableMercenaryKeys: Array[int] = []
