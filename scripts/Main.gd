extends Node2D

## Orchestrates the run: starts the timer on first input, stops it at the
## end-zone, and drives the on-screen timer / speed debug readouts.

@onready var player: CharacterBody2D = %Player
@onready var joystick: Control = %Joystick
@onready var end_zone: Area2D = %EndZone
@onready var terrain: Node2D = %Terrain
@onready var timer_label: Label = %TimerLabel
@onready var best_label: Label = %BestLabel
@onready var speed_label: Label = %SpeedLabel
@onready var flow_bar_bg: Control = %FlowBarBg
@onready var flow_bar_fill: Control = %FlowBarFill
@onready var chain_label: Label = %ChainLabel
@onready var restart_button: Button = %RestartButton
@onready var jump_button: Button = %JumpButton
@onready var camera: Camera2D = player.get_node("Camera2D")

const PLAYER_GROUND_OFFSET: float = 40.0 # ball diameter (2x Player.ball_radius) - keeps the ball's bottom at the surface, matches Player's local origin-at-ground-contact convention
const END_ZONE_HEIGHT: float = 400.0
const END_ZONE_MARGIN: float = 100.0 # back off from the very last keyframe so there's a flat runway after it

const CAMERA_BASE_ZOOM: float = 0.85
const CAMERA_MIN_ZOOM: float = 0.55 # zoomed out this far at CAMERA_ZOOM_SPEED_REF and above
const CAMERA_ZOOM_SPEED_REF: float = 850.0 # px/s at which zoom reaches its minimum - raised from 500 since Flow/Chain bonuses now routinely push speed past 1000 px/s, and the old reference maxed the zoom out well before that, making the camera look identical at 500 vs 1160 despite a very different pace
const CAMERA_LOOKAHEAD_MAX: float = 260.0 # px offset toward travel direction at full speed, so blind crests on the now-long course are readable
const CAMERA_EASE: float = 0.08
const FALL_RECOVERY_MARGIN: float = 2000.0 # px below the deepest terrain point before an auto-recovery kicks in

# A rough landing already reads on the character (squash) and the HUD
# ("ROUGH" chain text), but neither of those is visible in your peripheral
# vision the way the whole screen moving is - a camera shake sells the hit
# as an actual impact. Uses Camera2D.offset (not .position) so the jolt is
# instant and separate from the eased lookahead lerp below, which would
# otherwise smooth a sharp shake into a soft, unconvincing wobble.
const MAX_LANDING_SHAKE_PX: float = 14.0 # shake amplitude on a completely mismatched (quality 0) landing; scales down to ~0 on a clean one
const CAMERA_SHAKE_DECAY_PX_PER_SEC: float = 45.0 # how fast the shake amplitude bleeds back to 0 - fast/snappy, not a lingering wobble

# Launch's symmetric counterpart to the landing shake above: a clean launch
# pops the camera briefly wider (zoom OUT, since lower Camera2D.zoom values
# show more world) to sell the "leaving the ground" moment, easing back to
# the normal speed-based zoom just as fast as it appeared. Mild by design -
# per Player.gd, a launch isn't really a "mistake" the way a bad landing is,
# so unlike the shake this only fires on good launches, not bad ones.
const MAX_LAUNCH_ZOOM_KICK: float = 0.05 # zoom units subtracted (zoomed further out) on a perfectly-matched (quality 1) launch
const CAMERA_ZOOM_KICK_DECAY_PER_SEC: float = 0.18 # how fast the kick eases back out

# A new best time already printed to the console ("NEW BEST"), which is
# useless on the user's actual platform - there's no console visible on the
# Android build, so the only in-game signal was the Best label's number
# quietly matching the Timer label, easy to miss entirely. Flashes the label
# gold with an explicit "NEW BEST" callout for a few seconds, same one-shot
# decay pattern as the landing squash/launch stretch/camera shake above.
const NEW_BEST_FLASH_DURATION: float = 2.0
const NEW_BEST_FLASH_COLOR: Color = Color(1.0, 0.85, 0.2, 1)

