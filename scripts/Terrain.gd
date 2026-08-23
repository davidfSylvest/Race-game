extends Node2D

## Procedurally builds a curved ground silhouette from keyframes instead of
## hand-placed straight ramps. Between keyframes, height is smoothstep-
## interpolated (ease in/out) rather than linear, so slopes ramp into and
## out of hills instead of meeting at sharp angle joints - real curves the
## lean/slope physics can react to smoothly.

@export var sample_spacing: float = 24.0 # world px between collision/visual sample points; smaller = smoother curve
@export var ground_thickness: float = 500.0 # how far the solid ground extends below the lowest point
@export var finish_runway: float = 1200.0 # flat ground built past the last keyframe, purely as a safety buffer - NOT counted in course_end_x() (the finish line doesn't move). Main.gd's end-zone trigger sits back from the true polygon edge by a much smaller END_ZONE_MARGIN, and at the speeds this course produces (1000+ px/s) that margin alone is under 0.2s of travel - a player who crosses the line without instantly releasing the stick (i.e. almost everyone) would run clean off the actual end of the terrain a moment later and silently trigger the fall-recovery reset, wiping a run that had just finished. Found via a headless test that kept feeding forward lean past the finish line rather than assuming a player stops the instant they cross.
@export var ground_color: Color = Color(0.5, 0.52, 0.56, 1)
@export var bhop_accent_color: Color = Color(0.78, 0.56, 0.22, 1) # marks the chain-friendly bump section so it reads as a distinct "try chaining jumps here" zone on sight
@export var ice_accent_color: Color = Color(0.75, 0.88, 0.95, 1) # pale icy blue marking the low-friction patch
@export var mud_accent_color: Color = Color(0.42, 0.32, 0.22, 1) # muddy brown marking the high-friction patch
@export var boost_accent_color: Color = Color(0.95, 0.9, 0.15, 1) # electric yellow-gold marking the boost pad, distinct from every other zone color
@export var launch_pad_accent_color: Color = Color(0.3, 0.95, 0.5, 1) # vivid spring green marking the launch pad, distinct from every other zone color

const BHOP_SECTION_START_X: float = 7000.0 # must match the keyframe where the bhop bumps begin, below

## A Trackmania-style boost pad. First tried on crest 2's flat top (right
## before hill 2's descent into the roller bump) but a headless test caught
## a bad interaction: the extra speed sent a tangent-tracking bot into a
## bigger arc off that descent, and the resulting worse-than-usual landing
## angle fed straight into _apply_landing's mismatch penalty, eating back
## most of what the boost gave and making every simulated policy's overall
## time WORSE, not better - the boost mechanic worked exactly as designed,
## the placement just fed it straight into the one system that punishes
## exactly the kind of extra momentum it hands out. Moved to the flat run
## after the bhop section instead (still ahead of the actual finish
## trigger, and past x=8700 there's no more terrain to launch off before
## the flat finish straight begins) - a reward for clearing the course's
## hardest stretch with no crest/landing to punish the extra speed. Unlike
## ice/mud (continuous friction scaling, read every physics frame), this is
## a one-shot edge-triggered kick applied once per crossing - see
## Player.gd's boost_multiplier and _was_in_boost_zone.
const BOOST_ZONE_START_X: float = 8700.0
const BOOST_ZONE_END_X: float = 8900.0

## Launch pad: an automatic pop off the ground along the floor normal (same
## axis the manual jump uses), no button required - the terrain-triggered
## counterpart to Player.gd's jump() rather than another velocity-magnitude
## kick like boost. Placed on crest 1's flat top, with runway on both sides
## (the flat top itself runs 2900-3300) so a rider crosses it already
## committed to forward speed and lands back on more flat ground before the
## real descent begins at 3300 - unlike the boost pad's rejected first
## placement (see BOOST_ZONE above), the arc this adds lands on flat ground,
## not into a slope that would feed extra speed straight into
## _apply_landing's mismatch penalty. Verified with the same class of
## tangent-tracking headless bot used to validate boost's placement.
const LAUNCH_PAD_START_X: float = 3100.0
const LAUNCH_PAD_END_X: float = 3200.0

## Low-friction patch on valley 1's flat floor, right after hill 1's
## downhill - Trackmania-style momentum test: much less grip means you
## carry way more speed into the climb ahead if you managed it well
## approaching the ice, and much less control to correct if you didn't.
const ICE_ZONE_START_X: float = 1400.0
const ICE_ZONE_END_X: float = 1900.0
@export var ice_friction_scale: float = 0.06 # fraction of normal friction loss while on the ice - 0.06 means ~94% less grip than normal ground. Lowered from 0.15 after playtest feedback that the slide felt too weak to actually read as ice

