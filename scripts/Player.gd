extends CharacterBody2D

## Lean-based movement feel-test character.
## Movement is side-view. Lean force is applied along the actual ground
## tangent (not a fixed world-horizontal axis), so the same lean input
## behaves differently on a downhill vs an uphill: leaning into a downhill
## compounds with gravity for extra push and a raised speed ceiling,
## leaning up a slope fights gravity for reduced push and a lowered ceiling.
## On top of that, the lean ANGLE is expected to track the slope: pointing
## the stick down-and-forward on a downhill or up-and-forward on an uphill
## is mechanically rewarded over just holding a flat push-forward - it's
## not "find the right force forward," it's "match the hill."
##
## Flow state: technique compounds instead of resetting between sections.
## Landing a jump with velocity aligned to the new slope preserves/boosts
## your speed; landing mismatched scrubs some off. Separately, sustained
## well-aimed lean builds a Flow meter that raises your accel/ceiling while
## it's up, so a good stretch of riding makes the next stretch easier to
## ride well too - and losing technique lets it fade back down.

@export_group("Acceleration")
@export var max_accel_constant: float = 900.0 # px/s^2 at full lean, applied along the ground tangent
@export var friction_decay: float = 0.98 # multiplicative decay applied every physics frame to ground-speed, lean or no lean

@export_group("Top Speed Curve")
@export var top_speed_constant: float = 650.0 # px/s ceiling at full lean on flat ground
@export var speed_exponent: float = 2.5 # exponential steepness of the lean -> top speed curve
@export var min_ceiling_with_any_lean: float = 90.0 # px/s floor on the ceiling whenever there's real lean intent (directional_magnitude above a tiny threshold) - the exponent + a bad alignment penalty can otherwise compound into a near-crawl on steep uphills (measured ~38 px/s in testing); this doesn't touch the curve for good alignment, only lifts the worst-case floor so bad technique is slow, never an effective soft-lock

@export_group("Gravity")
@export var gravity: float = 1600.0 # px/s^2, pulls the character down onto slopes

@export_group("Slope Response")
@export var slope_ceiling_bonus: float = 0.9 # how much a downhill raises (or uphill lowers) the speed ceiling; 0 = flat-ground behavior everywhere
@export var slope_ceiling_floor: float = 0.32 # uphill can never shrink the ceiling below this fraction of its flat-ground value - kept above a bare crawl so weak/unaimed input on a climb is still slow, not an effective soft-lock
@export var gravity_slope_assist: float = 0.2 # gentle passive drift downhill even with no lean input; kept small so lean stays the dominant force, not gravity
@export var max_combined_ceiling_multiplier: float = 2.2 # hard cap on slope * Flow * Chain stacking together, so a best-case moment can't multiply the ceiling by 3x+

@export_group("Lean Alignment")
@export var alignment_influence: float = 1.0 # 0 = only raw lean magnitude matters (old behavior); 1 = full angle-matching (see below)

@export_group("Landing Quality")
@export var landing_min_speed: float = 60.0 # below this, a touchdown is too gentle to count as a real landing (ignores settle-jitter)
@export var landing_penalty_worst: float = 0.75 # speed multiplier on a completely mismatched landing
@export var landing_bonus_best: float = 1.12 # speed multiplier on a perfectly-matched landing
@export var landing_flow_swing: float = 0.25 # how much a landing's quality also swings the Flow meter, worst to best

@export_group("Launch Quality")
@export var launch_min_speed: float = 80.0 # below this, leaving the ground is too gentle to count as a real launch
@export var launch_penalty_worst: float = 0.92 # speed multiplier leaving the ground badly off the slope's tangent - mild, launches aren't really "mistakes" the way bad landings are
@export var launch_bonus_best: float = 1.08 # speed multiplier popping cleanly off a crest along the tangent - a small reward for carrying speed smoothly into a jump instead of stumbling off it

