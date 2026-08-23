extends Node2D

## Procedurally builds a curved ground silhouette from keyframes instead of
## hand-placed straight ramps. Between keyframes, height is smoothstep-
## interpolated (ease in/out) rather than linear, so slopes ramp into and
## out of hills instead of meeting at sharp angle joints - real curves the
## lean/slope physics can react to smoothly.

@export var sample_spacing: float = 24.0 # world px between collision/visual sample points; smaller = smoother curve
@export var ground_thickness: float = 500.0 # how far the solid ground extends below the lowest point
@export var ground_color: Color = Color(0.5, 0.52, 0.56, 1)

## (x, y) control points, world px, Y+ is down. Flat runs happen wherever
## consecutive points share the same y; everything else curves between them.
var keyframes: Array[Vector2] = [
	Vector2(-600, 600),  # runway behind spawn, so a hard reverse lean can't run off the world
	Vector2(500, 600),   # end of flat start
	Vector2(1400, 1050), # bottom of hill 1's downhill
	Vector2(1900, 1050), # valley 1 floor
	Vector2(2900, 600),  # crest 1
	Vector2(3300, 600),  # flat top of crest 1
	Vector2(4300, 1150), # bottom of hill 2's downhill (deeper, further out)
	Vector2(4800, 1150), # valley 2 floor
	Vector2(5700, 700),  # crest 2
	Vector2(6100, 700),  # flat top of crest 2
	Vector2(6800, 950),  # gentle final descent (bottom of the two big hills)
	# Bhop section: a rhythmic run of bumps, sized so a fast rider can chain
	# several clean launch/land cycles in a row - the two big crests each
	# only give one real jump per run, which isn't enough to actually feel
	# the chain-streak system in action. ~100px rise over ~160px run keeps
	# the peak slope around 43deg (safely under floor_max_angle's 55deg)
	# while still being sharp enough for a fast rider to actually launch.
	Vector2(6960, 850),
	Vector2(7120, 950),
	Vector2(7280, 850),
	Vector2(7440, 950),
	Vector2(7600, 850),
	Vector2(7760, 950),
	Vector2(7920, 850),
	Vector2(8080, 950),
	Vector2(8240, 820),  # one bigger bump to close the run out
	Vector2(8420, 950),
	Vector2(9200, 950),  # finish straight
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

	var visual := Polygon2D.new()
	visual.polygon = polygon_points
	visual.color = ground_color
	body.add_child(visual)
