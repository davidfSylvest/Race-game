extends Camera2D

## Fully self-contained camera behavior: speed-based zoom-out, travel-
## direction lookahead, a landing-only shake, and a launch-only zoom kick.
## Main.gd's only contact with this script is init(player) once at startup
## and reset_camera() on restart - everything else drives itself every
## frame by polling the player it was given, so camera behavior lives
## entirely in this one swappable file.
##
## Attached to the EXISTING Camera2D node at runtime (see Main.gd's
## _ready(), which calls set_script() on the Player-owned Camera2D) rather
## than replacing it with a new node - neither .tscn needs editing, and the
## node's scene-configured zoom/position_smoothing stay sane defaults if
## this script is ever swapped for a different camera treatment.

@export var base_zoom: float = 0.85
@export var min_zoom: float = 0.55 # zoomed out this far at zoom_speed_ref and above
@export var zoom_speed_ref: float = 850.0 # px/s at which zoom reaches its minimum - see git history for why this was raised from 500 once Flow/Chain routinely pushed speed well past it
@export var lookahead_max: float = 260.0 # px offset toward travel direction at full speed, so blind crests on a long course are readable
@export var ease: float = 0.08

@export_group("Landing Shake")
@export var max_landing_shake_px: float = 14.0 # shake amplitude on a completely mismatched (quality 0) landing; ~0 on a clean one - deliberately landing-only, never routine movement
@export var shake_decay_px_per_sec: float = 45.0 # fast/snappy, not a lingering wobble

@export_group("Launch Zoom Kick")
@export var max_launch_zoom_kick: float = 0.05 # zoom units subtracted (zoomed further out) on a perfectly-matched launch - mild, a launch isn't really a "mistake" the way a bad landing is, so unlike the shake this only fires on GOOD launches
@export var zoom_kick_decay_per_sec: float = 0.18

var _player: CharacterBody2D = null
var _zoom_smoothed: float = 0.0
var _shake_amount: float = 0.0
var _zoom_kick: float = 0.0
var _last_seen_landing_event: int = 0
var _last_seen_launch_event: int = 0


func init(player: CharacterBody2D) -> void:
	_player = player
	# set_script() at runtime (see Main.gd) does NOT retroactively turn on
	# _process() - Godot only auto-enables per-frame processing once, from
	# the ORIGINAL script's NOTIFICATION_READY, before this script ever
	# existed on the node. Without this line CameraRig silently never ticks -
	# caught via a headless test where speed climbed but zoom/position all
	# stayed frozen at their init() values.
	set_process(true)
	reset_camera()


func reset_camera() -> void:
	reset_smoothing()
	offset = Vector2.ZERO
	_shake_amount = 0.0
	_zoom_kick = 0.0
	_zoom_smoothed = base_zoom
	if _player:
		_last_seen_landing_event = _player.landing_event_id
		_last_seen_launch_event = _player.launch_event_id


func _process(delta: float) -> void:
	if not _player:
		return

	if _player.landing_event_id != _last_seen_landing_event:
		_last_seen_landing_event = _player.landing_event_id
		var shake: float = (1.0 - _player.last_landing_quality) * max_landing_shake_px
		_shake_amount = max(_shake_amount, shake)
	_shake_amount = max(_shake_amount - shake_decay_px_per_sec * delta, 0.0)

	if _player.launch_event_id != _last_seen_launch_event:
		_last_seen_launch_event = _player.launch_event_id
		var kick: float = _player.last_launch_quality * max_launch_zoom_kick
		_zoom_kick = max(_zoom_kick, kick)
	_zoom_kick = max(_zoom_kick - zoom_kick_decay_per_sec * delta, 0.0)

	var speed_t: float = clamp(_player.current_speed / zoom_speed_ref, 0.0, 1.0)
	var target_zoom: float = lerp(base_zoom, min_zoom, speed_t)
	_zoom_smoothed = lerp(_zoom_smoothed, target_zoom, ease)
	var displayed_zoom: float = max(_zoom_smoothed - _zoom_kick, min_zoom * 0.5)
	zoom = Vector2(displayed_zoom, displayed_zoom)

	var lookahead: Vector2 = Vector2.ZERO
	if _player.velocity.length() > 10.0:
		lookahead = _player.velocity.normalized() * lookahead_max * speed_t
	position = position.lerp(lookahead, ease)

	offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake_amount if _shake_amount > 0.0 else Vector2.ZERO
