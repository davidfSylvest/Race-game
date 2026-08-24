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

@export var level: int = 1 # 1-4 - see _configure_level()
@export var sample_spacing: float = 24.0 # world px between collision/visual sample points; smaller = smoother curve
@export var ground_thickness: float = 500.0 # how far the solid ground extends below the lowest point
@export var finish_runway: float = 1200.0 # flat ground built past the last keyframe, purely as a safety buffer - NOT counted in course_end_x() (the finish line doesn't move). Main.gd's end-zone trigger sits back from the true polygon edge by a much smaller END_ZONE_MARGIN, and at the speeds this course produces (1000+ px/s) that margin alone is under 0.2s of travel - a player who crosses the line without instantly releasing the stick (i.e. almost everyone) would run clean off the actual end of the terrain a moment later and silently trigger the fall-recovery reset, wiping a run that had just finished. Found via a headless test that kept feeding forward lean past the finish line rather than assuming a player stops the instant they cross.
@export var ice_friction_scale: float = 0.06 # fraction of normal friction loss on ice - 0.06 means ~94% less grip than normal ground
@export var mud_friction_scale: float = 2.0 # multiple of normal friction loss in mud - lowered from 6.5, which turned out to scale catastrophically with speed rather than just "more friction": the per-frame loss is a PERCENTAGE of current speed, while the counter-acceleration that fights it is a roughly fixed absolute rate, so at the 800-1000+ px/s this course routinely produces (after this session's various speed-boosting additions), 6.5x crushed even a perfect, full-lean rider from ~1000 to ~120 px/s in well under a second - nowhere near "barely notices it," and a large part of why simply staying airborne (jumping) through mud beat riding it on the ground by a wide margin. 2.0 keeps mud a real, felt slowdown (verified: a full-lean rider settles around the mid-400s px/s crossing it, not near-zero) without being effectively unsurvivable at realistic speed

## Each entry: {type: "ice"/"mud"/"boost"/"launch"/"bhop"/"flow", start: float, end: float}.
## Populated per-level in _configure_level(). Checked in this same order
## wherever precedence could matter (only relevant if two zones overlap -
## e.g. deliberately never done for ice/mud/boost/launch, but flow and bhop
## sit back-to-back by design so a boundary pixel picks the first match).
var zones: Array[Dictionary] = []

## Each entry: {start: float, end: float} - a real absence of ground, not a
## cosmetic zone. The user explicitly asked for the game to be more
## punishing: a gap can't be rolled across, only jumped - miss it and you
## fall through into open space, which Main.gd now treats as death (see
## Main.gd's checkpoint/death system) rather than the old "just walk back."
## height_at()/tangent_at() stay pure curve math across a gap's x-range
## regardless (needed for continuity - camera lookahead, checkpoint
## fallback positions, etc. shouldn't care that there's no ground there);
## only _build_ground()/TerrainRenderer actually carve the hole out of
## collision/visuals. Populated per-level in _configure_level().
var gaps: Array[Dictionary] = []

## World x positions the player must reach (moving forward) to move their
## respawn point up - see Main.gd's checkpoint tracking. Placed right before
## each gap so a missed jump costs you the run-up, not the whole level, plus
## a couple of earlier waypoints so an early mistake doesn't send you all
## the way back to spawn either. Populated per-level in _configure_level().
var checkpoints: Array[float] = []

