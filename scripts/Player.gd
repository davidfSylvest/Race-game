extends CharacterBody2D

## Lean-based movement feel-test character.
## Movement is side-view. Lean force is applied along the actual ground
## tangent (not a fixed world-horizontal axis), so the same lean input
## behaves differently on a downhill vs an uphill: leaning into a downhill
## compounds with gravity for extra push and a raised speed ceiling,
## leaning up a slope fights gravity for reduced push and a lowered ceiling.

signal fell()

@export_group("Acceleration")
@export var max_accel_constant: float = 900.0 # px/s^2 at full lean, applied along the ground tangent
@export var friction_decay: float = 0.98 # multiplicative decay applied every physics frame to ground-speed, lean or no lean

@export_group("Top Speed Curve")
@export var top_speed_constant: float = 650.0 # px/s ceiling at full lean on flat ground
@export var speed_exponent: float = 2.5 # exponential steepness of the lean -> top speed curve

@export_group("Gravity")
@export var gravity: float = 1600.0 # px/s^2, pulls the character down onto slopes

@export_group("Slope Response")
@export var slope_ceiling_bonus: float = 0.9 # how much a downhill raises (or uphill lowers) the speed ceiling; 0 = flat-ground behavior everywhere
@export var slope_ceiling_floor: float = 0.2 # uphill can never shrink the ceiling below this fraction of its flat-ground value
@export var gravity_slope_assist: float = 0.2 # gentle passive drift downhill even with no lean input; kept small so lean stays the dominant force, not gravity

@export_group("Fall / Wipeout")
@export var fall_threshold: float = 0.9 # lean magnitude that starts the wipeout clock
@export var fall_sustain_time: float = 0.4 # seconds of sustained over-lean before wiping out
@export var fall_speed_penalty: float = 0.2 # velocity multiplier applied on wipeout
@export var recover_time: float = 0.6 # seconds of locked-out input after a wipeout

@export_group("Lean Visual")
@export var max_tilt_degrees: float = 35.0 # visual tilt at full effective lean, so you can see how hard you're leaning
@export var normal_color: Color = Color(0.85, 0.25, 0.25, 1)
@export var locked_out_color: Color = Color(0.4, 0.4, 0.45, 1) # tint while wiped out / lean is locked out

@onready var joystick: Control = %Joystick
@onready var visual: Node2D = $Visual

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
	var dir_sign: float = signf(effective_x) if absf(effective_x) > 0.001 else 0.0

	# Ground tangent: the direction "forward along the slope" (matches world
	# +x on flat ground). Airborne, there's no surface to push against, so
	# lean falls back to pure horizontal, same as flat ground.
	var on_floor: bool = is_on_floor()
	var tangent: Vector2 = Vector2.RIGHT
	if on_floor:
		var normal: Vector2 = get_floor_normal()
		tangent = Vector2(-normal.y, normal.x).normalized()

	# Positive = leaning in the downhill direction of the current slope,
	# negative = leaning into the uphill face. Zero on flat ground or airborne.
	var forward_slope: float = dir_sign * tangent.y if on_floor else 0.0

	if effective_magnitude > 0.0 and dir_sign != 0.0:
		var accel_force: float = effective_magnitude * max_accel_constant
		var speed_ratio: float = pow(effective_magnitude, speed_exponent)
		var slope_multiplier: float = max(1.0 + forward_slope * slope_ceiling_bonus, slope_ceiling_floor)
		var max_speed_this_frame: float = speed_ratio * top_speed_constant * slope_multiplier

		# Accelerate toward the ceiling this lean+slope unlocks, but never yank
		# existing momentum down if it's already above that ceiling - velocity
		# only bleeds off via friction_decay, never an input clamp.
		var ground_speed: float = velocity.dot(tangent)
		if absf(ground_speed) < max_speed_this_frame:
			velocity += tangent * dir_sign * accel_force * delta
			var new_ground_speed: float = velocity.dot(tangent)
			var clamped: float = clamp(new_ground_speed, -max_speed_this_frame, max_speed_this_frame)
			velocity += tangent * (clamped - new_ground_speed)

	# Gravity always pulls straight down (needed for airborne falls and floor
	# detection). On top of that, an explicit tangential assist makes the
	# downhill/uphill pull on your ground-speed strong and tunable, rather
	# than relying entirely on incidental floor-collision sliding.
	velocity.y += gravity * delta
	if on_floor:
		velocity += tangent * (tangent.y * gravity * gravity_slope_assist * delta)

	# Friction bleeds ground-speed (the tangential component) every frame,
	# lean or no lean; it never touches the perpendicular/airborne component.
	var ground_speed_now: float = velocity.dot(tangent)
	velocity += tangent * (ground_speed_now * (friction_decay - 1.0))

	move_and_slide()

	current_speed = velocity.length()

	_update_visual(effective_x)

	if _locked_out:
		_recover_timer -= delta
		if _recover_timer <= 0.0:
			_locked_out = false


func _get_lean_vector() -> Vector2:
	if joystick and joystick.has_method("get_vector"):
		return joystick.get_vector()
	return Vector2.ZERO


## Resets position/velocity/state for an in-game restart (no scene reload).
func reset(spawn_position: Vector2) -> void:
	global_position = spawn_position
	velocity = Vector2.ZERO
	current_speed = 0.0
	_over_threshold_time = 0.0
	_locked_out = false
	_recover_timer = 0.0
	if visual:
		visual.rotation = 0.0
		visual.modulate = normal_color


## Tilts the character toward the current effective lean (0 while locked out,
## so a wipeout visibly snaps the character upright) and tints it to flag
## the lockout state - the only feedback for "how hard am I leaning right now".
func _update_visual(effective_lean_x: float) -> void:
	if not visual:
		return
	visual.rotation = effective_lean_x * deg_to_rad(max_tilt_degrees)
	visual.modulate = locked_out_color if _locked_out else normal_color


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
