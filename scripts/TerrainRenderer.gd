extends Node2D

## Owns everything about how the ground LOOKS - fill colors, the per-vertex
## shading gradient, the rim highlight - as a separate, swappable system from
## Terrain.gd's physics/collision. build(terrain) reads terrain.get_top_points()
## directly (the exact array the collision polygon was built from) rather than
## resampling height_at() itself, so visual and physics terrain can never
## desync just because rendering now lives in its own file.
##
## A Polygon2D silhouette fill against the sky (see Background.gd) is the
## whole visual language here - no sprites, no texture assets. Swapping this
## script for a different one (a shader-based fill, a tilemap-look renderer,
## whatever) only requires it expose the same build(terrain) entry point;
## nothing else in the game reaches into terrain visuals directly.

@export var ground_color: Color = Color(0.5, 0.52, 0.56, 1)
@export var bhop_accent_color: Color = Color(0.78, 0.56, 0.22, 1) # marks a chain-friendly bump section so it reads as a distinct "try chaining jumps here" zone on sight
@export var ice_accent_color: Color = Color(0.75, 0.88, 0.95, 1) # pale icy blue marking a low-friction patch
@export var mud_accent_color: Color = Color(0.42, 0.32, 0.22, 1) # muddy brown marking a high-friction patch
@export var boost_accent_color: Color = Color(0.95, 0.9, 0.15, 1) # electric yellow-gold marking a boost pad, distinct from every other zone color
@export var launch_pad_accent_color: Color = Color(0.3, 0.95, 0.5, 1) # vivid spring green marking a launch pad, distinct from every other zone color
@export var flow_accent_color: Color = Color(0.55, 0.35, 0.85, 1) # soft violet marking level 2's sustained rolling-hills gauntlet - purely a "you're in the zone" callout, no gameplay effect of its own

@export_group("Grapple Points")
@export var grapple_point_color: Color = Color(0.25, 0.95, 0.95, 1) # vivid cyan, distinct from every zone accent above - matches Player.gd's grapple_rope_color so it's obvious the rope and the point it's attached to are the same thing
@export var grapple_point_radius: float = 14.0

@export_group("Ground Shading")
@export var top_edge_lighten: float = 0.22 # how much brighter the top (sunlit) curve vertices are than the flat zone color - baked as Polygon2D per-vertex colors, no shader needed, so it's cheap on mobile and works with every zone color automatically
@export var bottom_edge_darken: float = 0.4 # how much darker the bottom (shadowed/buried) vertices are than the flat zone color
@export var rim_highlight_color: Color = Color(1, 0.98, 0.85, 0.55) # warm, translucent - drawn as a single Line2D tracing the whole course's surface, like sunlight catching the very top edge
@export var rim_highlight_width: float = 5.0

var _terrain: Node2D = null
var _body: Node = null # holds every visual node this script creates, so refresh_colors() can tear down and rebuild without touching Terrain's own collision body


func build(terrain: Node2D) -> void:
	_terrain = terrain
	_rebuild()


## Re-fills every zone segment and the rim from the CURRENT color exports
## without touching Terrain's collision at all - PaletteController calls
## this after changing this node's *_accent_color/ground_color exports on a
## time-of-day/biome swap, so a palette change is just "recolor and rebuild
## the fill," never a geometry rebuild.
func refresh_colors() -> void:
	if _terrain:
		_rebuild()


func _rebuild() -> void:
	# Synchronous removal, not queue_free(): refresh_colors() can run again
	# in the same frame _rebuild() first ran (Main._ready() applies the
	# initial time-of-day preset right after Terrain._ready() already built
	# this once) - queue_free() defers actual removal, so the old node was
	# still present when the new one tried to claim the same name, and Godot
	# silently renamed it to avoid the collision. Caught via a headless test
	# that couldn't find "GroundVisual" by name even though a visual body
	# clearly existed under a different auto-generated name.
	if _body:
		remove_child(_body)
		_body.free()
	_body = Node2D.new()
	_body.name = "GroundVisual"
	add_child(_body)

	var top_points: PackedVector2Array = _terrain.get_top_points()
	var bottom_y: float = _terrain.get_bottom_y()
	var zones: Array = _terrain.zones
	var gaps: Array = _terrain.gaps if "gaps" in _terrain else []

	var start_x: float = top_points[0].x
	var end_x: float = top_points[-1].x

	# Split into colored zones sharing sample points at every boundary (no
	# seam/gap between adjacent COLORS) AND at every gap edge - a gap is a
	# real hole, not a color, so any segment landing inside one is skipped
	# entirely rather than filled, leaving the Background visible through it.
	# Terrain's own collision polygon is carved out the same way in
	# Terrain._build_ground(), independently of this file.
	var boundaries: Array[float] = [start_x, end_x]
	for z in zones:
		boundaries.append(z.start)
		boundaries.append(z.end)
	for g in gaps:
		boundaries.append(g.start)
		boundaries.append(g.end)
	boundaries.sort()
	for i in range(boundaries.size() - 1):
		var seg_start: float = boundaries[i]
		var seg_end: float = boundaries[i + 1]
		if seg_end <= seg_start:
			continue
		var mid: float = (seg_start + seg_end) / 2.0
		if _terrain.is_gap_at(mid):
			continue
		var color: Color = ground_color
		for z in zones:
			if mid >= z.start and mid <= z.end:
				color = _zone_color(z.type)
				break
		_add_visual_segment(top_points, seg_start, seg_end, color, bottom_y)
		# The rim highlight has to stop at gap edges too, for the same reason
		# the fill does - one Line2D per contiguous solid stretch instead of
		# a single line for the whole course.
		_add_rim_segment(top_points, seg_start, seg_end)

	_add_grapple_markers()


