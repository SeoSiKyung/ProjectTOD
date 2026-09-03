class_name MoveOrder
extends RefCounted

const INVALID_ORDER_ID: int = -1
const INVALID_INDEX: int = -1
const INACTIVE_FLAG: int = 0
const ACTIVE_FLAG: int = 1

var orderId: int = INVALID_ORDER_ID
var targetWorld: Vector2 = Vector2.ZERO
var arrivalCenter: Vector2 = Vector2.ZERO
var memberIds: PackedInt32Array = []
var arrivalSlots: PackedVector2Array = []
var activeMemberCount: int = 0

var _activeFlags: PackedByteArray = []
var _memberIndexByUnitId: Dictionary[int, int] = {}


func _init(pOrderId: int, pTargetWorld: Vector2, pArrivalCenter: Vector2, pMemberIds: PackedInt32Array, pArrivalSlots: PackedVector2Array) -> void:
	if pOrderId < 0:
		push_error("MoveOrder의 orderId는 0 이상이어야 합니다.")
		return

	if not pTargetWorld.is_finite() or not pArrivalCenter.is_finite():
		push_error("MoveOrder의 목표 위치가 유효하지 않습니다.")
		return

	if pMemberIds.is_empty():
		push_error("멤버가 없는 MoveOrder는 생성할 수 없습니다.")
		return

	if pMemberIds.size() != pArrivalSlots.size():
		push_error("MoveOrder의 memberIds와 arrivalSlots 크기가 일치하지 않습니다.")
		return

	var memberIndexByUnitId: Dictionary[int, int] = {}

	for index: int in range(pMemberIds.size()):
		var unitId: int = pMemberIds[index]

		if unitId < 0:
			push_error("MoveOrder에 유효하지 않은 unitId가 있습니다.")
			return

		if memberIndexByUnitId.has(unitId):
			push_error("MoveOrder에 unitId %d가 중복되어 있습니다." % unitId)
			return

		if not pArrivalSlots[index].is_finite():
			push_error("MoveOrder에 유효하지 않은 도착 슬롯이 있습니다.")
			return

		memberIndexByUnitId[unitId] = index

	orderId = pOrderId
	targetWorld = pTargetWorld
	arrivalCenter = pArrivalCenter
	memberIds = pMemberIds.duplicate()
	arrivalSlots = pArrivalSlots.duplicate()
	activeMemberCount = memberIds.size()
	_memberIndexByUnitId = memberIndexByUnitId

	_activeFlags.resize(activeMemberCount)
	_activeFlags.fill(ACTIVE_FLAG)


func IsValid() -> bool:
	return orderId != INVALID_ORDER_ID


func IsMemberActive(unitId: int) -> bool:
	var index: int = _memberIndexByUnitId.get(unitId, INVALID_INDEX)

	if index == INVALID_INDEX:
		return false

	return _activeFlags[index] == ACTIVE_FLAG


func GetArrivalSlot(unitId: int) -> Vector2:
	var index: int = _memberIndexByUnitId.get(unitId, INVALID_INDEX)

	if index == INVALID_INDEX:
		push_error("MoveOrder에 unitId %d가 없습니다." % unitId)
		return Vector2.ZERO

	return arrivalSlots[index]


func FinishMember(unitId: int) -> bool:
	var index: int = _memberIndexByUnitId.get(unitId, INVALID_INDEX)

	if index == INVALID_INDEX or _activeFlags[index] == INACTIVE_FLAG:
		return false

	_activeFlags[index] = INACTIVE_FLAG
	activeMemberCount -= 1
	return true


func IsFinished() -> bool:
	return activeMemberCount == 0