## Ice's opposite: a high-friction patch on valley 2's floor, right after
## hill 2's downhill. Aggressively bleeds the speed you carried in - tests
## the complementary skill of quickly re-accelerating/re-aiming into the
## next climb instead of relying on momentum you can no longer coast on.
const MUD_ZONE_START_X: float = 4600.0
const MUD_ZONE_END_X: float = 5000.0
@export var mud_friction_scale: float = 6.5 # multiple of normal friction loss while in the mud. Raised from 3.5 after playtest feedback that it didn't slow the player down enough to actually read as mud

## (x, y) control points, world px, Y+ is down. Flat runs happen wherever
## consecutive points share the same y; everything else curves between them.
var keyframes: Array[Vector2] = [
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

var _top_points: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	_build_ground()


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


## Fraction (or multiple) of normal friction loss at world x - 1.0 on plain
## ground. Queried by Player.gd every physics frame, so keep it cheap.
func friction_multiplier_at(x: float) -> float:
	if x >= ICE_ZONE_START_X and x <= ICE_ZONE_END_X:
		return ice_friction_scale
	if x >= MUD_ZONE_START_X and x <= MUD_ZONE_END_X:
		return mud_friction_scale
	return 1.0


## True while x is inside the boost pad - queried once per frame by Player.gd
## to edge-detect entering the zone, same idea as an on_floor transition.
func is_boost_zone_at(x: float) -> bool:
	return x >= BOOST_ZONE_START_X and x <= BOOST_ZONE_END_X


## True while x is inside the launch pad - same edge-detection pattern as
## is_boost_zone_at above.
func is_launch_pad_at(x: float) -> bool:
	return x >= LAUNCH_PAD_START_X and x <= LAUNCH_PAD_END_X


## Short debug tag for whichever special zone x is in, "" on plain ground -
## a HUD readout for this during feel-testing, so a speed change is never
## ambiguous between "the terrain did that" and "your technique did that."
func zone_name_at(x: float) -> String:
	if x >= ICE_ZONE_START_X and x <= ICE_ZONE_END_X:
		return "ICE"
	if x >= MUD_ZONE_START_X and x <= MUD_ZONE_END_X:
		return "MUD"
	if x >= BOOST_ZONE_START_X and x <= BOOST_ZONE_END_X:
		return "BOOST"
	if x >= LAUNCH_PAD_START_X and x <= LAUNCH_PAD_END_X:
		return "LAUNCH"
	if x >= BHOP_SECTION_START_X:
		return "BHOP"
	return ""


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
	var bottom_y: float = max_y + ground_thickness

	var polygon_points: PackedVector2Array = _top_points.duplicate()
	polygon_points.append(Vector2(end_x, bottom_y))
	polygon_points.append(Vector2(start_x, bottom_y))

	var body := StaticBody2D.new()
	body.name = "Ground"
	add_child(body)

	var collision := CollisionPolygon2D.new()
	collision.polygon = polygon_points
	body.add_child(collision)

	# Visual is split into colored zones sharing sample points at every
	# boundary (no seam/gap) - collision above stays a single unified
	# polygon, completely unaffected by how the visual is carved up.
	var boundaries: Array[float] = [start_x, ICE_ZONE_START_X, ICE_ZONE_END_X, MUD_ZONE_START_X, MUD_ZONE_END_X, LAUNCH_PAD_START_X, LAUNCH_PAD_END_X, BOOST_ZONE_START_X, BOOST_ZONE_END_X, BHOP_SECTION_START_X, end_x]
	boundaries.sort()
	for i in range(boundaries.size() - 1):
		var seg_start: float = boundaries[i]
		var seg_end: float = boundaries[i + 1]
		if seg_end <= seg_start:
			continue
		var mid: float = (seg_start + seg_end) / 2.0
		var color: Color = ground_color
		if mid >= ICE_ZONE_START_X and mid <= ICE_ZONE_END_X:
			color = ice_accent_color
		elif mid >= MUD_ZONE_START_X and mid <= MUD_ZONE_END_X:
			color = mud_accent_color
		elif mid >= LAUNCH_PAD_START_X and mid <= LAUNCH_PAD_END_X:
			color = launch_pad_accent_color
		elif mid >= BOOST_ZONE_START_X and mid <= BOOST_ZONE_END_X:
			color = boost_accent_color
		elif mid >= BHOP_SECTION_START_X:
			color = bhop_accent_color
		_add_visual_segment(body, seg_start, seg_end, color, bottom_y)


func _add_visual_segment(body: Node, seg_start: float, seg_end: float, color: Color, bottom_y: float) -> void:
	var start_index: int = 0
	while start_index < _top_points.size() - 1 and _top_points[start_index].x < seg_start:
		start_index += 1
	var end_index: int = start_index
	while end_index < _top_points.size() - 1 and _top_points[end_index].x < seg_end:
		end_index += 1

	var points: PackedVector2Array = _top_points.slice(start_index, end_index + 1)
	points.append(Vector2(points[points.size() - 1].x, bottom_y))
	points.append(Vector2(points[0].x, bottom_y))

	var visual := Polygon2D.new()
	visual.polygon = points
	visual.color = color
	body.add_child(visual)
