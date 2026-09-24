class_name NavigationPathSearchState
extends RefCounted

const MAX_GENERATION: int = 2_147_483_647

var f: PackedFloat64Array = PackedFloat64Array()
var g: PackedFloat64Array = PackedFloat64Array()
var h: PackedFloat64Array = PackedFloat64Array()
var turnCost: PackedFloat64Array = PackedFloat64Array()

var parent: PackedInt32Array = PackedInt32Array()
var incomingDirection: PackedInt32Array = PackedInt32Array()
var heapPosition: PackedInt32Array = PackedInt32Array()

var _searchStamp: PackedInt32Array = PackedInt32Array()
var _generation: int = 0


func Resize(size: int) -> void:
	f.resize(size)
	g.resize(size)
	h.resize(size)
	turnCost.resize(size)

	parent.resize(size)
	incomingDirection.resize(size)
	heapPosition.resize(size)

	_searchStamp.resize(size)

	heapPosition.fill(-1)
	_searchStamp.fill(0)

	_generation = 0


func BeginSearch() -> void:
	if _generation >= MAX_GENERATION:
		_searchStamp.fill(0)
		_generation = 1
		return

	_generation += 1


func Touch(index: int) -> bool:
	var stamp: int = _searchStamp[index]

	if stamp == _generation or stamp == -_generation:
		return false

	_searchStamp[index] = _generation

	f[index] = Math.BIG_NUMBER
	g[index] = Math.BIG_NUMBER
	h[index] = Math.BIG_NUMBER
	turnCost[index] = Math.BIG_NUMBER

	parent[index] = -1
	incomingDirection[index] = -1

	return true


func IsClosed(index: int) -> bool:
	return _searchStamp[index] == -_generation


func MarkClosed(index: int) -> void:
	_searchStamp[index] = -_generation
