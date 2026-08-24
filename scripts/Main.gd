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
@onready var _event_label: Label = _make_event_label()

@export var time_of_day: PaletteController.Preset = PaletteController.Preset.DAY # sunrise/day/dusk - see PaletteController.gd; per-scene so Main.tscn and Level2.tscn could eventually differ, though both currently ship on DAY

const PLAYER_GROUND_OFFSET: float = 40.0 # ball diameter (2x Player.ball_radius) - keeps the ball's bottom at the surface, matches Player's local origin-at-ground-contact convention
const END_ZONE_HEIGHT: float = 400.0
const END_ZONE_MARGIN: float = 100.0 # back off from the very last keyframe so there's a flat runway after it
const FALL_RECOVERY_MARGIN: float = 2000.0 # px below the deepest terrain point before an auto-recovery kicks in

# Total level count, and the level->scene naming convention (level 1 lives in
# Main.tscn for historical reasons - it predates every other level - every
# level after it is "res://scenes/Level%d.tscn"). LevelButton used to be a
# hardcoded 2-level toggle (a straight swap between "the other level"); that
# broke the instant a 3rd level existed, since pressing it from Level 2 would
# incorrectly go back to Level 1 instead of forward to Level 3. Generalized to
# cycle forward through all N levels, wrapping back to 1 after the last -
# bump TOTAL_LEVELS as each new level is added.
const TOTAL_LEVELS: int = 3

# A new best time already printed to the console ("NEW BEST"), which is
# useless on the user's actual platform - there's no console visible on the
# Android build, so the only in-game signal was the Best label's number
# quietly matching the Timer label, easy to miss entirely. Flashes the label
# gold with an explicit "NEW BEST" callout for a few seconds, same one-shot
# decay pattern as the landing squash/launch stretch/camera shake above.
const NEW_BEST_FLASH_DURATION: float = 2.0
const NEW_BEST_FLASH_COLOR: Color = Color(1.0, 0.85, 0.2, 1)

# The user explicitly asked for the game to be more punishing: missing a
# terrain gap's jump (or running off the world edge, the old reverse-lean
# case) is now death, not a shrug-and-walk-back. Death sends the player back
# to their last checkpoint rather than all the way to spawn - the whole
# point of a checkpoint - and deliberately does NOT reset the run timer or
# best-time state the way the explicit Restart button does, so losing time
# to a death is itself part of the punishment, not something death forgives.
const DEATH_FLASH_DURATION: float = 1.6
const DEATH_FLASH_COLOR: Color = Color(0.95, 0.25, 0.2, 1)
const CHECKPOINT_FLASH_DURATION: float = 1.2
const CHECKPOINT_FLASH_COLOR: Color = Color(0.35, 0.9, 0.55, 1)

# Trackmania-style level gating: the user explicitly asked for later levels
# to require beating the previous level's bronze time first (see Medals.gd/
# SaveManager.gd). Reuses the same one-shot event banner CHECKPOINT/DIED
# already use rather than adding a whole new UI element for one message.
const LOCKED_FLASH_DURATION: float = 2.0
const LOCKED_FLASH_COLOR: Color = Color(0.75, 0.75, 0.8, 1)

var _elapsed: float = 0.0
var _timer_running: bool = false
var _finished: bool = false
var _spawn_position: Vector2
var _best_time: float = -1.0 # loaded from SaveManager in _ready() - persistent across restarts/relaunches now, since the user explicitly asked for cross-session highscores (this used to be session-only by design; see "Persistence, Ghosts, and Level Unlocks" in CLAUDE.md for why that changed)
var _fall_recovery_y: float = 0.0
var _new_best_flash_timer: float = 0.0
var _last_checkpoint_position: Vector2
var _next_checkpoint_index: int = 0 # index into terrain.checkpoints of the next one still to claim
var _event_flash_timer: float = 0.0
var _event_flash_duration: float = 1.0 # the duration passed to the most recent _show_event() call, needed to compute the fade fraction in _update_event_flash()

