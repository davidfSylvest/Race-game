extends Node2D

## Procedurally builds a curved ground silhouette from keyframes instead of
## hand-placed straight ramps. Between keyframes, height is smoothstep-
## interpolated (ease in/out) rather than linear, so slopes ramp into and
## out of hills instead of meeting at sharp angle joints - real curves the
## lean/slope physics can react to smoothly.
##
## Two levels share this one script rather than duplicating all the height/
## tangent/friction/zone logic - level (1 or 2) just selects which keyframe
## list and zone layout _configure_level() loads before _build_ground()
## runs. Zones (ice/mud/boost/launch/bhop/flow) are a generic
## {type, start, end} list instead of one const pair per type, so a level
## can have as many of each kind as its layout needs (level 2 has two boost
## pads and two bhop-style corridors, level 1 has one of each).
##
## This script owns physics/collision and the course-layout data ONLY -
## everything about how the ground LOOKS (fill colors, the per-vertex
## shading gradient, the rim highlight) lives in the separate
## TerrainRenderer.gd, instantiated below once _build_ground() has the
## collision + top-curve points ready. The renderer reads _top_points
## directly rather than recomputing the curve, so visual and physics
## terrain can never desync - splitting rendering out doesn't relax that
## guarantee, it just moves "how it looks" into its own swappable file.

@export var level: int = 1 # 1 or 2 - see _configure_level()
@export var sample_spacing: float = 24.0 # world px between collision/visual sample points; smaller = smoother curve
@export var ground_thickness: float = 500.0 # how far the solid ground extends below the lowest point
@export var finish_runway: float = 1200.0 # flat ground built past the last keyframe, purely as a safety buffer - NOT counted in course_end_x() (the finish line doesn't move). Main.gd's end-zone trigger sits back from the true polygon edge by a much smaller END_ZONE_MARGIN, and at the speeds this course produces (1000+ px/s) that margin alone is under 0.2s of travel - a player who crosses the line without instantly releasing the stick (i.e. almost everyone) would run clean off the actual end of the terrain a moment later and silently trigger the fall-recovery reset, wiping a run that had just finished. Found via a headless test that kept feeding forward lean past the finish line rather than assuming a player stops the instant they cross.
@export var ice_friction_scale: float = 0.06 # fraction of normal friction loss on ice - 0.06 means ~94% less grip than normal ground
@export var mud_friction_scale: float = 6.5 # multiple of normal friction loss in mud

## Each entry: {type: "ice"/"mud"/"boost"/"launch"/"bhop"/"flow", start: float, end: float}.
## Populated per-level in _configure_level(). Checked in this same order
## wherever precedence could matter (only relevant if two zones overlap -
## e.g. deliberately never done for ice/mud/boost/launch, but flow and bhop
## sit back-to-back by design so a boundary pixel picks the first match).
var zones: Array[Dictionary] = []

## (x, y) control points, world px, Y+ is down. Flat runs happen wherever
## consecutive points share the same y; everything else curves between them.
## Populated per-level in _configure_level().
var keyframes: Array[Vector2] = []

var _top_points: PackedVector2Array = PackedVector2Array()
var _bottom_y: float = 0.0


func _ready() -> void:
	_configure_level()
	_build_ground()
	var renderer: Node2D = preload("res://scripts/TerrainRenderer.gd").new()
	renderer.name = "TerrainRenderer"
	add_child(renderer)
	renderer.build(self)


## Loads this instance's course layout. Keeping both levels' data in one
## script (rather than a second copy of every height/tangent/zone method)
## means a fix to the shared logic below can never accidentally apply to
## only one level.
func _configure_level() -> void:
	if level == 2:
		keyframes = _level_2_keyframes()
		zones = _level_2_zones()
	else:
		keyframes = _level_1_keyframes()
		zones = _level_1_zones()


