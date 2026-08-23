extends Node2D

## Procedurally builds a curved ground silhouette from keyframes instead of
## hand-placed straight ramps. Between keyframes, height is smoothstep-
## interpolated (ease in/out) rather than linear, so slopes ramp into and
## out of hills instead of meeting at sharp angle joints - real curves the
## lean/slope physics can react to smoothly.

@export var sample_spacing: float = 24.0 # world px between collision/visual sample points; smaller = smoother curve
@export var ground_thickness: float = 500.0 # how far the solid ground extends below the lowest point
@export var ground_color: Color = Color(0.5, 0.52, 0.56, 1)
@export var bhop_accent_color: Color = Color(0.78, 0.56, 0.22, 1) # marks the chain-friendly bump section so it reads as a distinct "try chaining jumps here" zone on sight
@export var ice_accent_color: Color = Color(0.75, 0.88, 0.95, 1) # pale icy blue marking the low-friction patch
@export var mud_accent_color: Color = Color(0.42, 0.32, 0.22, 1) # muddy brown marking the high-friction patch

const BHOP_SECTION_START_X: float = 7000.0 # must match the keyframe where the bhop bumps begin, below

## Low-friction patch on valley 1's flat floor, right after hill 1's
## downhill - Trackmania-style momentum test: much less grip means you
## carry way more speed into the climb ahead if you managed it well
## approaching the ice, and much less control to correct if you didn't.
const ICE_ZONE_START_X: float = 1400.0
const ICE_ZONE_END_X: float = 1900.0
@export var ice_friction_scale: float = 0.15 # fraction of normal friction loss while on the ice - 0.15 means ~85% less grip than normal ground

## Ice's opposite: a high-friction patch on valley 2's floor, right after
## hill 2's downhill. Aggressively bleeds the speed you carried in - tests
## the complementary skill of quickly re-accelerating/re-aiming into the
## next climb instead of relying on momentum you can no longer coast on.
const MUD_ZONE_START_X: float = 4600.0
const MUD_ZONE_END_X: float = 5000.0
@export var mud_friction_scale: float = 3.5 # multiple of normal friction loss while in the mud

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


## Short debug tag for whichever special zone x is in, "" on plain ground -
## a HUD readout for this during feel-testing, so a speed change is never
## ambiguous between "the terrain did that" and "your technique did that."
func zone_name_at(x: float) -> String:
	if x >= ICE_ZONE_START_X and x <= ICE_ZONE_END_X:
		return "ICE"
	if x >= MUD_ZONE_START_X and x <= MUD_ZONE_END_X:
		return "MUD"
	if x >= BHOP_SECTION_START_X:
		return "BHOP"
	return ""


func _build_ground() -> void:
	var start_x: float = keyframes[0].x
	var end_x: float = keyframes[-1].x

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
	var boundaries: Array[float] = [start_x, ICE_ZONE_START_X, ICE_ZONE_END_X, MUD_ZONE_START_X, MUD_ZONE_END_X, BHOP_SECTION_START_X, end_x]
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
