class_name DefenseTimeManager
extends RefCounted

var _elapsedTimeMs: int = 0
var _lastTimeMs: int = 0
var _isRunning: bool = false


func Initialize() -> void:
	_elapsedTimeMs = 0
	_lastTimeMs = Time.get_ticks_msec()
	_isRunning = true


func Update() -> void:
	if not _isRunning:
		return

	var currentTimeMs: int = Time.get_ticks_msec()
	var deltaTimeMs: int = currentTimeMs - _lastTimeMs

	_elapsedTimeMs += deltaTimeMs
	_lastTimeMs = currentTimeMs


func PauseBattle() -> void:
	if not _isRunning:
		return

	Update()
	_isRunning = false


func ResumeBattle() -> void:
	if _isRunning:
		return

	_lastTimeMs = Time.get_ticks_msec()
	_isRunning = true


func GetElapsedTimeMs() -> int:
	return _elapsedTimeMs
