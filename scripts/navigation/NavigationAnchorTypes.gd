class_name NavigationAnchorTypes
extends RefCounted


class GraphEdge:
	var toPortalId: int = -1
	var toAnchorIndex: int = -1

	var route: NavigationPortalRouteData = null
	var reversed: bool = false


class GraphData:
	var edgesByNode: Dictionary[Vector2i, Array] = { }


class Connection:
	var nodeKey: Vector2i = Vector2i(-1, -1)
	var path: PackedVector2Array = PackedVector2Array()
	var cost: float = Math.BIG_NUMBER


class ConnectionCacheEntry:
	var connections: Array[Connection] = []


class RegionTopology:
	var nodes: Array[Vector2i] = []
	var componentByNode: Dictionary[Vector2i, int] = { }