@export_group("Air Control")
@export var air_control_accel: float = 260.0 # px/s^2 extra push along your current trajectory while airborne, when lean points that way (Quake/Trackmania-style "aim where you're going" air control - not free, has to be earned by pointing the stick right)

@export_group("Boost")
@export var boost_multiplier: float = 1.3 # flat multiplier applied to velocity's current magnitude the instant you enter a boost pad zone while grounded - a Trackmania staple. Unlike ice/mud (a continuous per-frame friction scale), this is a one-shot edge-triggered kick, same pattern as _apply_launch, so driving through slowly still gets boosted but a fast, well-managed approach gets launched much harder - momentum in, momentum out, no separate skill check of its own

@export_group("Jump")
@export var jump_impulse: float = 520.0 # px/s added along the floor normal on a jump input - along the actual slope's normal rather than a fixed world-up, so a jump off an incline pops away from the surface instead of just straight up, consistent with how lean/gravity already treat the real ground tangent as the reference axis, not world-horizontal/vertical
@export var jump_cooldown: float = 0.15 # seconds of forced delay before another jump can trigger, even if grounded again by then (e.g. a bhop bump) - guards against a single button_down accidentally re-firing across two adjacent physics frames right at a landing, not meant to be a felt limitation during normal play
@export var coyote_time: float = 0.1 # seconds after leaving the floor (walking off a ledge/crest) a jump input still counts as grounded - standard forgiveness for imprecise touch timing. Deliberately kept below jump_cooldown: cooldown alone already blocks any attempt to chain coyote time into a same-jump double-jump, so this never needs its own separate guard against that
@export var jump_buffer_time: float = 0.12 # seconds a jump press made too early (already airborne, past coyote) is remembered and fired the instant you land, instead of silently dropped - the landing counterpart to coyote time

@export_group("Chain")
@export var chain_quality_threshold: float = 0.7 # landing quality needed to extend (or start) a chain
@export var chain_window: float = 3.0 # seconds since the last landing within which another good landing still extends the chain, instead of starting over
@export var chain_bonus_per_link: float = 0.04 # +this fraction of ceiling/accel per chain link
@export var chain_max_bonus: float = 0.4 # hard cap on the total chain bonus, however long the streak runs

@export_group("Flow Meter")
@export var flow_good_threshold: float = 0.6 # directional_magnitude at/above this, while grounded, counts as "good technique"
@export var flow_gain_rate: float = 0.35 # per second, while sustaining good technique
@export var flow_decay_rate: float = 0.25 # per second, otherwise (bad angle, no lean, or airborne)
@export var flow_speed_bonus: float = 0.3 # +this fraction of top_speed_constant at flow = 1.0
@export var flow_accel_bonus: float = 0.15 # +this fraction of max_accel_constant at flow = 1.0

@export_group("Lean Visual")
@export var max_tilt_degrees: float = 35.0 # visual tilt (forward/back) at full effective lean.x
@export var max_crouch_scale: float = 0.35 # vertical squash/stretch at full effective lean.y - crouch tucking down, stand tall leaning up, so the angle-matching mechanic is visible, not just felt
@export var normal_color: Color = Color(0.85, 0.25, 0.25, 1)
@export var flow_color: Color = Color(1.0, 0.75, 0.15, 1) # blended in as Flow rises toward 1.0 - the HUD bar tells you the number, but the character itself should visibly light up with it too, since Flow is a moment-to-moment feel state, not just a stat
@export var max_landing_squash: float = 0.4 # extra one-shot squash on a completely mismatched landing, on top of the lean-driven crouch - a rough landing should visibly read as an impact, a clean one barely shows it
@export var landing_squash_decay_rate: float = 3.0 # per second, how fast the squash springs back out
@export var max_launch_stretch: float = 0.25 # brief upward stretch on takeoff, scaled by launch quality - a clean pop off a crest should look like one
@export var launch_stretch_decay_rate: float = 4.0 # per second, how fast the stretch settles back out

@onready var joystick: Control = %Joystick
@onready var visual: Node2D = $Visual
@onready var terrain: Node2D = %Terrain