# Ghost racing (see Ghost.gd/SaveManager.gd): _ghost_recording captures this
# run's [x, y, roll_angle] every physics frame while the timer is running;
# _ghost plays back the current best run's recording, one frame per physics
# tick, in lockstep with recording so a faster/slower live run naturally
# pulls ahead of or falls behind the ghost exactly like racing a real lap.
var _ghost: Node2D = null
var _ghost_recording: Array = []


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
	_last_checkpoint_position = _spawn_position
	_fall_recovery_y = terrain.lowest_surface_y() + FALL_RECOVERY_MARGIN

	# Persistent highscore + ghost - loaded once here rather than kept
	# session-only, since the user explicitly asked to race against "ghosts
	# from the best time on each map" across sessions, not just within one.
	_best_time = SaveManager.get_best_time(terrain.level)
	var ghost_frames: Array = SaveManager.get_ghost(terrain.level)
	if not ghost_frames.is_empty():
		_ghost = preload("res://scripts/Ghost.gd").new()
		add_child(_ghost)
		_ghost.load_frames(ghost_frames)

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
	_update_level_button_label()
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
	# edge into open space (caught via a hard-reverse-lean stress test), or
	# the player can miss a terrain gap's jump and fall straight through it -
	# both are now death rather than an instant no-cost reset, since the user
	# explicitly asked for missing a jump to actually cost something. One
	# Y-based catch handles both causes (and any future terrain gap) without
	# needing a precise per-hazard boundary.
	if player.position.y > _fall_recovery_y:
		_on_death()
		return

	if not _timer_running and not _finished and joystick.get_vector().length() > 0.0:
		_timer_running = true
		_ghost_recording.clear()
		if _ghost:
			_ghost.start()

	if _timer_running and not _finished:
		_elapsed += delta
		_update_timer_label()

	# Checkpoints only move forward and only while a run is actually in
	# progress - claiming one after finishing (while still coasting through
	# the runway) or before the timer has even started would be meaningless.
	if _timer_running and not _finished:
		_check_checkpoints()

	var zone: String = terrain.zone_name_at(player.position.x)
	speed_label.text = "Speed: %.1f px/s%s" % [player.current_speed, ("  [%s]" % zone) if zone != "" else ""]
	flow_bar_fill.size.x = flow_bar_bg.size.x * clamp(player.flow, 0.0, 1.0)
	chain_label.text = _chain_text()
	_update_best_flash(delta)
	_update_event_flash(delta)
	# Camera behavior (speed zoom, lookahead, landing shake, launch zoom
	# kick, speed-streak overlay) is fully self-driven by CameraRig.gd once
	# init() has been called - see _ready() above. Nothing to poll here.


## Ghost recording/playback runs on the physics tick, not _process's variable
## frame rate - recording happens here (not in _process) so a saved run's
## frame count always means exactly one recorded sample per physics step,
## matching the fixed cadence CLAUDE.md's own headless testing methodology
## already relies on (see "await get_tree().physics_frame"). This keeps
## playback speed-independent of real framerate on whatever device the ghost
## is later watched on. Deliberately does NOT reset on death: neither
## `_elapsed` nor the ghost's frame index resets when the player dies (see
## _on_death()), so the ghost and the live timer stay in lockstep through a
## death exactly the way they do through the rest of the run.
func _physics_process(_delta: float) -> void:
	if _timer_running and not _finished:
		_ghost_recording.append([player.position.x, player.position.y, player.visual.rotation])
		if _ghost:
			_ghost.advance_frame()


## Advances the respawn point the moment the player passes the next
## uncollected checkpoint x - forward progress only (terrain.checkpoints is
## authored in course order), so there's no way to "bank" a checkpoint by
## drifting backward and forward across it repeatedly.
func _check_checkpoints() -> void:
	if not ("checkpoints" in terrain) or _next_checkpoint_index >= terrain.checkpoints.size():
		return
	var next_x: float = terrain.checkpoints[_next_checkpoint_index]
	if player.position.x >= next_x:
		_last_checkpoint_position = Vector2(next_x, terrain.height_at(next_x) - PLAYER_GROUND_OFFSET)
		_next_checkpoint_index += 1
		_show_event("CHECKPOINT", CHECKPOINT_FLASH_COLOR, CHECKPOINT_FLASH_DURATION)


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
	if _best_time >= 0.0:
		var medal: String = Medals.medal_for(terrain.level, _best_time)
		best_label.text = "Best: %s%s" % [_format_time(_best_time), ("  [%s]" % medal) if medal != "" else ""]
	else:
		best_label.text = ""


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


## Small centered banner for one-shot events the player needs an explicit
## reason for (a checkpoint claimed, a death/respawn) - built here rather
## than placed in either .tscn, same "extra HUD element via code" pattern as
## the rest of this session's additions. Lives in the UI CanvasLayer (found
## via an existing HUD node's parent, not a new unique name) so it sits
## above gameplay and is unaffected by the world-space CanvasModulate tint.
func _make_event_label() -> Label:
	var label := Label.new()
	label.anchor_left = 0.5
	label.anchor_right = 0.5
	label.offset_left = -220.0
	label.offset_right = 220.0
	label.offset_top = 200.0
	label.offset_bottom = 240.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 26)
	label.modulate = Color(1, 1, 1, 0)
	timer_label.get_parent().add_child(label)
	return label


func _show_event(text: String, color: Color, duration: float) -> void:
	_event_label.text = text
	_event_flash_duration = duration
	_event_flash_timer = duration
	_event_label.modulate = color


