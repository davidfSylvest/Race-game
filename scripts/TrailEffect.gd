extends Line2D

## Speed is the ONLY "juice" signal in a sprite-less, silhouette-based game
## like this one, so the motion trail is deliberately the most legible
## visual here: a ribbon through the ball's own recent world positions,
## sampled once per physics frame via update(). Length is a free side effect
## of speed itself - a faster ball simply covers more world distance between
## samples, so the ribbon visibly stretches with no separate "how long
## should this be" logic. Width and alpha are the only things this script
## actively scales with speed.
##
## A completely standalone system: nothing outside this file knows how the
## trail is drawn, and Player.gd's only contact with it is update()/clear().
## Swap the whole visual technique (GPUParticles2D, a different curve shape)
## by rewriting this file alone - the two calling sites never change.
##
## top_level = true (below) lets this live as a child of Player for
## lifecycle purposes (freed automatically with the ball) while its `points`
## stay in WORLD space, immune to Player's own position/rotation - the
## history below is pushed as global positions, not local offsets.

@export var history_length: int = 22 # physics frames of position history kept - see the class doc above for why this alone controls visual length via speed
@export var min_speed_for_trail: float = 120.0 # below this, essentially invisible - a stationary/slow ball shouldn't drag a ribbon behind it
@export var speed_for_max_effect: float = 900.0 # speed at which width/opacity reach their max
@export var min_width: float = 2.0
@export var max_width: float = 14.0
@export var min_alpha: float = 0.0
@export var max_alpha: float = 0.65
@export var trail_color: Color = Color(1.0, 0.55, 0.25, 1.0)

var _history: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	top_level = true
	position = Vector2.ZERO
	default_color = trail_color
	joint_mode = Line2D.LINE_JOINT_ROUND
	begin_cap_mode = Line2D.LINE_CAP_ROUND
	end_cap_mode = Line2D.LINE_CAP_ROUND
	antialiased = true
	z_index = -1 # behind the ball itself, like a real trail would be

	# Tapers from a point at the tail (oldest sample, t=0) to full width at
	# the head (newest sample, t=1) - points are appended newest-last below,
	# matching Line2D's own start-to-end width_curve convention.
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.05))
	curve.add_point(Vector2(1.0, 1.0))
	width_curve = curve


func update(world_position: Vector2, speed: float) -> void:
	_history.append(world_position)
	while _history.size() > history_length:
		_history.remove_at(0)
	points = _history

	var t: float = clamp((speed - min_speed_for_trail) / max(speed_for_max_effect - min_speed_for_trail, 1.0), 0.0, 1.0)
	width = lerp(min_width, max_width, t)
	modulate.a = lerp(min_alpha, max_alpha, t)


## Called on Player.reset() so a restart doesn't draw a stale streak
## connecting the old run's last position to the new spawn point.
func clear() -> void:
	_history.clear()
	points = _history