var current_speed: float = 0.0
var flow: float = 0.0 # 0..1, see "Flow Meter" above
var chain_count: int = 0 # consecutive good-quality landings within chain_window of each other
var last_landing_quality: float = -1.0 # -1 = no landing yet this run; HUD readout
var last_launch_quality: float = -1.0 # ditto, for launches
var landing_event_id: int = 0 # increments once per actual landing, so Main.gd can edge-detect a fresh landing (e.g. to trigger camera shake) instead of polling last_landing_quality for changes
var launch_event_id: int = 0 # ditto, for launches (e.g. to trigger a camera zoom-kick)

var _was_on_floor: bool = false
var _last_grounded_tangent: Vector2 = Vector2.RIGHT
var _time_since_last_landing: float = 999.0
var _landing_squash: float = 0.0 # 0..max_landing_squash, decays toward 0 each frame
var _launch_stretch: float = 0.0 # 0..max_launch_stretch, decays toward 0 each frame
var _jump_cooldown_remaining: float = 0.0
var _coyote_timer: float = 999.0 # seconds since last on a floor, any cause (jump or walking off a ledge) - see coyote_time above for why jump_cooldown already covers the jump-caused case
var _jump_buffer_remaining: float = 0.0 # seconds left in which a landing should immediately fire the jump that was pressed too early - see jump_buffer_time above
var _was_in_boost_zone: bool = false # edge-detects entering a boost pad, same idea as _was_on_floor for landings


func _ready() -> void:
	floor_max_angle = deg_to_rad(55.0)
	floor_snap_length = 5.0


