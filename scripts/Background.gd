extends Node2D

## Purely cosmetic backdrop: a screen-fixed sky gradient (always covers the
## viewport regardless of camera zoom/position, so it's a CanvasLayer rather
## than a world-space node) plus two ParallaxLayer rows of distant hill
## silhouettes for a sense of depth as the camera travels the length of the
## course. No collision, no gameplay effect. Built once here and instanced
## by Main.gd for both levels - same "one script, every scene" pattern
## Terrain.gd already uses for its own procedural visuals.

@export var sky_top_color: Color = Color(0.42, 0.62, 0.88, 1)
@export var sky_horizon_color: Color = Color(0.8, 0.86, 0.82, 1)
@export var far_hill_color: Color = Color(0.64, 0.7, 0.74, 1)
@export var near_hill_color: Color = Color(0.5, 0.58, 0.6, 1)

const TILE_WIDTH: float = 2400.0 # hill silhouettes repeat seamlessly on this period (see _make_hill_layer)
const SKY_MARGIN: float = 500.0 # sky rect overshoots the 1280x720 default viewport by this much on every side, so it still covers a differently-sized/aspect-ratio device window


func _ready() -> void:
	_rebuild()


## Rebuilds the sky/hills from the CURRENT color exports - PaletteController
## calls this after changing sky_top_color/etc. on a time-of-day/biome swap.
## Geometry is identical every time (only the exported colors change), so a
## full rebuild is cheap and only ever happens on a preset switch, never
## per-frame.
func refresh() -> void:
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	add_child(_make_sky())
	# Two layers at different motion_scale for parallax depth - the far layer
	# barely drifts as the camera moves, the near layer drifts more, so they
	# visibly separate instead of reading as one flat backdrop.
	add_child(_make_hill_layer(far_hill_color, 260.0, Vector2(0.12, 0.12), 520.0, 3, -2))
	add_child(_make_hill_layer(near_hill_color, 360.0, Vector2(0.22, 0.2), 620.0, 2, -1))


func _make_sky() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = -10
	var sky := Polygon2D.new()
	var w: float = 1280.0 + SKY_MARGIN * 2.0
	var h: float = 720.0 + SKY_MARGIN * 2.0
	sky.polygon = PackedVector2Array([
		Vector2(-SKY_MARGIN, -SKY_MARGIN), Vector2(w - SKY_MARGIN, -SKY_MARGIN),
		Vector2(w - SKY_MARGIN, h - SKY_MARGIN), Vector2(-SKY_MARGIN, h - SKY_MARGIN),
	])
	sky.vertex_colors = PackedColorArray([sky_top_color, sky_top_color, sky_horizon_color, sky_horizon_color])
	layer.add_child(sky)
	return layer


## harmonic_count summed sine waves (decreasing amplitude per harmonic) give
## an organic, non-repetitive-looking rolling silhouette within one tile -
## periodic in x by construction (sin(h * TAU * x/TILE_WIDTH) is exactly
## equal at x=0 and x=TILE_WIDTH for any integer h), so ParallaxLayer's
## motion_mirroring can tile it forever with no visible seam.
func _make_hill_layer(color: Color, base_y: float, motion_scale: Vector2, amplitude: float, harmonic_count: int, z: int) -> ParallaxBackground:
	var bg := ParallaxBackground.new()
	var pl := ParallaxLayer.new()
	pl.motion_scale = motion_scale
	pl.motion_mirroring = Vector2(TILE_WIDTH, 0)

	var hill := Polygon2D.new()
	var points := PackedVector2Array()
	var steps: int = 48
	for i in range(steps + 1):
		var x: float = TILE_WIDTH * i / float(steps)
		var y: float = base_y
		for h in range(1, harmonic_count + 1):
			y -= (amplitude / h) * sin(TAU * h * x / TILE_WIDTH + h * 1.7)
		points.append(Vector2(x, y))
	points.append(Vector2(TILE_WIDTH, base_y + 900.0))
	points.append(Vector2(0.0, base_y + 900.0))
	hill.polygon = points
	hill.color = color
	hill.z_index = z

	pl.add_child(hill)
	bg.add_child(pl)
	return bg
