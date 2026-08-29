class_name NavigationFootprintData
extends Resource

@export var halfSize: int = 0

# portalId와 같은 index로 유지
@export var portals: Array[NavigationFootprintPortalData] = []

# 같은 Region 내부의 Portal ↔ Portal 경로
@export var portalRoutes: Array[NavigationPortalRouteData] = []
