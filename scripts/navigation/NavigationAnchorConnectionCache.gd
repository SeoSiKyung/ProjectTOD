class_name NavigationAnchorConnectionCache
extends RefCounted

var _entries: Dictionary[Vector4, NavigationAnchorTypes.ConnectionCacheEntry] = { }

var _order: Array[Vector4] = []


func Has(key: Vector4) -> bool:
	return _entries.has(key)


func Get(key: Vector4) -> Array[NavigationAnchorTypes.Connection]:
	if not _entries.has(key):
		return []

	var entry: NavigationAnchorTypes.ConnectionCacheEntry = _entries[key]
	_Touch(key)

	return entry.connections


func Set(key: Vector4, connections: Array[NavigationAnchorTypes.Connection], capacity: int) -> void:
	var entry: NavigationAnchorTypes.ConnectionCacheEntry = (
		NavigationAnchorTypes.ConnectionCacheEntry.new()
	)
	entry.connections = connections

	_entries[key] = entry

	_Touch(key)
	_Trim(capacity)


func Clear() -> void:
	_entries.clear()
	_order.clear()


func _Touch(key: Vector4) -> void:
	var existingIndex: int = _order.find(key)
	if existingIndex >= 0:
		_order.remove_at(existingIndex)

	_order.append(key)


func _Trim(capacity: int) -> void:
	var normalizedCapacity: int = maxi(1, capacity)
	while _order.size() > normalizedCapacity:
		var oldestKey: Vector4 = _order[0]
		_order.remove_at(0)
		_entries.erase(oldestKey)
