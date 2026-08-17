extends Node2D

## Orchestrates the run: starts the timer on first input, stops it at the
## end-zone, and drives the on-screen timer / speed debug readouts.

@onready var player: CharacterBody2D = %Player
@onready var joystick: Control = %Joystick
@onready var end_zone: Area2D = %EndZone
@onready var timer_label: Label = %TimerLabel
@onready var speed_label: Label = %SpeedLabel

var _elapsed: float = 0.0
var _timer_running: bool = false
var _finished: bool = false


func _ready() -> void:
	end_zone.body_entered.connect(_on_end_zone_body_entered)
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
		print("Final time: %s (%.3f s)" % [_format_time(_elapsed), _elapsed])
