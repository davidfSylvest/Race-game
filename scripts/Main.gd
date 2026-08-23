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
@onready var camera: Camera2D = player.get_node("Camera2D")

const PLAYER_GROUND_OFFSET: float = 40.0 # capsule height - keeps feet at the surface, matches Player's local origin-at-feet convention
const END_ZONE_HEIGHT: float = 400.0
const END_ZONE_MARGIN: float = 100.0 # back off from the very last keyframe so there's a flat runway after it

const CAMERA_BASE_ZOOM: float = 0.85
const CAMERA_MIN_ZOOM: float = 0.55 # zoomed out this far at CAMERA_ZOOM_SPEED_REF and above
const CAMERA_ZOOM_SPEED_REF: float = 850.0 # px/s at which zoom reaches its minimum - raised from 500 since Flow/Chain bonuses now routinely push speed past 1000 px/s, and the old reference maxed the zoom out well before that, making the camera look identical at 500 vs 1160 despite a very different pace
const CAMERA_LOOKAHEAD_MAX: float = 260.0 # px offset toward travel direction at full speed, so blind crests on the now-long course are readable
const CAMERA_EASE: float = 0.08

var _elapsed: float = 0.0
var _timer_running: bool = false
var _finished: bool = false
var _spawn_position: Vector2
var _best_time: float = -1.0 # session-only, no persistence - just gives restart-and-retry a sense of progress


func _ready() -> void:
	var spawn_x: float = terrain.spawn_x()
	_spawn_position = Vector2(spawn_x, terrain.height_at(spawn_x) - PLAYER_GROUND_OFFSET)
	player.global_position = _spawn_position

	var end_x: float = terrain.course_end_x() - END_ZONE_MARGIN
	end_zone.global_position = Vector2(end_x, terrain.height_at(end_x) - END_ZONE_HEIGHT / 2.0)

	end_zone.body_entered.connect(_on_end_zone_body_entered)
	restart_button.pressed.connect(_on_restart_pressed)
	_update_timer_label()


func _process(delta: float) -> void:
	if not _timer_running and not _finished and joystick.get_vector().length() > 0.0:
		_timer_running = true

	if _timer_running and not _finished:
		_elapsed += delta
		_update_timer_label()

	speed_label.text = "Speed: %.1f px/s" % player.current_speed
	flow_bar_fill.size.x = flow_bar_bg.size.x * clamp(player.flow, 0.0, 1.0)
	chain_label.text = _chain_text()

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
	camera.zoom = camera.zoom.lerp(Vector2(target_zoom, target_zoom), CAMERA_EASE)

	var lookahead: Vector2 = Vector2.ZERO
	if player.velocity.length() > 10.0:
		lookahead = player.velocity.normalized() * CAMERA_LOOKAHEAD_MAX * speed_t
	camera.position = camera.position.lerp(lookahead, CAMERA_EASE)


func _update_timer_label() -> void:
	timer_label.text = _format_time(_elapsed)
	best_label.text = ("Best: %s" % _format_time(_best_time)) if _best_time >= 0.0 else ""


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
		_update_timer_label()
		print("Final time: %s (%.3f s)%s" % [_format_time(_elapsed), _elapsed, "  NEW BEST" if is_new_best else ""])


func _on_restart_pressed() -> void:
	player.reset(_spawn_position)
	camera.reset_smoothing()
	_elapsed = 0.0
	_timer_running = false
	_finished = false
	_update_timer_label()
