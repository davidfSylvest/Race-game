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
@onready var restart_button: Button = %RestartButton

const PLAYER_GROUND_OFFSET: float = 40.0 # capsule height - keeps feet at the surface, matches Player's local origin-at-feet convention
const END_ZONE_HEIGHT: float = 400.0
const END_ZONE_MARGIN: float = 100.0 # back off from the very last keyframe so there's a flat runway after it

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

	var fall_tag: String = " [FALL]" if player.is_locked_out() else ""
	speed_label.text = "Speed: %.1f px/s%s" % [player.current_speed, fall_tag]


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
	var camera: Camera2D = player.get_node_or_null("Camera2D")
	if camera:
		camera.reset_smoothing()
	_elapsed = 0.0
	_timer_running = false
	_finished = false
	_update_timer_label()