## A ring + center dot at each grapple point, plus a thin translucent guide
## line down to the ground so a point floating in open air still reads as
## anchored to the course rather than randomly placed - the same visual
## language as the ground-fill's rim highlight, just for a point instead of
## a curve. Rebuilt alongside everything else in _rebuild() (including on a
## palette refresh_colors() call), so it never desyncs from the zone fill.
func _add_grapple_markers() -> void:
	if not ("grapple_points" in _terrain):
		return
	for point in _terrain.grapple_points:
		var ring := Line2D.new()
		var ring_points := PackedVector2Array()
		var segments: int = 20
		for i in range(segments):
			var angle: float = TAU * i / segments
			ring_points.append(point + Vector2(cos(angle), sin(angle)) * grapple_point_radius)
		ring.points = ring_points
		ring.closed = true
		ring.width = 3.0
		ring.default_color = grapple_point_color
		_body.add_child(ring)

		var dot := Polygon2D.new()
		var dot_points := PackedVector2Array()
		for i in range(12):
			var angle: float = TAU * i / 12
			dot_points.append(point + Vector2(cos(angle), sin(angle)) * (grapple_point_radius * 0.35))
		dot.polygon = dot_points
		dot.color = grapple_point_color
		_body.add_child(dot)

		var ground_y: float = _terrain.height_at(point.x)
		if ground_y > point.y:
			var pole := Line2D.new()
			pole.points = PackedVector2Array([point, Vector2(point.x, ground_y)])
			pole.width = 2.0
			pole.default_color = Color(grapple_point_color.r, grapple_point_color.g, grapple_point_color.b, 0.35)
			_body.add_child(pole)


func _zone_color(type: String) -> Color:
	match type:
		"ice": return ice_accent_color
		"mud": return mud_accent_color
		"boost": return boost_accent_color
		"launch": return launch_pad_accent_color
		"bhop": return bhop_accent_color
		"flow": return flow_accent_color
		_: return ground_color


## Shared by _add_visual_segment/_add_rim_segment: the slice of top_points
## framing [seg_start, seg_end] (nearest existing samples, not necessarily
## exact - same sample_spacing-scale slop the zone-color system already
## accepted before gaps existed).
func _slice_top_points(top_points: PackedVector2Array, seg_start: float, seg_end: float) -> PackedVector2Array:
	var start_index: int = 0
	while start_index < top_points.size() - 1 and top_points[start_index].x < seg_start:
		start_index += 1
	var end_index: int = start_index
	while end_index < top_points.size() - 1 and top_points[end_index].x < seg_end:
		end_index += 1
	return top_points.slice(start_index, end_index + 1)


func _add_rim_segment(top_points: PackedVector2Array, seg_start: float, seg_end: float) -> void:
	var rim := Line2D.new()
	rim.points = _slice_top_points(top_points, seg_start, seg_end)
	rim.width = rim_highlight_width
	rim.default_color = rim_highlight_color
	rim.joint_mode = Line2D.LINE_JOINT_ROUND
	rim.begin_cap_mode = Line2D.LINE_CAP_ROUND
	rim.end_cap_mode = Line2D.LINE_CAP_ROUND
	rim.antialiased = true
	_body.add_child(rim)


func _add_visual_segment(top_points: PackedVector2Array, seg_start: float, seg_end: float, color: Color, bottom_y: float) -> void:
	var points: PackedVector2Array = _slice_top_points(top_points, seg_start, seg_end)
	var top_point_count: int = points.size()
	points.append(Vector2(points[points.size() - 1].x, bottom_y))
	points.append(Vector2(points[0].x, bottom_y))

	# Per-vertex colors fake a "lit from directly above" gradient - lighter on
	# the visible top curve, darker toward the buried bottom edge - cheap
	# (baked once here, no shader) and works with any zone's base color
	# automatically. Uniform `color` is left white so it doesn't double-tint
	# on top of these.
	var vertex_colors: PackedColorArray = PackedColorArray()
	vertex_colors.resize(points.size())
	var lit: Color = color.lightened(top_edge_lighten)
	var shaded: Color = color.darkened(bottom_edge_darken)
	for i in range(points.size()):
		vertex_colors[i] = lit if i < top_point_count else shaded

	var visual := Polygon2D.new()
	visual.polygon = points
	visual.vertex_colors = vertex_colors
	_body.add_child(visual)
