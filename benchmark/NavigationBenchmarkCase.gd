class_name NavigationBenchmarkCase

var caseName: String
var start: Vector2
var target: Vector2
var halfSize: int


func _init(pCaseName: String, pStart: Vector2, pTarget: Vector2, pHalfSize: int) -> void:
	caseName = pCaseName
	start = pStart
	target = pTarget
	halfSize = pHalfSize