func _level_1_keyframes() -> Array[Vector2]:
	return [
		Vector2(-600, 600),  # runway behind spawn, so a hard reverse lean can't run off the world
		Vector2(500, 600),   # end of flat start
		Vector2(1400, 1050), # bottom of hill 1's downhill
		Vector2(1900, 1050), # valley 1 floor
		Vector2(2900, 600),  # crest 1
		Vector2(3300, 600),  # flat top of crest 1
		# Hill 2's descent gets one roller bump partway down - a taste of the
		# chain mechanic mid-course, not just at the dedicated bhop section at
		# the very end. Widened the overall run (was a straight 1000px drop,
		# now 1400px) so inserting the bump doesn't force any segment steeper
		# than a comfortable ~45deg peak.
		Vector2(3700, 820),  # descent begins
		Vector2(3900, 760),  # roller bump (gentle, ~17deg avg - meant to be easy to chain off)
		Vector2(4500, 1150), # bottom of hill 2's downhill
		Vector2(5000, 1150), # valley 2 floor
		Vector2(5900, 700),  # crest 2
		Vector2(6300, 700),  # flat top of crest 2
		Vector2(7000, 950),  # gentle final descent (bottom of the two big hills)
		# Bhop section: a rhythmic run of bumps, sized so a fast rider can chain
		# several clean launch/land cycles in a row - the two big crests each
		# only give one real jump per run, which isn't enough to actually feel
		# the chain-streak system in action. ~100px rise over ~160px run keeps
		# the peak slope around 43deg (safely under floor_max_angle's 55deg)
		# while still being sharp enough for a fast rider to actually launch.
		Vector2(7160, 850),
		Vector2(7320, 950),
		Vector2(7480, 850),
		Vector2(7640, 950),
		Vector2(7800, 850),
		Vector2(7960, 950),
		Vector2(8120, 850),
		Vector2(8280, 950),
		Vector2(8440, 820),  # one bigger bump to close the run out
		Vector2(8620, 950),
		Vector2(9400, 950),  # finish straight
	]


func _level_1_zones() -> Array[Dictionary]:
	return [
		# Low-friction patch on valley 1's flat floor, right after hill 1's
		# downhill - Trackmania-style momentum test: much less grip means you
		# carry way more speed into the climb ahead if you managed it well
		# approaching the ice, and much less control to correct if you didn't.
		{"type": "ice", "start": 1400.0, "end": 1900.0},
		# Ice's opposite: a high-friction patch on valley 2's floor, right
		# after hill 2's downhill. Aggressively bleeds the speed you carried
		# in - tests the complementary skill of quickly re-accelerating/
		# re-aiming into the next climb instead of relying on stored momentum.
		{"type": "mud", "start": 4600.0, "end": 5000.0},
		# Terrain-triggered counterpart to the manual jump: an automatic pop
		# off the ground, no button required. Placed on crest 1's flat top
		# (2900-3300) with runway on both sides so a rider crosses it already
		# committed to forward speed and lands back on flat ground before the
		# real descent begins at 3300.
		{"type": "launch", "start": 3100.0, "end": 3200.0},
		# A Trackmania-style boost pad. First tried on crest 2's flat top
		# (right before hill 2's descent) but a headless test caught a bad
		# interaction: the extra speed sent a tangent-tracking bot into a
		# bigger arc off that descent, and the resulting worse landing angle
		# fed straight into the landing-quality mismatch penalty, eating back
		# most of the boost and making every simulated policy's time WORSE,
		# not better. Moved to the flat run after the bhop section instead,
		# where there's no more terrain to launch off before the finish.
		{"type": "boost", "start": 8700.0, "end": 8900.0},
		# The rhythmic bump run above - bounded at 8620 (where the bumps
		# actually end and the flat finish straight begins) rather than left
		# open-ended, so the finish straight doesn't cosmetically tag/color
		# as "BHOP" once it's plain flat ground.
		{"type": "bhop", "start": 7000.0, "end": 8620.0},
	]


