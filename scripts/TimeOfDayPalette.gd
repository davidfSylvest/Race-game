extends Resource
class_name TimeOfDayPalette

## One named "look" for the whole game - sky/background/ground/ambient/rim
## colors bundled into a single swappable Resource, so a time-of-day or
## biome change is exactly one PaletteController.apply_palette() call,
## never N separate sprite/script reskins. This is the "one shader/system"
## the palette request asked for, in Resource form rather than a literal
## .gdshader, since every surface it touches is already a plain exported
## Color (Polygon2D fills, CanvasModulate) rather than a texture a real
## shader would need to recolor.
##
## Deliberately does NOT touch any gameplay-communicative color - zone
## accents (ice/mud/boost/launch/bhop/flow) or the ball's Flow tint. Those
## stay meaningful and consistent regardless of time of day, same reasoning
## Terrain.gd already documents for keeping "the terrain did that" vs "your
## technique did that" unambiguous - a palette is environment mood, not a
## gameplay reskin.
##
## class_name here (unlike every other script in this project) is
## deliberate: a custom Resource subtype is the one case where Godot's own
## convention is to declare one, since it's what lets other scripts type a
## field as `TimeOfDayPalette` and lets the Inspector treat it as a real
## resource type - see CLAUDE.md's Visual Presentation section for why the
## rest of the codebase doesn't use class_name.

@export var sky_top: Color = Color(0.42, 0.62, 0.88, 1)
@export var sky_horizon: Color = Color(0.8, 0.86, 0.82, 1)
@export var far_hill: Color = Color(0.64, 0.7, 0.74, 1)
@export var near_hill: Color = Color(0.5, 0.58, 0.6, 1)
@export var ground_color: Color = Color(0.5, 0.52, 0.56, 1)
@export var rim_highlight_color: Color = Color(1, 0.98, 0.85, 0.55)
@export var ambient_tint: Color = Color(1.0, 0.97, 0.91, 1.0)


## Every default above IS the "day" look - this just names it, so
## PaletteController.Preset.DAY doesn't need its own duplicated color list.
static func day() -> TimeOfDayPalette:
	return TimeOfDayPalette.new()


static func sunrise() -> TimeOfDayPalette:
	var p := TimeOfDayPalette.new()
	p.sky_top = Color(0.35, 0.32, 0.5, 1)
	p.sky_horizon = Color(0.95, 0.68, 0.45, 1)
	p.far_hill = Color(0.55, 0.5, 0.62, 1)
	p.near_hill = Color(0.42, 0.36, 0.48, 1)
	p.ground_color = Color(0.48, 0.42, 0.46, 1)
	p.rim_highlight_color = Color(1.0, 0.75, 0.45, 0.65)
	p.ambient_tint = Color(1.05, 0.92, 0.85, 1.0)
	return p


static func dusk() -> TimeOfDayPalette:
	var p := TimeOfDayPalette.new()
	p.sky_top = Color(0.14, 0.16, 0.32, 1)
	p.sky_horizon = Color(0.75, 0.4, 0.38, 1)
	p.far_hill = Color(0.3, 0.28, 0.4, 1)
	p.near_hill = Color(0.2, 0.18, 0.3, 1)
	p.ground_color = Color(0.32, 0.3, 0.38, 1)
	p.rim_highlight_color = Color(0.95, 0.55, 0.4, 0.6)
	p.ambient_tint = Color(0.95, 0.85, 0.9, 1.0)
	return p
