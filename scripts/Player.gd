extends CharacterBody2D

## Lean-based movement feel-test character.
## Movement is horizontal (side-view course); gravity + slope collision
## handle vertical motion and the downhill/crest speed transfer.

signal fell()

@export_group("Acceleration")
@export var max_accel_constant: float = 900.0 # px/s^2 at full lean
@export var friction_decay: float = 0.98 # multiplicative velocity decay applied every physics frame, lean or no lean

@export_group("Top Speed Curve")
@export var top_speed_constant: float = 650.0 # px/s ceiling at full lean
@export var speed_exponent: float = 2.5 # exponential steepness of the lean -> top speed curve

@export_group("Gravity")
@export var gravity: float = 1600.0 # px/s^2, pulls the character down onto slopes

@export_group("Fall / Wipeout")
@export var fall_threshold: float = 0.9 # lean magnitude that starts the wipeout clock
@export var fall_sustain_time: float = 0.4 # seconds of sustained over-lean before wiping out
@export var fall_speed_penalty: float = 0.2 # velocity multiplier applied on wipeout
@export var recover_time: float = 0.6 # seconds of locked-out input after a wipeout

@onready var joystick: Control = %Joystick

var current_speed: float = 0.0

var _over_threshold_time: float = 0.0
var _locked_out: bool = false
var _recover_timer: float = 0.0


func _ready() -> void:
	floor_max_angle = deg_to_rad(55.0)
	floor_snap_length = 12.0


func _physics_process(delta: float) -> void:
	var lean: Vector2 = _get_lean_vector()
	var lean_magnitude: float = clamp(lean.length(), 0.0, 1.0)

	_update_fall_state(delta, lean_magnitude)

	var effective_magnitude: float = 0.0 if _locked_out else lean_magnitude
	var effective_x: float = 0.0 if _locked_out else lean.x

	if effective_magnitude > 0.0:
		var accel_force: float = effective_magnitude * max_accel_constant
		var dir_sign: float = signf(effective_x) if absf(effective_x) > 0.001 else 0.0
		var speed_ratio: float = pow(effective_magnitude, speed_exponent)
		var max_speed_this_frame: float = speed_ratio * top_speed_constant

		# Accelerate toward the ceiling this lean unlocks, but never yank
		# existing momentum down if it's already above that ceiling -
		# velocity only bleeds off via friction_decay, never an input clamp.
		if dir_sign != 0.0 and absf(velocity.x) < max_speed_this_frame:
			velocity.x += dir_sign * accel_force * delta
			velocity.x = clamp(velocity.x, -max_speed_this_frame, max_speed_this_frame)

	velocity.y += gravity * delta
	velocity.x *= friction_decay

	move_and_slide()

	current_speed = velocity.length()

	if _locked_out:
		_recover_timer -= delta
		if _recover_timer <= 0.0:
			_locked_out = false


func _get_lean_vector() -> Vector2:
	if joystick and joystick.has_method("get_vector"):
		return joystick.get_vector()
	return Vector2.ZERO


func _update_fall_state(delta: float, lean_magnitude: float) -> void:
	if lean_magnitude > fall_threshold:
		_over_threshold_time += delta
	else:
		_over_threshold_time = 0.0

	if not _locked_out and _over_threshold_time > fall_sustain_time:
		_trigger_fall()


func _trigger_fall() -> void:
	velocity *= fall_speed_penalty
	_locked_out = true
	_recover_timer = recover_time
	_over_threshold_time = 0.0
	fell.emit()


func is_locked_out() -> bool:
	return _locked_out