## Level 2: roughly 2x level 1's length, built around one long uninterrupted
## "flow" gauntlet (a run of gentle rolling hills with no flat valley floors
## to break grounded contact) bracketed by two bhop-style bump corridors -
## see the flow-zone comment in _level_2_zones() for the full reasoning.
func _level_2_keyframes() -> Array[Vector2]:
	return [
		Vector2(-600, 600),  # runway behind spawn, same as level 1
		Vector2(500, 600),   # end of flat start
		Vector2(1600, 1150), # bottom of hill 1's downhill (dx=1100 dy=550, peak ~37deg)
		Vector2(2100, 1150), # valley 1 floor - ice zone
		Vector2(3300, 550),  # crest 1 (dx=1200 dy=-600, peak ~37deg)
		Vector2(3600, 550),  # flat top of crest 1 - launch pad
		Vector2(4300, 900),  # descent begins into flow corridor 1 (dx=700 dy=350, peak ~37deg)
		# Flow corridor 1: a first taste of bump-chaining, comparable in
		# density to level 1's whole bhop section but arriving much earlier -
		# level 2 wants two of these instead of level 1's one, since it's
		# meant to be a longer, harder ride overall.
		Vector2(4470, 1010),
		Vector2(4640, 900),
		Vector2(4810, 1010),
		Vector2(4980, 900),
		Vector2(5150, 1010),
		Vector2(5320, 900),
		Vector2(5490, 1010),
		Vector2(5660, 900),
		Vector2(5830, 1010),
		Vector2(6300, 1150), # settle down to valley 2 floor (dx=470 dy=140, gentle ~24deg)
		Vector2(6800, 1150), # valley 2 floor - mud zone
		Vector2(8100, 500),  # crest 2 (dx=1300 dy=-650, peak ~37deg)
		Vector2(8500, 500),  # flat top of crest 2 - boost pad #1 (widened to 400px so the
		                     # boost has real runway before the flow gauntlet's first dip,
		                     # same lesson as boost's rejected level-1 placement)
		# The flow gauntlet: six gentle rolling hills in a row (dx=700 dy=250,
		# peak ~28deg - deliberately gentler than every other slope in either
		# level), with no flat valley floor anywhere in between. Flow.gd's
		# meter builds from sustained well-aimed grounded lean and fades the
		# instant you go airborne or lose alignment - a long, continuous,
		# evenly-paced curve with nothing to interrupt grounded contact is
		# exactly the shape that lets a skilled rider hold perfect alignment
		# long enough to actually max the meter out and feel it stay there,
		# which the shorter, choppier hills+bumps of level 1 (or corridor 1
		# and 2's rhythmic launches, which zero Flow's "airborne" clause
		# every cycle) never gave enough room to do.
		Vector2(9200, 750),
		Vector2(9900, 500),
		Vector2(10600, 750),
		Vector2(11300, 500),
		Vector2(12000, 750),
		Vector2(12700, 500),
		Vector2(13400, 750),
		Vector2(14100, 500),
		Vector2(14800, 750),
		Vector2(15500, 500), # end of the flow gauntlet
		# Flow corridor 2: bigger and harder than corridor 1 (dx=170 dy=120,
		# peak ~47deg vs corridor 1's ~44deg), and longer (six full cycles
		# instead of four) - the "way harder" payoff right after the calm of
		# the flow gauntlet.
		Vector2(15670, 620),
		Vector2(15840, 500),
		Vector2(16010, 620),
		Vector2(16180, 500),
		Vector2(16350, 620),
		Vector2(16520, 500),
		Vector2(16690, 620),
		Vector2(16860, 500),
		Vector2(17030, 620),
		Vector2(17200, 500),
		Vector2(17370, 620),
		Vector2(17540, 500),
		Vector2(17900, 700),  # settle down (dx=360 dy=200, peak ~38deg)
		Vector2(18400, 750),  # nearly flat (dx=500 dy=50, peak ~8deg) - boost pad #2
		Vector2(19300, 750),  # finish straight
	]


func _level_2_zones() -> Array[Dictionary]:
	return [
		{"type": "ice", "start": 1600.0, "end": 2100.0},
		{"type": "launch", "start": 3400.0, "end": 3500.0},
		{"type": "bhop", "start": 4300.0, "end": 5830.0},
		{"type": "mud", "start": 6300.0, "end": 6800.0},
		{"type": "boost", "start": 8150.0, "end": 8300.0},
		{"type": "flow", "start": 8500.0, "end": 15500.0},
		{"type": "bhop", "start": 15500.0, "end": 17540.0},
		{"type": "boost", "start": 18500.0, "end": 18700.0},
	]


## Ground surface height at world x, following the same curve used to build
## the collision/visual so callers (spawn point, end zone) can place things
## exactly on the surface without duplicating the course layout.
func height_at(x: float) -> float:
	for i in range(keyframes.size() - 1):
		var a: Vector2 = keyframes[i]
		var b: Vector2 = keyframes[i + 1]
		if x <= b.x or i == keyframes.size() - 2:
			if is_equal_approx(a.x, b.x):
				return b.y
			var t: float = smoothstep(a.x, b.x, clamp(x, a.x, b.x))
			return lerp(a.y, b.y, t)
	return keyframes[-1].y


## Ground tangent (unit vector, always +x-ish) at world x, matching the
## exact curve height_at() traces - computed analytically (a numerical
## derivative of height_at() itself) rather than read from the collision
## polygon's per-segment normal. The physics engine's floor normal turned
## out to be genuinely noisy frame-to-frame (measured up to ~1.5deg of
## sign-flipping jitter per frame on an ordinary slope, even after
## quadrupling the polygon's sample resolution - so it isn't a segment-
## quantization artifact, something in how Godot resolves contact normals
## for a rolling CircleShape2D against a many-edge polygon each frame).
## That noise fed straight into the acceleration tangent and speed ceiling
## every frame - invisible with the old humanoid (whose tilt only reflected
## lean input, not the ground normal), but a real source of choppy movement
## once the ball's spin started tracking actual physics output. Since
## height_at() is itself perfectly smooth (every keyframe is a zero-slope
## point by construction - see the smoothstep note above), differentiating
## it directly gives an exactly-as-smooth tangent by definition, with no
## dependency on collision polygon resolution at all.
func tangent_at(x: float) -> Vector2:
	var eps: float = 2.0
	var slope: float = (height_at(x + eps) - height_at(x - eps)) / (2.0 * eps)
	return Vector2(1.0, slope).normalized()