func _physics_process(delta: float) -> void:
	var lean: Vector2 = _get_lean_vector()
	var dir_sign: float = signf(lean.x) if absf(lean.x) > 0.001 else 0.0

	# Ground tangent: the direction "forward along the slope" (matches world
	# +x on flat ground). Airborne, there's no surface to push against, so
	# lean falls back to pure horizontal, same as flat ground.
	var on_floor: bool = is_on_floor()
	var tangent: Vector2 = Vector2.RIGHT
	if on_floor:
		var normal: Vector2 = get_floor_normal()
		tangent = Vector2(-normal.y, normal.x).normalized()

	_time_since_last_landing += delta
	_jump_cooldown_remaining = max(_jump_cooldown_remaining - delta, 0.0)
	_jump_buffer_remaining = max(_jump_buffer_remaining - delta, 0.0)
	_coyote_timer = 0.0 if on_floor else _coyote_timer + delta

	# Touched down this frame after being airborne last frame: a one-shot
	# impact that rewards matching your velocity to the new slope instead
	# of just always preserving speed for free.
	if on_floor and not _was_on_floor and velocity.length() > landing_min_speed:
		_apply_landing(tangent)

	# A jump pressed slightly too early (while still airborne, past coyote)
	# was queued instead of dropped - fire it now, after landing has already
	# redirected velocity onto the new surface above, so it reads as an
	# actual hop off the landing rather than getting immediately flattened
	# back onto the tangent by that same redirect.
	if on_floor and not _was_on_floor and _jump_buffer_remaining > 0.0:
		_do_jump()
		_jump_buffer_remaining = 0.0

	# Left the ground this frame after being grounded last frame: the
	# takeoff counterpart to landing - popping off a crest cleanly (velocity
	# still matching the slope you're leaving) gives a small speed reward,
	# leaving badly-angled costs a little. Uses the tangent from the last
	# grounded frame since there's no floor to read from once airborne.
	if not on_floor and _was_on_floor and velocity.length() > launch_min_speed:
		_apply_launch(_last_grounded_tangent)

	if on_floor:
		_last_grounded_tangent = tangent

	# Positive = heading in the downhill direction of the current slope,
	# negative = heading into the uphill face. Zero on flat ground or airborne.
	# This is about the SLOPE vs your travel direction - independent of how
	# well you've angled the stick, which is a separate factor below.
	var forward_slope: float = dir_sign * tangent.y if on_floor else 0.0

	var directional_magnitude: float = 0.0
	if dir_sign != 0.0:
		# How well the stick's actual angle matches the ideal direction for
		# this slope (the tangent, or its mirror if leaning/traveling
		# backward). Projecting the full lean vector onto that ideal
		# direction combines "how hard" and "how well-aimed" into one
		# number: a full-magnitude lean dead-on the slope gives 1.0, the
		# same push aimed badly gives less, never below 0 (a wrong-angle
		# lean just loses effectiveness, it doesn't reverse or punish you).
		var target_dir: Vector2 = tangent if dir_sign > 0.0 else -tangent
		var aligned_magnitude: float = clamp(lean.dot(target_dir), 0.0, 1.0)
		var raw_magnitude: float = clamp(lean.length(), 0.0, 1.0)
		directional_magnitude = lerp(raw_magnitude, aligned_magnitude, alignment_influence)

		if directional_magnitude > 0.0:
			var chain_multiplier: float = 1.0 + min(chain_count * chain_bonus_per_link, chain_max_bonus)
			var flow_speed_multiplier: float = (1.0 + flow * flow_speed_bonus) * chain_multiplier
			var flow_accel_multiplier: float = (1.0 + flow * flow_accel_bonus) * chain_multiplier
			var accel_force: float = directional_magnitude * max_accel_constant * flow_accel_multiplier
			var speed_ratio: float = pow(directional_magnitude, speed_exponent)
			var slope_multiplier: float = max(1.0 + forward_slope * slope_ceiling_bonus, slope_ceiling_floor)
			# Slope, Flow, and Chain each stack multiplicatively into the
			# ceiling - great on their own, but a steep downhill at max Flow
			# and a long Chain can otherwise combine to nearly 3x. Capping
			# the combined environmental+skill multiplier keeps any single
			# best-case moment from trivializing the course, while each
			# system still reads clearly on its own below the cap.
			var combined_multiplier: float = min(slope_multiplier * flow_speed_multiplier, max_combined_ceiling_multiplier)
			var max_speed_this_frame: float = max(speed_ratio * top_speed_constant * combined_multiplier, min_ceiling_with_any_lean)

			# Accelerate toward the ceiling this lean+slope+flow unlocks, but
			# never yank existing momentum down if it's already above that
			# ceiling - velocity only bleeds off via friction_decay, never an
			# input clamp.
			var ground_speed: float = velocity.dot(tangent)
			if absf(ground_speed) < max_speed_this_frame:
				velocity += tangent * dir_sign * accel_force * delta
				var new_ground_speed: float = velocity.dot(tangent)
				var clamped: float = clamp(new_ground_speed, -max_speed_this_frame, max_speed_this_frame)
				velocity += tangent * (clamped - new_ground_speed)

	# Air control: while airborne, pointing the stick along your current
	# trajectory (not just world-horizontal) adds a little extra speed -
	# an air-strafe-style reward for aiming where you're already going
	# instead of just coasting through the jump passively. Requires an
	# actual lean; doing nothing mid-air gets nothing.
	if not on_floor and velocity.length() > 10.0:
		var vel_dir: Vector2 = velocity.normalized()
		var air_alignment: float = clamp(lean.dot(vel_dir), 0.0, 1.0)
		if air_alignment > 0.0:
			velocity += vel_dir * air_alignment * air_control_accel * delta

	# Flow builds from sustained good technique on the ground, and fades
	# otherwise (bad angle, no lean, or mid-air) - it's a state you have to
	# keep earning, not a one-time unlock.
	var good_technique: bool = on_floor and directional_magnitude >= flow_good_threshold
	flow = clamp(flow + (flow_gain_rate if good_technique else -flow_decay_rate) * delta, 0.0, 1.0)

	# Gravity always pulls straight down (needed for airborne falls and floor
	# detection). On top of that, an explicit tangential assist makes the
	# downhill/uphill pull on your ground-speed strong and tunable, rather
	# than relying entirely on incidental floor-collision sliding.
	velocity.y += gravity * delta
	if on_floor:
		velocity += tangent * (tangent.y * gravity * gravity_slope_assist * delta)

	# Friction bleeds ground-speed (the tangential component) every frame,
	# lean or no lean; it never touches the perpendicular/airborne component.
	# Terrain can locally scale how much of that loss actually applies (an
	# ice patch means far less grip, so you carry way more speed through it).
	var friction_scale: float = terrain.friction_multiplier_at(position.x) if on_floor and terrain and terrain.has_method("friction_multiplier_at") else 1.0
	var effective_friction_decay: float = 1.0 - (1.0 - friction_decay) * friction_scale
	var ground_speed_now: float = velocity.dot(tangent)
	velocity += tangent * (ground_speed_now * (effective_friction_decay - 1.0))

	# Boost pad: a one-shot kick on the frame you enter the zone, applied
	# after friction above so it isn't immediately damped the same frame it
	# lands - the full boost_multiplier actually carries into this frame's
	# move_and_slide(). Grounded-only (there's no pad to detect while airborne
	# anyway, since this checks position.x against a ground zone, not a
	# trigger volume).
	var in_boost_zone: bool = on_floor and terrain and terrain.has_method("is_boost_zone_at") and terrain.is_boost_zone_at(position.x)
	if in_boost_zone and not _was_in_boost_zone:
		velocity *= boost_multiplier
	_was_in_boost_zone = in_boost_zone

	_was_on_floor = on_floor
	_landing_squash = max(_landing_squash - landing_squash_decay_rate * delta, 0.0)
	_launch_stretch = max(_launch_stretch - launch_stretch_decay_rate * delta, 0.0)

	move_and_slide()

	current_speed = velocity.length()

	_update_visual(lean)


