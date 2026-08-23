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
@onready var level_button: Button = %LevelButton
@onready var camera: Camera2D = player.get_node("Camera2D")

@export var time_of_day: PaletteController.Preset = PaletteController.Preset.DAY # sunrise/day/dusk - see PaletteController.gd; per-scene so Main.tscn and Level2.tscn could eventually differ, though both currently ship on DAY

const PLAYER_GROUND_OFFSET: float = 40.0 # ball diameter (2x Player.ball_radius) - keeps the ball's bottom at the surface, matches Player's local origin-at-ground-contact convention
const END_ZONE_HEIGHT: float = 400.0
const END_ZONE_MARGIN: float = 100.0 # back off from the very last keyframe so there's a flat runway after it
const FALL_RECOVERY_MARGIN: float = 2000.0 # px below the deepest terrain point before an auto-recovery kicks in

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
var _new_best_flash_timer: float = 0.0


func _ready() -> void:
	# Built here (not placed in the .tscn) and pushed to the very back of the
	# tree so it draws behind Terrain/Player - same "one script instanced by
	# both scenes" pattern Terrain.gd itself uses, so neither level's scene
	# file needs its own copy.
	var background: Node2D = preload("res://scripts/Background.gd").new()
	add_child(background)
	move_child(background, 0)

	# Subtle warm-neutral tint over the whole world-space canvas - just enough
	# to take the edge off flat gray-box color, short of anything that reads
	# as "filtered." CanvasModulate only affects its own canvas layer, so the
	# UI (a separate CanvasLayer) is untouched - the HUD stays full-contrast.
	var ambient := CanvasModulate.new()
	ambient.color = Color(1.0, 0.97, 0.91, 1.0)
	add_child(ambient)
	move_child(ambient, 1)

	# One call recolors sky/hills/ground/rim/ambient together for the chosen
	# time-of-day preset - see PaletteController.gd. terrain's TerrainRenderer
	# child already exists by this point (children ready before their parent,
	# so Terrain._ready() - which builds it - already ran before Main's own
	# _ready() body here).
	var palette_controller := PaletteController.new()
	palette_controller.preset = time_of_day
	add_child(palette_controller)
	palette_controller.setup(background, terrain.get_node("TerrainRenderer"), ambient)

	var spawn_x: float = terrain.spawn_x()
	_spawn_position = Vector2(spawn_x, terrain.height_at(spawn_x) - PLAYER_GROUND_OFFSET)
	player.global_position = _spawn_position
	_fall_recovery_y = terrain.lowest_surface_y() + FALL_RECOVERY_MARGIN

	var end_x: float = terrain.course_end_x() - END_ZONE_MARGIN
	end_zone.global_position = Vector2(end_x, terrain.height_at(end_x) - END_ZONE_HEIGHT / 2.0)

	# Swaps in the camera's whole self-contained behavior (speed zoom,
	# lookahead, landing shake, launch zoom kick, the speed-streak overlay) by
	# attaching CameraRig.gd to the EXISTING Camera2D node - see that script's
	# own doc comment for why this reads as "set_script + init," not a new
	# node. The old Camera2D's scene-configured zoom/position_smoothing are
	# harmless leftover defaults; CameraRig.gd overwrites zoom/position every
	# frame from init() onward.
	camera.set_script(preload("res://scripts/CameraRig.gd"))
	camera.init(player)

	end_zone.body_entered.connect(_on_end_zone_body_entered)
	restart_button.pressed.connect(_on_restart_pressed)
	# button_down (not the .pressed click signal) fires immediately on
	# touch-down rather than after release, so a jump tap registers as
	# responsively as the joystick's own direct touch handling.
	jump_button.button_down.connect(player.jump)
	# Not a menu screen - just a HUD button, same category as Restart/Jump,
	# that swaps to the other level's scene entirely (fresh Player/Terrain/
	# Main, no shared state) rather than trying to reconfigure Terrain live.
	level_button.text = "Level 2" if terrain.level == 1 else "Level 1"
	# Switched from the default .pressed click signal to button_down for the
	# same reason as JumpButton above: .pressed only fires if the finger lifts
	# while still over the button, so any tiny drag during a quick real-device
	# tap (much more likely on a small top-corner button than on Restart,
	# which players tap slowly and deliberately after finishing a run) can
	# silently swallow the tap. button_down fires the instant touch begins,
	# same as Jump and the joystick.
	level_button.button_down.connect(_on_level_button_pressed)
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
	# Camera behavior (speed zoom, lookahead, landing shake, launch zoom
	# kick, speed-streak overlay) is fully self-driven by CameraRig.gd once
	# init() has been called - see _ready() above. Nothing to poll here.


func _chain_text() -> String:
	if player.last_landing_quality < 0.0:
		return ""
	var quality: float = player.last_landing_quality
	var word: String = "PERFECT" if quality >= 0.9 else ("CLEAN" if quality >= 0.7 else ("OK" if quality >= 0.4 else "ROUGH"))
	if player.chain_count > 1:
		return "%s   Chain x%d" % [word, player.chain_count]
	return word


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


func _on_level_button_pressed() -> void:
	var target: String = "res://scenes/Level2.tscn" if terrain.level == 1 else "res://scenes/Main.tscn"
	get_tree().change_scene_to_file(target)


func _on_restart_pressed() -> void:
	player.reset(_spawn_position)
	camera.reset_camera()
	_new_best_flash_timer = 0.0
	best_label.modulate = Color.WHITE
	_elapsed = 0.0
	_timer_running = false
	_finished = false
	_update_timer_label()
