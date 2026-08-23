extends Node
class_name PaletteController

## Applies one TimeOfDayPalette across every environment-mood surface in a
## single call - swapping the whole game's look is exactly one
## apply_preset() call, never a per-system reskin. See TimeOfDayPalette.gd
## for why gameplay-communicative colors (zone accents, ball Flow tint)
## are deliberately left untouched.
##
## class_name here is the same deliberate exception TimeOfDayPalette.gd
## documents: it's what lets Main.gd export a `PaletteController.Preset`
## dropdown in the Inspector for picking sunrise/day/dusk per-scene, without
## every other script in the project needing one too.

enum Preset { SUNRISE, DAY, DUSK }

@export var preset: Preset = Preset.DAY

var _background: Node2D = null
var _terrain_renderer: Node2D = null
var _ambient: CanvasModulate = null


func setup(background: Node2D, terrain_renderer: Node2D, ambient: CanvasModulate) -> void:
	_background = background
	_terrain_renderer = terrain_renderer
	_ambient = ambient
	apply_preset(preset)


func apply_preset(new_preset: Preset) -> void:
	preset = new_preset
	var palette: TimeOfDayPalette
	match preset:
		Preset.SUNRISE: palette = TimeOfDayPalette.sunrise()
		Preset.DUSK: palette = TimeOfDayPalette.dusk()
		_: palette = TimeOfDayPalette.day()
	apply_palette(palette)


func apply_palette(palette: TimeOfDayPalette) -> void:
	if _background:
		_background.sky_top_color = palette.sky_top
		_background.sky_horizon_color = palette.sky_horizon
		_background.far_hill_color = palette.far_hill
		_background.near_hill_color = palette.near_hill
		_background.refresh()
	if _terrain_renderer:
		_terrain_renderer.ground_color = palette.ground_color
		_terrain_renderer.rim_highlight_color = palette.rim_highlight_color
		_terrain_renderer.refresh_colors()
	if _ambient:
		_ambient.color = palette.ambient_tint