## World positions of grapple anchor points - the user's explicit ask to "add
## a grapple effect" and have the level designs match it. A plain
## Array[Vector2] (not a {start,end} zone dict) since a grapple point is a
## single attach location, not a range. Deliberately placed floating above
## each existing gap rather than replacing the jump requirement there: the
## gap-jump distances/checkpoints/medal times were all measured and tuned
## against a jump-only bot (see Medals.gd), so turning a gap into a mandatory
## grapple crossing would invalidate all of that. Instead the grapple is an
## optional, faster/flashier alternative technique layered on top - see
## Player.gd's "Grapple" section for the swing physics itself. Populated per-
## level in _configure_level().
var grapple_points: Array[Vector2] = []

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
	if level == 4:
		keyframes = _level_4_keyframes()
		zones = _level_4_zones()
		gaps = _level_4_gaps()
		checkpoints = _level_4_checkpoints()
		grapple_points = _level_4_grapple_points()
	elif level == 3:
		keyframes = _level_3_keyframes()
		zones = _level_3_zones()
		gaps = _level_3_gaps()
		checkpoints = _level_3_checkpoints()
		grapple_points = _level_3_grapple_points()
	elif level == 2:
		keyframes = _level_2_keyframes()
		zones = _level_2_zones()
		gaps = _level_2_gaps()
		checkpoints = _level_2_checkpoints()
		grapple_points = _level_2_grapple_points()
	else:
		keyframes = _level_1_keyframes()
		zones = _level_1_zones()
		gaps = _level_1_gaps()
		checkpoints = _level_1_checkpoints()
		grapple_points = _level_1_grapple_points()


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


## One gap, on crest 2's flat top (5900-6300, otherwise unclaimed by any
## zone) - flat ground on both sides means approach speed is whatever the
## player actually carried out of the climb from the mud zone just before
## it, not distorted by also being mid-slope. 300px wide (a first pass at
## 200px turned out trivial - see CLAUDE.md for why): verified via headless
## bot that a realistic tangent-tracking approach speed clears it with a
## well-timed jump, and that simply rolling across without jumping reliably
## falls in - see CLAUDE.md for the exact numbers.
func _level_1_gaps() -> Array[Dictionary]:
	return [
		{"start": 5980.0, "end": 6280.0},
	]


## Checkpoints move the respawn point forward as the player clears them, so
## a death (falling into the gap, or the old off-the-world-edge case) costs
## the run-up since the last one, not the whole level. Placed after hill 1
## (so an early mistake there isn't punished as harshly as it used to be),
## and right at the gap's approach (so a missed jump only costs the very
## thing that killed you), plus one past the hardest remaining section.
func _level_1_checkpoints() -> Array[float]:
	return [1950.0, 5900.0, 8650.0]


