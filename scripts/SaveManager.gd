extends Node

## Persistent progress: best time + ghost replay per level, plus which levels
## are unlocked - the user explicitly asked for cross-session highscores and
## Trackmania-style ghost racing, which this project never had before (Main.gd
## used to keep `_best_time` as a plain session-only var, by design, since
## nothing needed it to survive a restart). This is an autoload singleton
## ("Save" in project.godot) so both level scenes share one save file instead
## of each needing its own persistence plumbing.
##
## File format is plain JSON at user://savedata.json - no encryption/versioning
## machinery, this is a single-player feel-test prototype, not a live-service
## game. A missing or corrupt save file is treated as "fresh save," not an
## error state, so a first run (or a manually-deleted save) just starts clean.

const SAVE_PATH: String = "user://savedata.json"

# Ghost frames are recorded once per physics frame (60Hz, matches the fixed
# physics step every headless test in this project already relies on - see
# CLAUDE.md's "await get_tree().physics_frame" methodology) as
# [x, y, roll_angle] triples. Storing plain arrays (not Vector2/custom
# classes) because JSON round-trips those natively with no custom
# serialization step.
var _data: Dictionary = {}


func _ready() -> void:
	_load()


## Level 1 is always unlocked; every other level needs its predecessor's
## bronze time beaten first (see Medals.gd for what "bronze" means) - the
## user's explicit Trackmania-style ask: unlock the next level by beating the
## previous one's bronze, not just by finishing it.
func is_level_unlocked(level: int) -> bool:
	if level <= 1:
		return true
	var levels: Dictionary = _data.get("levels", {})
	var entry: Dictionary = levels.get(str(level - 1), {})
	var best: float = entry.get("best_time", -1.0)
	if best < 0.0:
		return false
	return best <= Medals.bronze_time(level - 1)


func get_best_time(level: int) -> float:
	var levels: Dictionary = _data.get("levels", {})
	var entry: Dictionary = levels.get(str(level), {})
	return entry.get("best_time", -1.0)


## Returns the recorded ghost as an Array of [x, y, roll_angle] triples, or an
## empty array if this level has no best run yet.
func get_ghost(level: int) -> Array:
	var levels: Dictionary = _data.get("levels", {})
	var entry: Dictionary = levels.get(str(level), {})
	return entry.get("ghost", [])


## Call at the end of a finished run. Only overwrites the stored best
## time/ghost if this run actually beat it (or is the first one) - returns
## true when it did, so Main.gd knows whether to flash "NEW BEST" and whether
## the ghost the player just raced needs replacing for next time.
func record_result(level: int, time: float, ghost_frames: Array) -> bool:
	var levels: Dictionary = _data.get("levels", {})
	var entry: Dictionary = levels.get(str(level), {})
	var previous_best: float = entry.get("best_time", -1.0)
	if previous_best >= 0.0 and time >= previous_best:
		return false
	entry["best_time"] = time
	entry["ghost"] = ghost_frames
	levels[str(level)] = entry
	_data["levels"] = levels
	_save()
	return true


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		_data = parsed


func _save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not file:
		return
	file.store_string(JSON.stringify(_data))
	file.close()