var _elapsed: float = 0.0
var _timer_running: bool = false
var _finished: bool = false
var _spawn_position: Vector2
var _best_time: float = -1.0 # session-only, no persistence - just gives restart-and-retry a sense of progress
var _fall_recovery_y: float = 0.0
var _camera_shake_amount: float = 0.0
var _last_seen_landing_event: int = 0
var _camera_zoom_kick: float = 0.0
var _last_seen_launch_event: int = 0
var _camera_zoom_smoothed: float = CAMERA_BASE_ZOOM # eased speed-based zoom, kept separate from camera.zoom itself so the kick (applied only to the final displayed value) never feeds back into next frame's ease source
var _new_best_flash_timer: float = 0.0


func _ready() -> void:
	var spawn_x: float = terrain.spawn_x()
	_spawn_position = Vector2(spawn_x, terrain.height_at(spawn_x) - PLAYER_GROUND_OFFSET)
	player.global_position = _spawn_position
	_fall_recovery_y = terrain.lowest_surface_y() + FALL_RECOVERY_MARGIN

	var end_x: float = terrain.course_end_x() - END_ZONE_MARGIN
	end_zone.global_position = Vector2(end_x, terrain.height_at(end_x) - END_ZONE_HEIGHT / 2.0)

	end_zone.body_entered.connect(_on_end_zone_body_entered)
	restart_button.pressed.connect(_on_restart_pressed)
	# button_down (not the .pressed click signal) fires immediately on
	# touch-down rather than after release, so a jump tap registers as
	# responsively as the joystick's own direct touch handling.
	jump_button.button_down.connect(player.jump)
	_update_timer_label()


func _process(delta: float) -> void:
	# Sustained lean off either end of the terrain can build enough speed to
	# outrun the runway/finish-straight buffers and fall past the world's
	# edge into open space (caught via a hard-reverse-lean stress test - the
	# fall is otherwise never-ending, which violates the "no unrecoverable
	# state" principle just as much as any other stuck-forever scenario
	# would). A universal Y-based catch handles this regardless of which
	# edge, or any future terrain gap, without needing a precise boundary.
	if player.position.y > _fall_recovery_y:
		_on_restart_pressed()
		return

	if not _timer_running and not _finished and joystick.get_vector().length() > 0.0:
		_timer_running = true

	if _timer_running and not _finished:
		_elapsed += delta
		_update_timer_label()

	var zone: String = terrain.zone_name_at(player.position.x)
	speed_label.text = "Speed: %.1f px/s%s" % [player.current_speed, ("  [%s]" % zone) if zone != "" else ""]
	flow_bar_fill.size.x = flow_bar_bg.size.x * clamp(player.flow, 0.0, 1.0)
	chain_label.text = _chain_text()
	_update_best_flash(delta)

	if player.landing_event_id != _last_seen_landing_event:
		_last_seen_landing_event = player.landing_event_id
		var shake: float = (1.0 - player.last_landing_quality) * MAX_LANDING_SHAKE_PX
		_camera_shake_amount = max(_camera_shake_amount, shake)
	_camera_shake_amount = max(_camera_shake_amount - CAMERA_SHAKE_DECAY_PX_PER_SEC * delta, 0.0)

	if player.launch_event_id != _last_seen_launch_event:
		_last_seen_launch_event = player.launch_event_id
		var kick: float = player.last_launch_quality * MAX_LAUNCH_ZOOM_KICK
		_camera_zoom_kick = max(_camera_zoom_kick, kick)
	_camera_zoom_kick = max(_camera_zoom_kick - CAMERA_ZOOM_KICK_DECAY_PER_SEC * delta, 0.0)

	_update_camera()