## Same one-shot decay pattern as the landing squash/launch stretch/camera
## shake elsewhere - fades the banner's alpha to 0 over its own duration
## (checkpoint and death use different lengths) rather than lerping to
## white like the NEW BEST flash, since this is meant to disappear
## entirely, not hand off to a permanent label underneath it.
func _update_event_flash(delta: float) -> void:
	if _event_flash_timer <= 0.0:
		return
	_event_flash_timer = max(_event_flash_timer - delta, 0.0)
	var color: Color = _event_label.modulate
	color.a = _event_flash_timer / _event_flash_duration
	_event_label.modulate = color
	if _event_flash_timer <= 0.0:
		_event_label.text = ""


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
		# SaveManager is the source of truth for "is this actually a new
		# best" (it refuses to overwrite a better stored time) - trusting its
		# return value rather than comparing to the in-memory _best_time here
		# keeps the two from ever disagreeing.
		var is_new_best: bool = SaveManager.record_result(terrain.level, _elapsed, _ghost_recording)
		if is_new_best:
			_best_time = _elapsed
			_new_best_flash_timer = NEW_BEST_FLASH_DURATION
			# Next attempt should race against the run that just finished,
			# not the old one it just beat.
			if _ghost:
				_ghost.load_frames(_ghost_recording.duplicate())
			else:
				_ghost = preload("res://scripts/Ghost.gd").new()
				add_child(_ghost)
				_ghost.load_frames(_ghost_recording.duplicate())
			_update_level_button_label() # this level's medal/unlock state may have just changed
		_update_timer_label()
		print("Final time: %s (%.3f s)%s" % [_format_time(_elapsed), _elapsed, "  NEW BEST" if is_new_best else ""])


## Level 1 lives in Main.tscn (predates the level-scene naming convention);
## every level after it follows "res://scenes/Level%d.tscn".
static func _scene_path_for_level(level: int) -> String:
	if level <= 1:
		return "res://scenes/Main.tscn"
	return "res://scenes/Level%d.tscn" % level


## Labels the button with the NEXT level's number (cycling back to 1 after
## the last one), plus a lock marker if that level isn't unlocked yet - a real
## player needs this to know the button won't just be a level swap right now,
## without needing a whole level-select menu screen to communicate it (see
## CLAUDE.md's minimalism stance on menus).
func _update_level_button_label() -> void:
	var target_level: int = (terrain.level % TOTAL_LEVELS) + 1
	var label: String = "Level %d" % target_level
	if not SaveManager.is_level_unlocked(target_level):
		label += " (Locked)"
	level_button.text = label


## Not a menu screen - just a HUD button, same category as Restart/Jump, that
## swaps to the next level's scene entirely (fresh Player/Terrain/Main, no
## shared state) rather than trying to reconfigure Terrain live - unless that
## level is locked, in which case the swap is refused and the existing event
## banner (used elsewhere for CHECKPOINT/DIED) explains why instead, showing
## the bronze time still needed - the user's explicit Trackmania-style ask
## ("levels unlocked by beating the bronze time") needs a real gate, not just
## a cosmetic label. Cycles forward through all TOTAL_LEVELS rather than
## toggling between two, so this scales to however many levels exist.
func _on_level_button_pressed() -> void:
	var target_level: int = (terrain.level % TOTAL_LEVELS) + 1
	if not SaveManager.is_level_unlocked(target_level):
		_show_event("LOCKED - beat %s on Level %d" % [_format_time(Medals.bronze_time(target_level - 1)), target_level - 1], LOCKED_FLASH_COLOR, LOCKED_FLASH_DURATION)
		return
	get_tree().change_scene_to_file(_scene_path_for_level(target_level))


## Falling off the world edge or missing a gap's jump - see _process()'s
## fall-recovery check. Deliberately lighter than _on_restart_pressed():
## sends the player back to their last checkpoint (spawn if none claimed
## yet) but leaves the run timer, best-time state, and checkpoint progress
## alone, so the lost time itself is part of the punishment rather than
## something a death wipes clean.
func _on_death() -> void:
	player.reset(_last_checkpoint_position)
	camera.reset_camera()
	_show_event("DIED - RESPAWNED", DEATH_FLASH_COLOR, DEATH_FLASH_DURATION)


func _on_restart_pressed() -> void:
	player.reset(_spawn_position)
	camera.reset_camera()
	_last_checkpoint_position = _spawn_position
	_next_checkpoint_index = 0
	_ghost_recording.clear()
	if _ghost:
		_ghost.stop() # will start() again from frame 0 once the next run's timer starts, same as the live run itself resetting to the spawn line
	_new_best_flash_timer = 0.0
	_event_flash_timer = 0.0
	_event_label.text = ""
	best_label.modulate = Color.WHITE
	_elapsed = 0.0
	_timer_running = false
	_finished = false
	_update_timer_label()