## One-shot speed adjustment at the instant of touchdown: how well does the
## velocity direction (built up over the whole jump) match the tangent of
## the surface you're landing on? Dead-on gives a small bonus, way off
## scrubs some speed - never a hard reset, just a legible skill payoff for
## "landed it clean" vs "came in sideways."
##
## The result is redirected onto the tangent rather than just scaling the
## original (possibly very off-axis) vector in place - otherwise a steep
## mismatched landing gets hit twice: once by this penalty, and a second
## time when move_and_slide's floor collision separately absorbs whatever
## into-the-ground component the penalty didn't touch, compounding into an
## unpredictable near-total loss instead of the clean tunable multiplier
## below. Redirecting first means the multiplier is the whole story.
func _apply_landing(tangent: Vector2) -> void:
	var pre_speed: float = velocity.length()
	var travel_sign: float = signf(velocity.x) if absf(velocity.x) > 0.001 else 1.0
	var landing_target: Vector2 = tangent if travel_sign >= 0.0 else -tangent
	var landing_quality: float = clamp(velocity.normalized().dot(landing_target), 0.0, 1.0)
	velocity = landing_target * pre_speed * lerp(landing_penalty_worst, landing_bonus_best, landing_quality)
	flow = clamp(flow + lerp(-landing_flow_swing, landing_flow_swing, landing_quality), 0.0, 1.0)
	last_landing_quality = landing_quality
	landing_event_id += 1
	_landing_squash = (1.0 - landing_quality) * max_landing_squash

	# Bhop-style chain: a good landing soon after the last one extends the
	# streak; a good landing after too long a gap starts a fresh one at 1;
	# a bad landing breaks it back to 0.
	if landing_quality >= chain_quality_threshold:
		chain_count = chain_count + 1 if _time_since_last_landing <= chain_window else 1
	else:
		chain_count = 0
	_time_since_last_landing = 0.0