func _chain_text() -> String:
	if player.last_landing_quality < 0.0:
		return ""
	var quality: float = player.last_landing_quality
	var word: String = "PERFECT" if quality >= 0.9 else ("CLEAN" if quality >= 0.7 else ("OK" if quality >= 0.4 else "ROUGH"))
	if player.chain_count > 1:
		return "%s   Chain x%d" % [word, player.chain_count]
	return word


func _update_camera() -> void:
	var speed_t: float = clamp(player.current_speed / CAMERA_ZOOM_SPEED_REF, 0.0, 1.0)
	var target_zoom: float = lerp(CAMERA_BASE_ZOOM, CAMERA_MIN_ZOOM, speed_t)
	_camera_zoom_smoothed = lerp(_camera_zoom_smoothed, target_zoom, CAMERA_EASE)
	var displayed_zoom: float = max(_camera_zoom_smoothed - _camera_zoom_kick, CAMERA_MIN_ZOOM * 0.5)
	camera.zoom = Vector2(displayed_zoom, displayed_zoom)

	var lookahead: Vector2 = Vector2.ZERO
	if player.velocity.length() > 10.0:
		lookahead = player.velocity.normalized() * CAMERA_LOOKAHEAD_MAX * speed_t
	camera.position = camera.position.lerp(lookahead, CAMERA_EASE)

	camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _camera_shake_amount if _camera_shake_amount > 0.0 else Vector2.ZERO


func _update_timer_label() -> void:
	timer_label.text = _format_time(_elapsed)
	best_label.text = ("Best: %s" % _format_time(_best_time)) if _best_time >= 0.0 else ""


## Overrides the best-label text/color for a few seconds right after a new
## best, then hands display back to _update_timer_label()'s normal "Best:
## ..." text once the flash decays to 0 - runs every frame regardless of
## _timer_running/_finished, since the flash needs to keep animating after
## the run has already ended (there's no results screen to interrupt it).
func _update_best_flash(delta: float) -> void:
	if _new_best_flash_timer <= 0.0:
		return
	_new_best_flash_timer = max(_new_best_flash_timer - delta, 0.0)
	if _new_best_flash_timer <= 0.0:
		best_label.modulate = Color.WHITE
		_update_timer_label()
		return
	best_label.text = "NEW BEST: %s !" % _format_time(_best_time)
	best_label.modulate = NEW_BEST_FLASH_COLOR.lerp(Color.WHITE, 1.0 - _new_best_flash_timer / NEW_BEST_FLASH_DURATION)


func _format_time(t: float) -> String:
	var total_ms: int = int(round(t * 1000.0))
	var minutes: int = total_ms / 60000
	var seconds: int = (total_ms / 1000) % 60
	var ms: int = total_ms % 1000
	return "%02d:%02d.%03d" % [minutes, seconds, ms]


func _on_end_zone_body_entered(body: Node) -> void:
	if body == player and _timer_running and not _finished:
		_finished = true
		_timer_running = false
		var is_new_best: bool = _best_time < 0.0 or _elapsed < _best_time
		if is_new_best:
			_best_time = _elapsed
			_new_best_flash_timer = NEW_BEST_FLASH_DURATION
		_update_timer_label()
		print("Final time: %s (%.3f s)%s" % [_format_time(_elapsed), _elapsed, "  NEW BEST" if is_new_best else ""])


func _on_restart_pressed() -> void:
	player.reset(_spawn_position)
	camera.reset_smoothing()
	camera.offset = Vector2.ZERO
	_camera_shake_amount = 0.0
	_last_seen_landing_event = player.landing_event_id
	_camera_zoom_kick = 0.0
	_camera_zoom_smoothed = CAMERA_BASE_ZOOM
	_last_seen_launch_event = player.launch_event_id
	_new_best_flash_timer = 0.0
	best_label.modulate = Color.WHITE
	_elapsed = 0.0
	_timer_running = false
	_finished = false
	_update_timer_label()
