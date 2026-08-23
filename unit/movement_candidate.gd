class_name MovementCandidate
extends RefCounted


var order_id: int = -1
var unit_id: int = -1
var start_position: Vector2 = Vector2.ZERO
var desired_position: Vector2 = Vector2.ZERO
var position: Vector2 = Vector2.ZERO
var desired_velocity: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
var target_position: Vector2 = Vector2.ZERO
var half_size: Vector2 = Vector2.ZERO
var max_step_distance: float = 0.0
var desired_step_distance: float = 0.0
var final_tick: bool = false
var finish_order: bool = false
var arrival_active: bool = false
var arrival_slot: Vector2 = Vector2.ZERO
var arrival_distance: float = 0.0
var priority: int = 2147483647