## Roughly centered in the flat start zone, giving runway both directions.
func spawn_x() -> float:
	return (keyframes[0].x + keyframes[1].x) / 2.0


func course_end_x() -> float:
	return keyframes[-1].x


## Deepest surface point across the whole course - used by Main.gd to set
## a fall-recovery threshold well below any solid ground, so overrunning
## either end of the terrain (or any future gap) is always recoverable.
func lowest_surface_y() -> float:
	var max_y: float = -INF
	for kf in keyframes:
		max_y = max(max_y, kf.y)
	return max_y


func _first_zone_of_type_at(x: float, type: String) -> bool:
	for z in zones:
		if z.type == type and x >= z.start and x <= z.end:
			return true
	return false


## Fraction (or multiple) of normal friction loss at world x - 1.0 on plain
## ground. Queried by Player.gd every physics frame, so keep it cheap.
func friction_multiplier_at(x: float) -> float:
	if _first_zone_of_type_at(x, "ice"):
		return ice_friction_scale
	if _first_zone_of_type_at(x, "mud"):
		return mud_friction_scale
	return 1.0


## True while x is inside a boost pad - queried once per frame by Player.gd
## to edge-detect entering the zone, same idea as an on_floor transition.
func is_boost_zone_at(x: float) -> bool:
	return _first_zone_of_type_at(x, "boost")


## True while x is inside a launch pad - same edge-detection pattern as
## is_boost_zone_at above.
func is_launch_pad_at(x: float) -> bool:
	return _first_zone_of_type_at(x, "launch")


## True inside a bhop or launch-pad zone, where the whole point is that small
## bumps produce a real, separate landing/launch each time - Player.gd uses
## this to shrink floor_snap_length there so those deliberate bumps don't get
## glued flat by the larger snap needed elsewhere (see floor_snap_length_wide
## in Player.gd for why plain hills need a much larger value).
func wants_tight_floor_snap_at(x: float) -> bool:
	return _first_zone_of_type_at(x, "bhop") or _first_zone_of_type_at(x, "launch")


## Short debug tag for whichever special zone x is in, "" on plain ground -
## a HUD readout for this during feel-testing, so a speed change is never
## ambiguous between "the terrain did that" and "your technique did that."
func zone_name_at(x: float) -> String:
	for z in zones:
		if x >= z.start and x <= z.end:
			return String(z.type).to_upper()
	return ""


## Read-only access to the exact sample points the collision polygon was
## built from - TerrainRenderer (and anything else that wants to draw the
## surface) uses these directly instead of resampling height_at() itself,
## which is what guarantees the visual can never drift from the collision.
func get_top_points() -> PackedVector2Array:
	return _top_points


## The visual fill's bottom edge y - same value the collision polygon's own
## bottom corners use (see _build_ground()), computed once there rather than
## re-derived by the renderer, so the two can't drift apart either.
func get_bottom_y() -> float:
	return _bottom_y


## Builds ONLY the physics/collision ground (a StaticBody2D + one unified
## CollisionPolygon2D) and records _top_points along the way. All visual
## representation is TerrainRenderer's job - see get_top_points() above and
## the module docstring at the top of this file.
func _build_ground() -> void:
	var start_x: float = keyframes[0].x
	# The physical polygon extends finish_runway past the last keyframe as a
	# flat safety buffer (see finish_runway above) - course_end_x() still
	# returns keyframes[-1].x unchanged, so the finish line itself doesn't move.
	var end_x: float = keyframes[-1].x + finish_runway

	_top_points.clear()
	var x: float = start_x
	while x < end_x:
		_top_points.append(Vector2(x, height_at(x)))
		x += sample_spacing
	_top_points.append(Vector2(end_x, height_at(end_x)))

	var max_y: float = -INF
	for p in _top_points:
		max_y = max(max_y, p.y)
	_bottom_y = max_y + ground_thickness

	var polygon_points: PackedVector2Array = _top_points.duplicate()
	polygon_points.append(Vector2(end_x, _bottom_y))
	polygon_points.append(Vector2(start_x, _bottom_y))

	var body := StaticBody2D.new()
	body.name = "Ground"
	add_child(body)

	var collision := CollisionPolygon2D.new()
	collision.polygon = polygon_points
	body.add_child(collision)
