extends Node2D

## Visual-only replay of a level's best run - the user explicitly asked to
## "race against ghosts from the best time on each map," Trackmania-style. No
## collision, no physics: just a translucent duplicate of the ball silhouette
## that walks through a recorded array of [x, y, roll_angle] triples, one
## triple per physics frame, driven externally by Main.gd's own
## _physics_process (see the comment there for why frame-indexed playback -
## not a timer - keeps it exactly in sync with the live run, deaths included).

const RADIUS: float = 20.0 # matches Player.ball_radius
# Raised from 0.5 - at 0.5 a pale blue circle read as nearly invisible against
# this project's similarly pale-blue sky/hill palette (see Background.gd).
# 0.8 keeps it clearly translucent (still reads as "not the real ball") while
# actually being visible during a race.
const GHOST_COLOR: Color = Color(0.55, 0.8, 1.0, 0.8)
const OUTLINE_COLOR: Color = Color(0.85, 0.95, 1.0, 0.9) # bright rim so the silhouette pops even where it's near the same color as the sky behind it

var frames: Array = []
var _index: int = 0
var _active: bool = false
var _visual: Polygon2D


func _ready() -> void:
	_visual = Polygon2D.new()
	_visual.polygon = _circle_polygon(RADIUS, 16)
	_visual.color = GHOST_COLOR
	# Matches Player.gd's own Visual/CollisionShape2D local offset (0, -20):
	# Player's own position.y is the ball's GROUND-CONTACT point, not its
	# visual center - the real ball is drawn RADIUS px above it. Main.gd
	# records raw player.position.y into ghost frames, so without this same
	# offset the ghost rendered centered on the ground-contact line instead
	# of the ball's actual visual center - about half the circle sat below
	# the terrain surface, both looking "off in height" and (combined with
	# z_index below) getting hidden behind the ground fill.
	_visual.position = Vector2(0, -RADIUS)
	add_child(_visual)

	var outline := Line2D.new()
	outline.points = _circle_polygon(RADIUS, 24)
	outline.closed = true
	outline.width = 3.0
	outline.default_color = OUTLINE_COLOR
	outline.position = Vector2(0, -RADIUS)
	add_child(outline)

	visible = false
	z_index = -1 # reads behind the live player, which is the one that matters - same z the ground-contact shadow already uses successfully (Player._make_shadow()), since both sit in the open space above the terrain fill, not inside it


func load_frames(new_frames: Array) -> void:
	frames = new_frames


## Called the instant the real run's timer starts (or restarts) - resets
## playback to frame 0 so the ghost begins its lap exactly alongside the
## player's, the same way a Trackmania ghost does.
func start() -> void:
	_index = 0
	_active = frames.size() > 0
	visible = _active
	if _active:
		_apply_frame(0)


func stop() -> void:
	_active = false
	visible = false


## Advances exactly one recorded frame - call once per physics tick while the
## live run's timer is running, same cadence the recording itself uses, so a
## faster live run pulls ahead of the ghost and a slower one falls behind
## exactly as it would racing a real recorded lap.
func advance_frame() -> void:
	if not _active:
		return
	if _index >= frames.size():
		stop() # ghost finished its lap already; nothing left to show
		return
	_apply_frame(_index)
	_index += 1


func _apply_frame(idx: int) -> void:
	var frame: Array = frames[idx]
	global_position = Vector2(frame[0], frame[1])
	_visual.rotation = frame[2]


func _circle_polygon(radius: float, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments):
		var angle: float = TAU * i / segments
		pts.append(Vector2(cos(angle), sin(angle)) * radius)
	return pts