## One-shot speed adjustment at the instant of leaving the ground: the
## takeoff counterpart to _apply_landing. Unlike landing, this only scales
## the velocity's magnitude rather than redirecting it - the whole point of
## a crest launch is the arc the terrain already gave it (up and away from
## the slope), and flattening that onto the tangent would kill the jump.
## Safe to just scale here since there's no floor left to collide with the
## same frame (that's what "no longer on_floor" means).
func _apply_launch(tangent: Vector2) -> void:
	var travel_sign: float = signf(velocity.x) if absf(velocity.x) > 0.001 else 1.0
	var launch_target: Vector2 = tangent if travel_sign >= 0.0 else -tangent
	var launch_quality: float = clamp(velocity.normalized().dot(launch_target), 0.0, 1.0)
	velocity *= lerp(launch_penalty_worst, launch_bonus_best, launch_quality)
	last_launch_quality = launch_quality
	launch_event_id += 1
	_launch_stretch = launch_quality * max_launch_stretch


func _get_lean_vector() -> Vector2:
	if joystick and joystick.has_method("get_vector"):
		return joystick.get_vector()
	return Vector2.ZERO


## Public entry point for a jump input (button/tap). Grounded-or-coyote only
## - no true air/double jump. Within jump_cooldown of the last jump, the
## press is just dropped (see jump_cooldown above); otherwise if currently
## grounded, or within coyote_time of having left the ground, it jumps
## immediately - and if neither (genuinely airborne, past coyote), the
## press is queued via jump_buffer_time instead of silently lost, so an
## early tap on a bumpy section still lands as a jump.
func jump() -> void:
	if _jump_cooldown_remaining > 0.0:
		return
	if is_on_floor() or _coyote_timer <= coyote_time:
		_do_jump()
	else:
		_jump_buffer_remaining = jump_buffer_time


## The actual impulse: added along the floor normal on top of existing
## velocity (horizontal momentum carries through unchanged), then lets the
## ordinary on_floor -> airborne transition next physics frame trigger the
## existing launch-quality system exactly like a terrain-launched hop - a
## jump aimed well with your current travel gets the same small launch
## bonus a clean crest pop does, aimed badly costs a little the same mild
## way. Uses _last_grounded_tangent (rather than get_floor_normal(), which
## Godot may no longer report once actually airborne) rotated back to a
## normal, so this works identically whether called grounded, on coyote
## grace, or from a buffered landing.
func _do_jump() -> void:
	var normal: Vector2 = Vector2(_last_grounded_tangent.y, -_last_grounded_tangent.x)
	velocity += normal * jump_impulse
	_jump_cooldown_remaining = jump_cooldown


## Resets position/velocity/state for an in-game restart (no scene reload).
func reset(spawn_position: Vector2) -> void:
	global_position = spawn_position
	velocity = Vector2.ZERO
	current_speed = 0.0
	flow = 0.0
	chain_count = 0
	last_landing_quality = -1.0
	last_launch_quality = -1.0
	landing_event_id = 0
	launch_event_id = 0
	_was_on_floor = false
	_last_grounded_tangent = Vector2.RIGHT
	_time_since_last_landing = 999.0
	_jump_cooldown_remaining = 0.0
	_coyote_timer = 999.0
	_jump_buffer_remaining = 0.0
	_was_in_boost_zone = false
	_landing_squash = 0.0
	_launch_stretch = 0.0
	if visual:
		visual.rotation = 0.0
		visual.scale.y = 1.0
		visual.modulate = normal_color


## Tilts the character toward the current lean.x, squashes/stretches it
## toward lean.y (crouch tucking down, stand tall leaning up - the visible
## half of "match your lean angle to the slope"), and layers brief one-shot
## impact/pop effects for landing and launch quality so those read as
## actual physical events, not just a speed change a moment later.
func _update_visual(lean: Vector2) -> void:
	if not visual:
		return
	visual.rotation = lean.x * deg_to_rad(max_tilt_degrees)
	visual.scale.y = clamp(1.0 - lean.y * max_crouch_scale - _landing_squash + _launch_stretch, 0.3, 1.6)
	visual.modulate = normal_color.lerp(flow_color, flow)