## The user's follow-up ask, after the grapple ability shipped: "add a lot of
## grappling spots all around the maps, so it becomes a choice in a lot of
## places" - not just the one gap-crossing point every level already had.
## Scattered one point over (or near) every zone type that has real
## traversal weight - each 220px above the local ground/floor height, same
## rule as the original gap points, so every one is a genuine swing, not a
## trivial hop:
## - Ice valley 1 (1400-1900, floor 1050): swing across the low-friction
##   patch entirely instead of riding it - skips the "carry speed well or
##   slide out of control" skill check for a guaranteed but slower-to-aim
##   crossing.
## - Mud valley 2 (4600-5000, floor 1150): same idea, the high-friction
##   complement - swing over instead of eating the friction penalty.
## - Mid-bhop-section (7160-8620, bump peaks at 850): one point above the
##   rhythmic bump run, an alternative to chaining jumps through it for the
##   Chain bonus - swinging over trades that bonus for a guaranteed clean
##   pass over the bumps.
## - The existing gap point (5980-6280) is untouched.
func _level_1_grapple_points() -> Array[Vector2]:
	return [
		Vector2(1650.0, 830.0),  # ice valley 1
		Vector2(4800.0, 930.0),  # mud valley 2
		Vector2(6130.0, 480.0),  # gap (unchanged)
		Vector2(7800.0, 630.0),  # bhop section
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


## One gap, on the flat run between bhop corridor 2 ending (17540/17900) and
## boost pad #2 (18500-18700) - generous flat runway on both sides (100px
## before, 200px after) so neither the corridor's last bump nor the gap jump
## itself sends the player into the boost pad badly angled, same lesson
## already learned from the boost-placement history above. Deliberately NOT
## placed inside the flow gauntlet (8500-15500) - that zone's whole point is
## uninterrupted grounded contact for the Flow meter, and a gap would break
## that every cycle. 300px wide, same width as level 1's gap - a 200px first
## attempt turned out trivial (verified via headless bot: even a
## meaningfully slower approach cleared it with 100+px to spare, because
## air control's constant forward push during the ~0.65s flight time
## dominates over small pre-jump speed differences), so both gaps use the
## width that actually required a real, deliberate jump.
func _level_2_gaps() -> Array[Dictionary]:
	return [
		{"start": 18000.0, "end": 18300.0},
	]


func _level_2_checkpoints() -> Array[float]:
	# The last checkpoint is 17750, not right at the gap's ~17900-18000
	# approach - verified via headless test that a checkpoint respawn at
	# 17900+ can land inside a real separation-from-surface window right at
	# the 17900 keyframe (a "cresting" transition from corridor 2's steep
	# descent into the much gentler run toward the gap, the same real
	# ballistic effect documented in this file's floor_snap_length history -
	# a fresh respawn with no established grounded contact can fail to
	# re-catch the floor there for many frames, unlike a continuously-rolling
	# player who's already grounded through it). 17750 sits cleanly mid-
	# descent, confirmed to re-establish on_floor within 0 frames of a reset.
	return [2150.0, 6850.0, 15550.0, 17750.0]


## Same "a lot of grapple spots, one over each zone with real traversal
## weight" rule as level 1 - see that function's comment for the full
## rationale. Level 2's flow gauntlet (8500-15500, 7000px of six gentle
## rolling hills) is deliberately built for SUSTAINED grounded contact so
## Flow can actually hold near its cap - see the flow-zone note under
## "Level 2" in this file's Architecture docs - so it gets exactly ONE
## point, positioned to swing over a single hill's dip rather than the
## whole gauntlet, preserving that design intent while still offering a
## choice at that one spot.
func _level_2_grapple_points() -> Array[Vector2]:
	return [
		Vector2(1850.0, 930.0),   # ice valley 1
		Vector2(5000.0, 680.0),   # bhop corridor 1
		Vector2(6550.0, 930.0),   # mud valley 2
		Vector2(12000.0, 530.0),  # one hill-dip inside the flow gauntlet
		Vector2(16500.0, 280.0),  # bhop corridor 2
		Vector2(18150.0, 480.0),  # gap (unchanged)
	]


## Level 3: harder and somewhat longer than level 2 (course_end_x ~23800 vs
## ~19300), continuing the escalation toward the user's 10-level goal. Same
## proven building blocks as levels 1/2, reused rather than reinvented:
## - Two bhop corridors, both harder than their level-2 equivalents (corridor
##   1 here matches level 2 corridor 2's ~47deg peak instead of level 2
##   corridor 1's gentler ~37deg; corridor 2 here is the same ~47deg peak but
##   with twice as many cycles, the longest bhop stretch in the game so far).
## - A LONGER flow gauntlet (10100-17800, 7700px) than level 2's (6300px),
##   for more sustained time to hold Flow at its cap - same ~28-32deg gentle
##   peak angles already verified safe for uninterrupted grounded contact.
## - TWO gaps instead of level 2's one (the escalation the user explicitly
##   asked for: "more challenging the greater the number"), both the same
##   300px width already verified to require a genuine jump rather than
##   being crossable on momentum alone (see the level-2 gap comment for why
##   200px turned out trivial).
func _level_3_keyframes() -> Array[Vector2]:
	return [
		Vector2(-600, 600),   # runway behind spawn, same as levels 1/2
		Vector2(500, 600),    # end of flat start
		Vector2(1700, 1200),  # bottom of hill 1's downhill (dx=1200 dy=600, peak ~37deg)
		Vector2(2200, 1200),  # valley 1 floor - ice zone
		Vector2(3500, 500),   # crest 1 (dx=1300 dy=-700, peak ~39deg)
		Vector2(3800, 500),   # flat top of crest 1 - launch pad
		Vector2(4500, 850),   # descent begins into bhop corridor 1 (dx=700 dy=350, peak ~37deg)
		# Bhop corridor 1: dx=150 dy=110, peak ~48deg - steeper than EITHER of
		# level 2's corridors, since level 3's first bump section should
		# already read as harder than level 2's hardest.
		Vector2(4650, 960),
		Vector2(4800, 850),
		Vector2(4950, 960),
		Vector2(5100, 850),
		Vector2(5250, 960),
		Vector2(5400, 850),
		Vector2(5550, 960),
		Vector2(5700, 850),
		Vector2(6200, 1200), # settle to valley 2 floor (dx=500 dy=250, peak ~37deg)
		Vector2(6700, 1200), # valley 2 floor - mud zone
		Vector2(8100, 450),  # crest 2 (dx=1400 dy=-750, peak ~39deg)
		Vector2(8600, 450),  # flat top crest 2 - boost pad #1
		Vector2(9500, 450),  # extended flat run - gap #1 sits inside this stretch with runway both sides
		Vector2(10100, 700), # descent begins into the flow gauntlet (dx=600 dy=250, peak ~32deg, gentle transition)
		# Flow gauntlet: 8 gentle rolling hills (dx=700 dy=250, peak ~32deg,
		# same gentle-by-design angle level 2's gauntlet already proved
		# holds Flow uninterrupted), spanning 7700px - longer than level 2's
		# 6300px for more sustained time at Flow's cap.
		Vector2(10800, 450),
		Vector2(11500, 700),
		Vector2(12200, 450),
		Vector2(12900, 700),
		Vector2(13600, 450),
		Vector2(14300, 700),
		Vector2(15000, 450),
		Vector2(15700, 700),
		Vector2(16400, 450),
		Vector2(17100, 700),
		Vector2(17800, 450), # end of the flow gauntlet
		Vector2(18300, 600), # gentle transition into bhop corridor 2 (dx=500 dy=150, peak ~24deg)
		# Bhop corridor 2: same ~47deg peak as corridor 1 (dx=170 dy=120),
		# but twice as many cycles (8 vs corridor 1's ~4) - the longest,
		# most sustained bump stretch in the game so far, the "way harder"
		# payoff after the calm of the gauntlet, same idea as level 2's
		# corridor 2 relative to its corridor 1.
		Vector2(18470, 720),
		Vector2(18640, 600),
		Vector2(18810, 720),
		Vector2(18980, 600),
		Vector2(19150, 720),
		Vector2(19320, 600),
		Vector2(19490, 720),
		Vector2(19660, 600),
		Vector2(19830, 720),
		Vector2(20000, 600),
		Vector2(20170, 720),
		Vector2(20340, 600),
		Vector2(20510, 720),
		Vector2(20680, 600),
		Vector2(20850, 720),
		Vector2(21020, 600),
		Vector2(21400, 750), # settle down (dx=380 dy=150, peak ~30deg)
		Vector2(21800, 750), # flat run - gap #2 sits inside this stretch with runway both sides
		Vector2(22400, 750), # flat continues past the gap for landing runway
		Vector2(22900, 750), # boost pad #2
		Vector2(23800, 750), # finish straight
	]


func _level_3_zones() -> Array[Dictionary]:
	return [
		{"type": "ice", "start": 1700.0, "end": 2200.0},
		{"type": "launch", "start": 3600.0, "end": 3700.0},
		{"type": "bhop", "start": 4500.0, "end": 5700.0},
		{"type": "mud", "start": 6200.0, "end": 6700.0},
		{"type": "boost", "start": 8650.0, "end": 8800.0},
		{"type": "flow", "start": 10100.0, "end": 17800.0},
		{"type": "bhop", "start": 18300.0, "end": 21020.0},
		{"type": "boost", "start": 22950.0, "end": 23150.0},
	]


## Gap 1 sits on crest 2's extended flat top (8600-9500, boost pad already
## claims 8650-8800), leaving 200px of runway before it and 200px before the
## flow gauntlet's descent begins - same "generous flat runway, no launch
## right before" placement rule established for both level-2's gap and this
## level's gap 2 below. Gap 2 sits on the flat settle-down after bhop
## corridor 2 (21400-22400), well before boost pad #2 (22950-23150).
func _level_3_gaps() -> Array[Dictionary]:
	return [
		{"start": 9000.0, "end": 9300.0},
		{"start": 21900.0, "end": 22200.0},
	]


func _level_3_checkpoints() -> Array[float]:
	return [2250.0, 5750.0, 7200.0, 8850.0, 13650.0, 17850.0, 21750.0]


## Same "a lot of grapple spots" rule as levels 1/2 - see level 1's
## _level_1_grapple_points() for the full rationale. Level 3's flow gauntlet
## (10100-17800, 7700px of eight gentle rolling hills, the longest in the
## game) gets the same single-dip treatment level 2's gauntlet does, for the
## same reason: it's built for sustained grounded contact, not a swing-past.
## The two existing gap points (9000-9300, 21900-22200) are unchanged.
func _level_3_grapple_points() -> Array[Vector2]:
	return [
		Vector2(1950.0, 980.0),   # ice valley 1
		Vector2(5100.0, 630.0),   # bhop corridor 1
		Vector2(6450.0, 980.0),   # mud valley 2
		Vector2(9150.0, 230.0),   # gap 1 (unchanged)
		Vector2(13950.0, 480.0),  # one hill-dip inside the flow gauntlet
		Vector2(19650.0, 380.0),  # bhop corridor 2
		Vector2(22050.0, 530.0),  # gap 2 (unchanged)
	]


## Level 4: "Grapple Gauntlet" - REBUILT from its original design after the
## user's explicit rejection: "this might never work as youre doing the
## level design and its very bad. its alot of repetition and not so much as
## flow and challenging," followed by "i want levels to be diverse, have
## various different hills and sloped and jumps and what not... be creative
## dont just copy paste the same thing again and again." The original
## version (9 identical loop-generated void/platform/void sections, all at
## the same flat y=600, all 3-point chains at the same flat height 490 - see
## git history) was physically sound but exactly the kind of copy-paste the
## user called out. This version keeps every validated PHYSICS fact from
## that build (300px chain spacing, the landing-ramp fix for a swing's
## natural sink, release timing 20-30% past the bottom of the arc, chains
## stay well under the ~12-point safe range) but throws out the
## loop-generated LAYOUT entirely in favor of hand-authored variety, same as
## levels 1-3 already are: real rollable terrain (hills, an ice valley, a
## mud valley, a bhop corridor, a launch pad, boost pads) fills the space
## BETWEEN four distinct grapple crossings, and no two crossings are the
## same shape:
##   1. A short 2-point intro swing (modest height variance) - a gentle
##      first taste right after the opening hill.
##   2. A 3-point "rising staircase" - each point higher than the last
##      (60px steps), climbing during the chain instead of staying flat.
##   3. The signature: a SINGLE long rope leap on one grapple point, engaged
##      near the edge of a wide void for a real pendulum arc rather than a
##      short hop-to-hop chain - the closest thing to the "loop" the user
##      floated. (A true vertical loop isn't possible on this engine's
##      terrain: height_at(x) is single-valued - one Y per X - by
##      construction, the same reason every gap/checkpoint/camera-lookahead
##      query in this file works, so a loop-back collision shape simply
##      can't be represented. The big swing is the honest substitute: a
##      real airborne arc with genuine height and a dramatic low point,
##      just not a closed loop.)
##   4. A 4-point rhythmic finale chain (alternating +/-50px, a wave) - the
##      most "dependable" pattern, saved for last as a familiar close after
##      three different rhythms.
## Every void->platform landing still uses the exact same sloped-ramp fix
## discovered building the original version (see the numbered writeup
## further down) - LEVEL_4_RAMP_LENGTH/LEVEL_4_RAMP_RISE, unchanged from
## that build. Verified end-to-end with a headless chain-swing bot (see the
## commit this landed in): zero deaths, all 4 crossings cleared, all 7
## checkpoints re-ground within 0 frames.
func _level_4_keyframes() -> Array[Vector2]:
	return [
		Vector2(-600.0, 600.0),  # runway behind spawn
		Vector2(500.0, 600.0),   # end of flat start
		# Opening hill + ice valley (dx=1200 dy=550, peak ~34.5deg)
		Vector2(1700.0, 1150.0),
		Vector2(2200.0, 1150.0), # ice valley floor
		# Climb to crest 1 (dx=1300 dy=-650, peak ~36.9deg) - launch pad on top
		Vector2(3500.0, 500.0),
		Vector2(3800.0, 500.0),
		Vector2(4300.0, 600.0),  # gentle descent (dx=500 dy=100, peak ~16.7deg)
		Vector2(4600.0, 600.0),  # flat run-up to void 1 - GAP 1 STARTS HERE
		# Void 1 (4600-5400): short 2-point intro swing at (4900,420)/(5200,470)
		Vector2(5400.0, 600.0 + LEVEL_4_RAMP_RISE),  # ramp entry (real void ends here; ramp is ADDED after it)
		Vector2(6050.0, 600.0),  # ramp crests onto platform 1 (dx=650 dy=-430, peak ~44.7deg)
		Vector2(6350.0, 600.0),  # platform 1 end (300px)
		# Bhop corridor (dx=170 dy=110, peak ~44.2deg, 4 cycles) straight off the platform
		Vector2(6520.0, 710.0),
		Vector2(6690.0, 600.0),
		Vector2(6860.0, 710.0),
		Vector2(7030.0, 600.0),
		Vector2(7200.0, 710.0),
		Vector2(7370.0, 600.0),
		Vector2(7540.0, 710.0),
		Vector2(7710.0, 600.0),  # end of bhop corridor
		Vector2(8310.0, 900.0),  # descent into mud valley (dx=600 dy=300, peak ~36.9deg)
		Vector2(8710.0, 900.0),  # mud valley floor
		Vector2(9910.0, 450.0),  # climb to crest 2 (dx=1200 dy=-450, peak ~29.4deg) - boost pad on top
		Vector2(10210.0, 450.0),
		Vector2(10710.0, 550.0), # gentle descent (dx=500 dy=100, peak ~16.7deg)
		Vector2(11010.0, 550.0), # flat run-up to void 2 - GAP 2 STARTS HERE
		# Void 2 (11010-12110): 3-point rising staircase at (11310,480)/(11610,420)/(11910,360)
		Vector2(12110.0, 500.0 + LEVEL_4_RAMP_RISE),  # ramp entry (platform 2 sits at y=500, a bit higher after the climb)
		Vector2(12760.0, 500.0), # ramp crests onto platform 2 (dx=650 dy=-430, peak ~44.7deg)
		Vector2(13060.0, 500.0), # platform 2 end (300px)
		Vector2(14260.0, 1050.0), # descent into ice valley 2 (dx=1200 dy=550, peak ~34.5deg)
		Vector2(14760.0, 1050.0), # ice valley floor
		Vector2(16060.0, 500.0), # climb to crest 3 (dx=1300 dy=-550, peak ~32.3deg) - launch pad on top
		Vector2(16360.0, 500.0),
		Vector2(16860.0, 650.0), # descent (dx=500 dy=150, peak ~24.2deg)
		Vector2(17360.0, 650.0), # flat run-up to void 3 - GAP 3 STARTS HERE
		# Void 3 (17360-18060): the signature single-point big swing at (17700,340)
		Vector2(18060.0, 550.0 + LEVEL_4_RAMP_RISE),  # ramp entry (platform 3 sits at y=550)
		Vector2(18710.0, 550.0), # ramp crests onto platform 3 (dx=650 dy=-430, peak ~44.7deg)
		Vector2(19010.0, 550.0), # platform 3 end (300px)
		Vector2(20010.0, 1000.0), # descent into mud valley 2 (dx=1000 dy=450, peak ~34.0deg)
		Vector2(20410.0, 1000.0), # mud valley floor
		Vector2(21610.0, 500.0), # climb to crest 4 (dx=1200 dy=-500, peak ~32.0deg) - boost pad on top
		Vector2(21910.0, 500.0),
		Vector2(22410.0, 600.0), # descent (dx=500 dy=100, peak ~16.7deg)
		Vector2(22710.0, 600.0), # flat run-up to void 4 - GAP 4 STARTS HERE
		# Void 4 (22710-24110): 4-point rhythmic finale chain, alternating
		# (23010,430)/(23310,480)/(23610,430)/(23910,480)
		Vector2(24110.0, 600.0 + LEVEL_4_RAMP_RISE),  # ramp entry (finish platform sits at y=600, matching spawn)
		Vector2(24760.0, 600.0), # ramp crests onto the finish platform (dx=650 dy=-430, peak ~44.7deg)
		Vector2(25410.0, 600.0), # finish straight (650px, same runway convention as levels 1-3)
	]


func _level_4_zones() -> Array[Dictionary]:
	return [
		{"type": "ice", "start": 1700.0, "end": 2200.0},
		{"type": "launch", "start": 3600.0, "end": 3700.0},
		{"type": "bhop", "start": 6350.0, "end": 7710.0},
		{"type": "mud", "start": 8310.0, "end": 8710.0},
		{"type": "boost", "start": 10010.0, "end": 10160.0},
		{"type": "ice", "start": 14260.0, "end": 14760.0},
		{"type": "launch", "start": 16160.0, "end": 16260.0},
		{"type": "mud", "start": 20010.0, "end": 20410.0},
		{"type": "boost", "start": 21710.0, "end": 21860.0},
	]


## Horizontal run/rise of the landing ramp carved into every void->platform
## transition. LARGER than the original build's 500/320 - a headless bot
## measuring the actual release trajectory off this redesign's void 1 found
## the ball sinks up to ~440px below the platform's height by the time it
## reaches the far edge (steeper/shorter swings sink faster than the
## original's uniform 4-point-chain geometry did), which clipped the old
## ramp's vertical left-edge wall exactly like the original build's very
## first (pre-ramp) failure mode - a real, headlessly-caught regression from
## reusing the old constant against a new swing shape, not a hypothetical.
## 650/430 (peak angle atan(1.5*430/650) =~ 44.7deg, same safety margin
## under floor_max_angle's 55deg as the original) gives real headroom over
## that measured sink. Re-verified with the same bot: zero wall-clips at any
## of the four crossings with this value.
const LEVEL_4_RAMP_LENGTH: float = 650.0
const LEVEL_4_RAMP_RISE: float = 430.0


## Four voids, each sized to its own crossing (short intro / staircase /
## the wide single-swing leap / the finale chain) rather than one uniform
## width repeated nine times - see _level_4_keyframes() for exactly where
## each one sits and _level_4_grapple_points() for what crosses it.
func _level_4_gaps() -> Array[Dictionary]:
	return [
		{"start": 4600.0, "end": 5400.0},
		{"start": 11010.0, "end": 12110.0},
		{"start": 17360.0, "end": 18060.0},
		{"start": 22710.0, "end": 24110.0},
	]


## Seven checkpoints - one on each rest platform (so a death mid-void sends
## you back to the start of that crossing's chain, not to spawn) PLUS one on
## the flat run-up just before each void (so a death mid-crossing doesn't
## also cost the whole rollable interlude - hill, ice/mud valley, bhop
## corridor, or climb - that led up to it). That's a real improvement over
## the original build, which only had a checkpoint per platform (8 for 9
## sections) and nothing guarding the rollable sections themselves. Every
## one of these sits comfortably mid-flat-stretch, well clear of any curve
## transition - verified headlessly (0-frame is_on_floor() re-establishment
## on a reset at all seven, same check every other level's checkpoints get).
func _level_4_checkpoints() -> Array[float]:
	return [4550.0, 6200.0, 10950.0, 12910.0, 17300.0, 18860.0, 22650.0]


## The core of this level, and the one place its identity as "majority
## grapple-only" still lives - four crossings, each a genuinely different
## shape rather than the same loop-generated pattern repeated:
##
## Point spacing (300px, the horizontal distance actually used between
## consecutive points below) is carried over from the original build's
## dedicated headless prototyping, not re-derived from scratch - that
## process (documented in git history) found 300px spacing reliable across
## release timing 20-30% past the bottom of the arc, and confirmed real
## height variance between points is tolerated on chains up to ~12 points
## long. Every chain here is 4 points or fewer - well inside that
## validated-safe range - so the height variance used for the staircase
## (60px/step) and the finale's alternating wave (+/-50px) doesn't reopen
## the long-chain drift problem that forced the original build's chains
## flat: that problem was specific to a single 27-point mega-chain spanning
## the whole course, not to a short individual crossing.
##
## What did NOT carry over unchanged: the landing-ramp size (see
## LEVEL_4_RAMP_RISE above) - a headless full-course bot caught this
## redesign's void 1 (a short 2-point chain) sinking much further below the
## platform than the original's longer, flatter chains ever did, clipping
## the ramp's vertical edge wall instead of landing on its slope. Confirmed
## via a release-fraction sweep (0.15/0.2/0.3/0.35 all failed identically)
## that this was a geometry problem, not a bot-timing problem, before
## enlarging the ramp.
##
## Void 3's single-point big swing is the one genuinely new configuration
## (a full pendulum arc across an entire void on one rope, not a hop-to-hop
## chain) - engaging from right at the void's edge (17360,650) to the point
## (17700,340) is a 460px pull (comfortably under grapple_max_range's 600,
## with real margin even if pressed ~100px early).
##
## Verified headlessly end to end: a chain-swing bot that targets each void's
## points in sequence (not "nearest in range," which re-grabs the point it
## just released - see CLAUDE.md) and releases 25% past the bottom of each
## arc clears all four crossings and finishes the full course with zero
## deaths.
func _level_4_grapple_points() -> Array[Vector2]:
	return [
		Vector2(4900.0, 420.0),   # void 1: intro swing, point 1
		Vector2(5200.0, 470.0),   # void 1: intro swing, point 2
		Vector2(11310.0, 480.0),  # void 2: rising staircase, point 1 (lowest)
		Vector2(11610.0, 420.0),  # void 2: rising staircase, point 2
		Vector2(11910.0, 360.0),  # void 2: rising staircase, point 3 (highest)
		Vector2(17700.0, 340.0),  # void 3: the signature big swing - one point, one long rope
		Vector2(23010.0, 430.0),  # void 4: finale wave, point 1
		Vector2(23310.0, 480.0),  # void 4: finale wave, point 2
		Vector2(23610.0, 430.0),  # void 4: finale wave, point 3
		Vector2(23910.0, 480.0),  # void 4: finale wave, point 4
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


## True inside a gap - a real absence of ground (see gaps above), not a
## cosmetic zone. Main.gd uses this to distinguish "fell into a gap"/"fell
## off the world" from ordinary grounded play when deciding whether to
## trigger a death/respawn.
func is_gap_at(x: float) -> bool:
	for g in gaps:
		if x >= g.start and x <= g.end:
			return true
	return false


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

	var body := StaticBody2D.new()
	body.name = "Ground"
	add_child(body)

	# Solid ground is one CollisionPolygon2D per contiguous stretch between
	# gaps, rather than one polygon for the whole course - a gap is a real
	# absence of collision, not a cosmetic zone like ice/mud, so it has to be
	# carved out of the shape itself. Boundaries are start_x/end_x plus every
	# gap edge, sorted, so each adjacent pair is either fully solid or
	# entirely inside a gap.
	var boundaries: Array[float] = [start_x, end_x]
	for g in gaps:
		boundaries.append(g.start)
		boundaries.append(g.end)
	boundaries.sort()
	for i in range(boundaries.size() - 1):
		var seg_start: float = boundaries[i]
		var seg_end: float = boundaries[i + 1]
		if seg_end <= seg_start:
			continue
		if is_gap_at((seg_start + seg_end) / 2.0):
			continue
		_add_collision_segment(body, seg_start, seg_end)


func _add_collision_segment(body: Node, seg_start: float, seg_end: float) -> void:
	var start_index: int = 0
	while start_index < _top_points.size() - 1 and _top_points[start_index].x < seg_start:
		start_index += 1
	var end_index: int = start_index
	while end_index < _top_points.size() - 1 and _top_points[end_index].x < seg_end:
		end_index += 1

	var points: PackedVector2Array = _top_points.slice(start_index, end_index + 1)
	points.append(Vector2(points[points.size() - 1].x, _bottom_y))
	points.append(Vector2(points[0].x, _bottom_y))

	var collision := CollisionPolygon2D.new()
	collision.polygon = points
	body.add_child(collision)
