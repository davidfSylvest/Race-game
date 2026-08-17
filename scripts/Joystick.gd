extends Control

## Fixed-position virtual joystick, bottom-left of screen.
## Reports deflection as a 2D vector: length 0.0-1.0 is lean magnitude,
## direction is lean angle. Supports touch (primary) and mouse (editor testing).

@export var base_radius: float = 90.0
@export var knob_radius: float = 38.0
@export var deadzone: float = 0.08
@export var activation_radius_multiplier: float = 1.5 # how far outside the visual base a touch can still grab the stick

const MOUSE_SENTINEL: int = -2

var _touch_index: int = -1
var _knob_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)


func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if _touch_index == -1 and _within_activation(event.position):
			_touch_index = event.index
			_update_knob(event.position)
			queue_redraw()
	elif event.index == _touch_index:
		_reset()


func _handle_drag(event: InputEventScreenDrag) -> void:
	if event.index == _touch_index:
		_update_knob(event.position)
		queue_redraw()


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.pressed:
		if _touch_index == -1 and _within_activation(event.position):
			_touch_index = MOUSE_SENTINEL
			_update_knob(event.position)
			queue_redraw()
	elif _touch_index == MOUSE_SENTINEL:
		_reset()


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _touch_index == MOUSE_SENTINEL:
		_update_knob(event.position)
		queue_redraw()


func _reset() -> void:
	_touch_index = -1
	_knob_offset = Vector2.ZERO
	queue_redraw()


func _within_activation(global_pos: Vector2) -> bool:
	var center: Vector2 = global_position + size / 2.0
	return global_pos.distance_to(center) <= base_radius * activation_radius_multiplier


func _update_knob(global_pos: Vector2) -> void:
	var center: Vector2 = global_position + size / 2.0
	var d: Vector2 = global_pos - center
	if d.length() > base_radius:
		d = d.normalized() * base_radius
	_knob_offset = d


## Deflection vector: magnitude 0.0-1.0 (deadzone-remapped), angle = lean direction.
func get_vector() -> Vector2:
	var mag: float = _knob_offset.length() / base_radius
	if mag < deadzone:
		return Vector2.ZERO
	var remapped: float = clamp((mag - deadzone) / (1.0 - deadzone), 0.0, 1.0)
	return _knob_offset.normalized() * remapped


func _draw() -> void:
	var center: Vector2 = size / 2.0
	draw_circle(center, base_radius, Color(1, 1, 1, 0.12))
	draw_arc(center, base_radius, 0, TAU, 48, Color(1, 1, 1, 0.35), 3.0, true)
	draw_circle(center + _knob_offset, knob_radius, Color(1, 1, 1, 0.55))
