# Race Game — Physics Feel-Test Prototype

A Godot 2D mobile prototype whose entire purpose is testing the *feel* of a
lean-based movement system on hilly terrain. It is explicitly not a game yet:
no menus, no title screen, no results screen. Do not add any of the "DO NOT
BUILD" items below unless the user explicitly asks for that specific thing in
that specific message.

Two more items just moved out of that list, together, on one explicit ask:
persistent highscores, ghost replays, and Trackmania-style bronze-time level
unlocking. See "Persistence, Ghosts, and Level Unlocks" under Architecture for
what was actually built and why the numbers used there are measured, not
guessed. This does NOT reopen "no save system" or "no ghost/replay" as a
general license - it's scoped exactly to per-level best-time+ghost
persistence and the unlock gate, not a save-everything system, not a
level-select menu, not cloud sync.

There are now three levels. The user's explicit /goal ask went further than
the original one-time second-course exception: "more challenging the greater
the number until level 10," each gated on beating the previous level's bronze
time. That's a standing, scoped authorization to keep adding levels 4-10
incrementally (see the "Two-/three-level architecture" and "Persistence,
Ghosts, and Level Unlocks" notes under Architecture for what's built and
what's still planned) - it is NOT a general license for anything else on the
DO NOT BUILD list below (still no level-select menu screen, still no scope
creep beyond levels + their own medal/unlock plumbing) unless asked for that
specific thing again.

Same story with visuals: the user explicitly asked to "greatly improve the
textures, shading, lighting, and models," so the old "gray-box art only" line
above is gone and a real lighting/shading pass now exists - see "Visual
Presentation" under Architecture. A follow-up request went further, asking
for the visual code itself to be restructured into "separate, swappable
systems" (a silhouette-based terrain renderer, a parallax background, a
speed-trail effect, a camera rig) plus a speed-scaled camera streak/
chromatic shader (since removed - the user found the blur-at-speed effect
undesirable, see the streak-blur note under "Visual Presentation") and a
time-of-day/biome palette system - see the same "Visual Presentation"
section for what the systems split into (`TerrainRenderer.gd`,
`TrailEffect.gd`, `CameraRig.gd`, `TimeOfDayPalette.gd`/`PaletteController.gd`).
Both visual requests are still scoped to what was asked (procedural
shading/lighting/depth cues and their modular organization, not an
art-asset pipeline - no external image files were added, see that section
for why), not a general license to keep adding visual scope. Everything
else in this file's minimalism stance (no UI/menu/persistence scope creep,
headless-only validation, don't add DO NOT BUILD items unasked) still
applies exactly as before.

One more explicit exception, and this one actually reverses an earlier
design principle rather than just adding to it: the user asked for the game
to be "more punishing," specifically that missing a jump over a gap should
kill you and send you back to a checkpoint. The Movement design section
used to say flatly "there is no fall/wipeout mechanic" - that's no longer
true. See "Gaps, Death, and Checkpoints" under Movement design for what
changed (real terrain gaps, a checkpoint system, a death path distinct from
the explicit Restart button, harsher landing punishment) and why it's still
scoped tightly to that ask (two gaps total, one per level, not a redesign
of the whole risk/reward system).

Newest exception: the user explicitly asked to "add a grapple effect" and
then "adjust the level designs so they match the abilit[y]." A real rope-
swing mechanic now exists (a genuinely new movement tool, not a variant of
lean/jump) - see "Grapple" under Movement design for the physics and
"Grapple Points" under Architecture for how it's wired into the world and
why it was layered ADDITIVELY onto every level rather than replacing any
already-tuned content (the gap widths/checkpoints/medal times documented
under "Persistence, Ghosts, and Level Unlocks" were all measured against a
jump-only bot - turning a gap into a mandatory grapple crossing would have
invalidated every one of those numbers). This is scoped to exactly one new
ability plus the anchor points needed to use it meaningfully - not a general
license for more abilities, a double-jump, wall-running, etc. unless asked
for that specific thing again.

## Godot version: 4.7.1 — always, no exceptions

**Always use Godot 4.7.1-stable.** Not "latest," not 4.3, not whatever a
particular editor happens to have cached. The user has been burned by a
stray older-version editor silently re-saving/downgrading project files.
If you (or any tool) opens this project with anything other than 4.7.1,
you risk corrupting `.uid` sidecar files, `project.godot` config keys, or
`.import` metadata that 4.7.1 expects in a specific shape.

- Binary for headless validation:
  `https://github.com/godotengine/godot/releases/download/4.7.1-stable/Godot_v4.7.1-stable_linux.x86_64.zip`
  Verify a version tag is real before trusting it (a fake tag 404s; a real
  one 302-redirects to the asset) — don't guess a newer tag exists.
- Before committing, confirm nothing downgraded `project.godot`,
  `scripts/*.gd.uid`, or `*.import` files. If you see a diff there you
  didn't intend, something opened the project with the wrong version.
- If you ever need a different Godot version for a specific one-off reason,
  say so explicitly and ask before making it the new default — don't drift
  silently.
- **Concrete things to check every session, not just "did an old editor
  touch this"** — this has already gone wrong twice from causes that had
  nothing to do with an old editor opening the project:
  1. `grep 'config/features' project.godot` must read
     `PackedStringArray("4.7")`. This field is what the Godot project list
     actually displays as the project's version — it will NOT self-correct
     just because you validated with the 4.7.1 binary elsewhere, and a
     stale value here (e.g. left over from early scaffolding, before a
     version was even pinned) is exactly what makes the project look like
     it's on the wrong Godot version even when every other file is fine.
  2. Every file in `scripts/*.gd` must have a matching `scripts/*.gd.uid`
     committed alongside it. `.uid` files are only generated by an actual
     **editor** import pass, not by `--headless` alone — so adding a new
     script and only validating with plain `--headless` runs will silently
     leave its `.uid` missing. Force one with
     `--headless --editor --quit-after 30` (crashes harmlessly on exit,
     see below) after adding any new script, then `git add` the new
     `.gd.uid` file before committing.
  3. `ls scripts/*.gd.uid *.svg.import 2>/dev/null` then `git status` —
     anything generated-but-uncommitted here is a future "why did this
     change" surprise for the user's own editor.

## Validating changes headlessly (no display in this environment)

This environment has no GUI. To verify a change actually works before
handing it off:

1. Download/keep the 4.7.1 binary at a stable path (e.g. `/tmp/Godot_v4.7.1-stable_linux.x86_64`).
2. `rm -rf .godot` then run `--headless --quit-after N` to force a clean
   reimport and confirm no import errors.
3. Run the actual game headless (`--headless --quit-after N`) and confirm
   exit code 0 with no `ERROR`/`SCRIPT ERROR` lines.
4. For physics changes, write a throwaway `scripts/_HeadlessTest.gd`,
   temporarily register it as an `[autoload]` in `project.godot`, and drive
   the player through the **real** physics loop:
   ```gdscript
   while i < N and player.position.x < target_x:
       player.joystick.set("_knob_offset", ...)   # set input for the upcoming tick
       await get_tree().physics_frame              # let the engine step once
       i += 1
   ```
   Run with **both** `--headless --fixed-fps 60 --quit-after N`.
   `--fixed-fps 60` is what makes this fast: it decouples simulated time
   from real wall-clock time (Godot runs ticks as fast as the CPU allows
   while still handing `_physics_process` the correct 1/60s delta each
   time), so an 18-simulated-second race completes in well under a second
   of real time instead of ~1 real second per simulated second. `N` for
   `--quit-after` needs headroom for however many physics frames the test
   actually needs (a few thousand is enough for any single-race check).
   Print the numbers that matter and sanity-check them against the intended
   design (e.g. "downhill + lean should exceed flat + same lean").
   **Do NOT call `player.call("_physics_process", delta)` directly** - this
   used to be the documented approach here, and it is broken: Godot's own
   engine loop keeps calling `_physics_process` on its normal automatic
   schedule regardless, so a manual call doesn't replace that, it races
   against it. The two compete unpredictably depending on real execution
   speed, which is invisible in a single run but produces genuinely
   different outcomes (confirmed: three back-to-back runs of one identical
   throwaway script gave one finish at 18s, one at 44s after a backward
   send-flying detour, and one that never got there in 3600 manual calls)
   for what should be a fully deterministic simulation. This cost real time
   chasing a phantom "regression" that was actually just this noise -
   re-running the exact same test against the exact same code gave three
   different answers before the `physics_frame`-driven version above gave
   the same answer (down to the exact finish millisecond) on every repeat.
   If a test needs to inject state mid-run (e.g. a specific velocity right
   before a jump), set it directly on `player` between `await` calls -
   never resume driving physics through a raw manual call once the loop
   has started.
5. **Always remove the test scaffolding before committing**: delete
   `scripts/_HeadlessTest.gd`, restore `project.godot` (no leftover
   `[autoload]` block), and `rm -rf .godot` so nothing test-only ships.
6. Note: `--headless --editor --quit-after N` (forcing a reimport via the
   editor) can crash on exit in 4.7.1 with `ERROR: Parameter "singleton" is
   null.` — this is a harmless teardown quirk in that invocation only; the
   import itself completes first. Prefer plain `--headless --quit-after N`
   (no `--editor`) for actually running/testing the game.

Don't trust a change until you've actually run these steps — this project
has already shipped one real bug (an unconditional gravity term that
overrode player input) that a headless smoke test caught before commit.

## Architecture

- **N levels, N scenes, one set of scripts.** `scenes/Main.tscn` (level 1,
  the original course), `scenes/Level2.tscn` (level 2), `scenes/Level3.tscn`
  (level 3 - see "Level 3" under Persistence/Ghosts/Unlocks below), and
  `scenes/Level4.tscn` (level 4, "Grapple Gauntlet" - see the dedicated
  section under Persistence/Ghosts/Unlocks) share the exact same
  `Player.gd`/`Main.gd`/`Joystick.gd` and even the same `Terrain.gd` script;
  the only per-scene difference is a single `level`
  property on the Terrain node (`1`/`2`/`3`/`4` respectively - see
  `Terrain._configure_level()`). A small `LevelButton` in the HUD (same
  category as Restart/Jump, not a menu screen) calls
  `get_tree().change_scene_to_file(...)` to cycle forward through all
  `Main.TOTAL_LEVELS` levels (wrapping back to 1 after the last, gated by
  `SaveManager.is_level_unlocked()` same as always - see
  `Main._scene_path_for_level()`/`_update_level_button_label()`/
  `_on_level_button_pressed()`) - each scene swap is a full fresh load (new
  Player, new Terrain, new Main), so there's no cross-level state to manage.
  Adding a level means: new `Terrain._level_N_*()` data functions + a new
  `scenes/LevelN.tscn` + bumping `Main.TOTAL_LEVELS` + a new `Medals.gd`
  entry - don't build a level-select menu screen, and don't add levels
  beyond what's been explicitly asked for (currently up to 10, per the
  user's /goal - see the top of this file).
- `scripts/Terrain.gd` — builds the ground at runtime from a `keyframes`
  array of `(x, y)` control points, smoothstep-interpolated between them
  (curved, not linear) into one `CollisionPolygon2D` + `Polygon2D`. Exposes
  `height_at(x)`, `spawn_x()`, `course_end_x()` so other scripts never
  hardcode the course layout. Special terrain (ice/mud/boost/launch/bhop/
  flow) is a generic `zones: Array[Dictionary]` of `{type, start, end}`
  rather than one pair of consts per zone type - this is what lets a level
  have as many of each kind as its layout needs (level 2 has two boost pads
  and two bhop-style corridors; level 1 still has exactly one of each, just
  expressed as a one-entry-per-type zones list now instead of dedicated
  consts). `_configure_level()` picks which keyframes/zones list to load
  (`_level_1_*()` / `_level_2_*()`) based on the `level` export, before
  `_build_ground()` runs - a fix to `height_at()`/`tangent_at()`/any zone
  helper automatically applies to both levels, since neither level
  duplicates that logic.
- `scripts/Player.gd` — the physics core. All movement tuning lives here as
  `@export` vars grouped by concern (Acceleration, Top Speed Curve,
  Gravity, Slope Response, Lean Alignment, Landing/Launch Quality, Air
  Control, Jump, Chain, Flow Meter, Ball Visual). `reset(spawn_position)`
  re-centers state for the in-game restart — no scene reload. `jump()` is
  the public entry point for the JUMP button (grounded-or-coyote only, with
  buffering — see Movement design below); `landing_event_id`/
  `launch_event_id` are incrementing counters Main.gd polls to edge-detect
  a fresh landing/launch (for camera shake/zoom-kick) without duplicating
  the on_floor-transition logic that already lives here.
- `scripts/Joystick.gd` — fixed bottom-left virtual joystick. Touch primary,
  mouse fallback for desktop testing. `get_vector()` returns deflection as
  a `Vector2`: length 0–1 is magnitude, direction is lean angle.
- `scripts/Main.gd` — HUD readouts (timer, speed, best time, Flow bar,
  Chain text), restart button wiring, JUMP button wiring (`button_down`,
  not `.pressed`, so a tap registers on touch-down like the joystick does),
  end-zone signal handling, camera zoom/lookahead/shake/zoom-kick, and a
  gold "NEW BEST" flash on the best-time label (a genuine new best was
  previously only ever printed to the console, invisible on the Android
  build the user actually plays on). `LevelButton` also uses `button_down`
  now, for the same reason - the user reported being unable to select Level
  2 on their real device even though the underlying `change_scene_to_file`
  mechanism tested fine headlessly (simulating a direct signal emit). The
  default `.pressed` signal only fires if the finger lifts while still over
  the button, so a quick real-device tap with any tiny drag can silently
  swallow it - much more likely on a small top-corner button tapped quickly
  mid-decision than on Restart, which players tap slowly and deliberately
  after a run. Also enlarged the button (120x44 -> 160x54) as a second,
  independent improvement to the same real-device-only complaint - a bigger
  target is harder to miss regardless of which theory about the tap was
  right. Couldn't fully confirm the original root cause on-device (no
  `export_presets.cfg` in the repo to check whether a local Android export
  preset might also be excluding `Level2.tscn` - that's a per-user export
  setting, not something this checkout can verify), so if the button still
  doesn't respond after this fix, check that the Android export preset's
  resource filter actually includes `scenes/Level2.tscn`.
- The course has one mid-course roller bump (partway down hill 2's descent)
  plus a dedicated bhop section (small rhythmic bumps) right before the
  finish, so the chain/flow/landing/launch systems have places to actually
  chain several jumps in a row - the two big hills' crests each only give
  ~1 real jump per run. Getting bumps to actually launch required lowering
  `floor_snap_length` (12 -> 5): Godot's floor snapping quietly absorbs
  any separation smaller than that value regardless of slope angle, so a
  bump can look plenty steep and still never produce real air time if it's
  small in absolute scale. If tuning bump size/spacing, re-check that
  bumps still generate real on_floor transitions (a quick instrumented
  headless run, not just eyeballing the slope angle) - a bot that
  re-aligns its lean to the tangent every frame will actively hug bumps
  instead of separating from them, so test with a fixed lean / momentum
  coast approach instead, closer to how a real player at speed behaves.
- `floor_snap_length` is no longer one global value - it's now
  `floor_snap_length_wide` (40) everywhere, dropping to
  `floor_snap_length_tight` (5, the original global value) only inside a
  `bhop` or `launch` zone (`Terrain.wants_tight_floor_snap_at()`, checked
  and applied at the top of `Player._physics_process()` every frame). Found
  after the user reported the ball visibly bouncing down ordinary hills
  instead of rolling. Headless tracing confirmed it was real ballistic
  physics, not a terrain-smoothness bug: a fast ball genuinely leaves the
  surface for a few frames at the convex curve transition where a flat top
  bends into a steep descent (up to ~41px of separation and 0.68s of real
  air time measured on hill 1's crest), because gravity can't pull it back
  onto the surface fast enough to match the curve's bend rate at that
  speed - a real "cresting" effect, not an artifact (ruling out terrain
  `sample_spacing` as a cause confirmed this: 8 vs 24 gave identical bounce
  counts). The single old global value (5) was tuned specifically for the
  bhop section's much smaller bumps and was far too small to bridge that
  separation, so it kept re-detecting "on floor" as false and dropping the
  ball into a full ballistic arc down every ordinary hill - a genuine
  regression from that earlier bhop-tuning pass, invisible until a full-hill
  headless trace was actually run (the bhop section itself was always
  tested and looked fine in isolation). Simply raising the global value to
  40 fixes ordinary hills perfectly (confirmed: on_floor stays continuously
  true through hill 1's whole descent, the only transition left is the
  test's own artificial initial drop) but breaks the bhop section outright
  - it glues right over those smaller, deliberate bumps too, collapsing a
  verified 5-landing-event chain down to 1. A per-zone value fixes both:
  re-verified hill 1's descent smooth AND the bhop section back to its
  original 5 landing events / 11 on_floor transitions, byte-for-byte the
  pre-regression numbers. Re-ran the full 4-policy benchmark on both
  Main.tscn and Level2.tscn afterward per the working-style rule below -
  no regressions, and every finishing policy actually got faster than the
  previously-documented numbers (e.g. level 1 perfect ~16.6s vs ~18s
  before), consistent with the old bouncing having been quietly costing
  speed through the landing-quality mismatch penalty on every one of those
  unwanted bounces.

### Visual Presentation (textures/shading/lighting)

The user explicitly asked to "greatly improve the textures, shading,
lighting, and models" for this to "look amazing" - this section is the
result. Deliberately no external image assets were added (no new binary
files, no `.import` sidecars to babysit alongside the `.uid`/`config/features`
checks above) - everything here is procedural, built from GDScript at
runtime the same way Terrain.gd already builds its ground polygons, so both
levels get it for free with zero duplication and there's nothing for the
wrong-Godot-version risk at the top of this file to corrupt.

- **Terrain rendering is a separate file from terrain physics.** A later
  request explicitly asked for "separate, swappable systems... not one
  monolithic script," so `Terrain.gd`'s visual-building code (the per-vertex
  gradient + rim highlight described below) was pulled out into
  `scripts/TerrainRenderer.gd`, instantiated as a child by `Terrain._ready()`
  right after `_build_ground()`. The split preserves the "visual can never
  desync from collision" guarantee rather than relaxing it:
  `TerrainRenderer.build(terrain)` reads `terrain.get_top_points()` /
  `terrain.get_bottom_y()` directly - the EXACT arrays/values the collision
  polygon was built from - rather than resampling `height_at()` itself.
  `Terrain.gd` now owns physics/collision and course-layout data only
  (keyframes, zones, `height_at`/`tangent_at`/friction/zone-query methods);
  `TerrainRenderer.gd` owns every fill color (`ground_color`, the six zone
  accent colors, `_zone_color()`) and the shading itself: each ground
  Polygon2D bakes per-vertex colors instead of one flat fill - top curve
  vertices get `color.lightened(top_edge_lighten)`, buried bottom-edge
  vertices get `color.darkened(bottom_edge_darken)`, faking a "lit from
  directly above" gradient on every zone color automatically with zero
  shader cost (`Polygon2D.vertex_colors`, baked once at build time). A
  single continuous `Line2D` along the whole course's top points adds a
  warm, translucent rim highlight - one node for the entire course, so
  there's no seam at zone-color boundaries. `TerrainRenderer.refresh_colors()`
  tears down and rebuilds just the visual fill from whatever its color
  exports currently are, without touching Terrain's collision at all - see
  the PaletteController bullet below for who calls it and why.
- **Ball shading** (`Player._make_shading()`/`_make_shadow()`/`_make_glow()`,
  all built in `_ready()`, not placed in either .tscn): three additions,
  each a plain sibling of the existing `Visual` node so none of them
  interfere with `Visual`'s own rotation/squash-stretch animation.
  - A fixed-direction highlight + undershade (`_shading`) sells a "glossy
    sphere" look. Critically, this lives OUTSIDE `Visual` - if it were a
    child of `Visual` it would spin with `_roll_angle` every frame, which
    would look like the light source orbits the ball as it rolls instead of
    staying put. `_update_visual()` still has to counter-scale it
    (`1.0 / visual.scale.y`) so a landing squash/launch stretch doesn't
    warp the highlight into an oval - the impact should read on the ball's
    silhouette, not smear the fixed light cue.
  - A squashed shadow ellipse (`_shadow`) is pinned under the ball's current
    x at actual ground height (`terrain.height_at(x) - position.y`, which is
    ~0 when grounded per the floor_snap_length gap notes above), shrinking
    and fading out with air height. Classic 2D-platformer depth cue - lets a
    jump's height and landing spot read at a glance without needing real
    3D shadow casting.
  - A real `PointLight2D` (`_glow`, ADD blend, a procedurally-generated
    radial `GradientTexture2D` rather than an image file) whose color tracks
    the exact same `normal_color.lerp(flow_color, flow)` tint the ball's
    `modulate` already used - so building Flow doesn't just recolor the
    ball, it visibly warms the light it casts on nearby ground. Ties a new
    visual system to an existing gameplay stat instead of decorating in a
    vacuum.
- **Background** (new `scripts/Background.gd`, instanced by `Main._ready()`
  and `move_child()`'d to index 0 so it draws behind Terrain/Player - same
  "one script, every scene" pattern as Terrain.gd, so neither .tscn needs
  its own copy): a screen-fixed sky gradient in a `CanvasLayer` at
  `layer = -10` (screen-space, so it always fills the viewport regardless of
  camera zoom/position - a world-space node would need constant resizing to
  guarantee full coverage) plus two `ParallaxBackground`/`ParallaxLayer`
  rows of hill silhouettes at different `motion_scale` for depth. Each hill
  shape sums a couple of sine harmonics over one `TILE_WIDTH` period and
  relies on `motion_mirroring` to repeat it forever along the course's
  x-axis - the harmonics are exactly periodic on that width by construction
  (`sin(h * TAU * x / TILE_WIDTH)` is identical at `x=0` and `x=TILE_WIDTH`
  for any integer `h`), so the tile repeats with no visible seam without
  needing a hand-authored, course-length-matched shape.
- **Ambient tint**: a `CanvasModulate` added by `Main._ready()` (world-space,
  alongside Background) applies a very subtle warm-neutral multiply over
  the whole scene. `CanvasModulate` only affects nodes on its own canvas,
  not separate `CanvasLayer`s, so the UI (already its own `CanvasLayer` for
  unrelated reasons) is untouched - confirmed headlessly by walking
  `Main`'s child list and checking `UI` sits in its own layer, not under the
  modulated world-space branch.
- **Speed trail** (`scripts/TrailEffect.gd`, a script on a standalone
  `Line2D` instantiated by `Player._make_trail()`): in a silhouette-based
  game with no sprite animation, speed has no other visible "juice" signal,
  so this is deliberately the loudest visual in the game. `top_level = true`
  lets it live as a child of Player (freed automatically with the ball)
  while its `points` stay in WORLD space, immune to Player's own
  position/rotation. Length is a free side effect of speed itself: it just
  samples the ball's last `history_length` physics-frame positions every
  frame via `update(world_position, speed)`, and a faster ball naturally
  covers more world distance between samples - no separate "how long should
  this be" logic exists. Width and alpha are the only things actively
  scaled with speed (`min_width`/`max_width`, `min_alpha`/`max_alpha`
  between `min_speed_for_trail` and `speed_for_max_effect`). `clear()` is
  called from `Player.reset()` so a restart doesn't draw a stale streak
  connecting the old run's last position to the new spawn point. Verified
  headlessly: alpha/width sit at their minimums at rest and ramp toward
  their maximums at speed, and the sampled points really do span a
  meaningfully longer world distance at ~850px/s than at rest.
- **Camera is its own script, attached at runtime.** The zoom/lookahead/
  landing-shake/launch-zoom-kick logic that used to live inline in
  `Main._process()` is now `scripts/CameraRig.gd`, attached to the
  *existing* `Camera2D` node (a child of Player, already placed in both
  `.tscn` files) via `camera.set_script(preload(...)); camera.init(player)`
  in `Main._ready()` - not a new node, so neither scene file needed editing.
  Everything about camera feel is now fully self-driven: `init(player)`
  stores the reference once, and CameraRig's own `_process()` polls
  `player.landing_event_id`/`launch_event_id`/`current_speed`/`velocity`
  every frame - Main.gd's only remaining contact with the camera is that one
  `init()` call and `camera.reset_camera()` on restart. **Real bug caught
  here, worth remembering**: `set_script()` on an already-`_ready()` node
  does NOT retroactively enable `_process()` - Godot only auto-turns on
  per-frame processing once, during the ORIGINAL script's
  `NOTIFICATION_READY`, before this script ever existed on the node.
  Without an explicit `set_process(true)` inside `init()`, CameraRig looked
  completely wired up (script attached, fields set) but silently never
  ticked - caught headlessly by watching zoom/position stay frozen at their
  init() values while `player.current_speed` visibly climbed in the same
  test. (A speed-scaled directional streak-blur/chromatic-aberration
  overlay briefly lived here too, built from a `shaders/streak_blur.gdshader`
  full-screen `ColorRect`+`ShaderMaterial` - removed after the user found
  the blur-at-speed effect undesirable. `UI`'s `CanvasLayer.layer = 10` in
  both `.tscn` files predates that removal and is now just an explicit,
  harmless value rather than a real ordering requirement - no need to touch
  it back.)
- **Time-of-day / biome palette** (`scripts/TimeOfDayPalette.gd`, a
  `Resource` subtype with `sunrise()`/`day()`/`dusk()` static presets, plus
  `scripts/PaletteController.gd`): one `apply_preset()` call recolors sky,
  background hills, terrain's `ground_color`, the rim highlight, and the
  ambient `CanvasModulate` tint together - swapping the whole game's mood is
  one call, never a per-system reskin or an asset swap. Deliberately does
  **not** touch any gameplay-communicative color (the six zone accents, the
  ball's Flow tint) - a palette is environment mood, not a gameplay reskin,
  same reasoning `Terrain.gd` already documents for why zone colors need to
  stay unambiguous. `Main.gd` exports `time_of_day: PaletteController.Preset`
  so each scene can eventually pick its own default (both currently ship on
  `DAY`, i.e. every value identical to what Background/TerrainRenderer
  already hardcoded, so this is a no-op visually until something actually
  switches presets). Applying a palette calls `Background.refresh()` /
  `TerrainRenderer.refresh_colors()`, which tear down and rebuild just the
  visual fill from current color exports - cheap since it only happens on a
  preset switch, never per-frame.
  - **`class_name` exception, deliberate and narrow**: every other script in
    this project is referenced by node path/type annotation, never a global
    class name (matches the rest of this file's low-machinery style). These
    two scripts are the one place that changes: `TimeOfDayPalette` needs to
    be `.new()`-constructed from its own static factory methods, and
    `PaletteController` needs its nested `Preset` enum to be a real type
    `Main.gd` can export as an Inspector dropdown - both are exactly the
    case Godot's own convention recommends `class_name` for (custom Resource
    subtypes, and a type another script needs to reference). Don't spread
    `class_name` to other scripts without the same kind of concrete need.
  - **Another editor-pass gotcha, same family as the `.uid` one at the top
    of this file**: a fresh `class_name` declaration isn't visible to a
    plain `--headless` run until an actual editor pass
    (`--headless --editor --quit-after N`) has registered it into
    `.godot/global_script_class_cache.cfg` - a brand new `TimeOfDayPalette`/
    `PaletteController` reference failed with "Could not find type... in the
    current scope" under plain `--headless` right after being written, and
    only started resolving once that cache existed. Critically, `rm -rf
    .godot` (the very command CLAUDE.md tells you to run before every
    validation pass, to force a clean reimport) wipes that cache right back
    out - so after adding or renaming a `class_name`, the editor pass has to
    run again, and it has to be the step immediately before whatever
    `--headless` run needs the class resolved, not just "once, ever."
- Verification here is necessarily partial: this environment has no
  display, so headless testing can confirm the scene builds without errors,
  the new nodes exist with sane values (shadow alpha shrinking with height,
  glow color actually shifting toward `flow_color` as Flow rises, tile
  seams matching exactly at the math level, trail width/alpha/length
  scaling with speed, camera zoom/lookahead all actually changing per-frame,
  all three palette presets recoloring the right fields
  while leaving zone accents untouched), and - most importantly - that none
  of it touched the physics/collision path (re-ran the full 4-policy
  benchmark on both levels after every pass in this section; every number
  matched the pre-visual-pass baseline exactly every time, confirming zero
  physics regression). Whether it actually looks good is necessarily the
  user's own call on their device, the same limitation noted for the
  LevelButton fix above.

### Persistence, Ghosts, and Level Unlocks

The user's explicit ask: a highscore system with cross-session ghosts to race
against ("race against ghosts from the best time on each map") and
Trackmania-style progression ("levels unlocked by being faster than the
bronze time, so the 3rd place of benchmarks"). This is the first real
persistence this project has ever had - previously `_best_time` in Main.gd
was deliberately session-only ("just gives restart-and-retry a sense of
progress"); that design choice is gone now, replaced by an actual save file.

- **`scripts/SaveManager.gd`** (new autoload, `SaveManager` in
  `project.godot`): the single source of truth for per-level best time + best
  run's ghost recording, persisted as plain JSON at `user://savedata.json`.
  `record_result(level, time, ghost_frames)` is the only write path and
  refuses to overwrite a stored time with a worse one - Main.gd doesn't do
  its own "is this better" comparison before calling it, so there's exactly
  one place that decision can ever be made incorrectly. A missing/corrupt
  save file is treated as "fresh save," not an error - this is a
  single-player prototype, not something that needs migration/versioning
  machinery.
- **`scripts/Medals.gd`** (new autoload, `Medals`): gold/silver/bronze time
  thresholds per level, plus `medal_for(level, time)`. An autoload, not a
  `class_name` Resource - deliberately NOT extending the narrow `class_name`
  exception documented under Visual Presentation above (that's reserved for
  `TimeOfDayPalette`/`PaletteController`'s specific Resource-subtype/exported-
  enum need); a plain lookup singleton fits the same pattern SaveManager
  itself already uses, so it stays consistent instead of adding a second kind
  of cross-script reference to the project.
  - **The thresholds were MEASURED, not guessed** - a throwaway 4-policy
    headless bot (perfect tangent-tracking / "decent" - tangent-aware but a
    consistent small angle error and slightly reduced magnitude / "randomish"
    - tangent-aware with real per-frame angle+magnitude noise / "poor" - weak,
    barely slope-aware input) raced both existing levels start to finish, same
    "measure, don't guess" spirit as every other constant in this file. First
    attempt at "decent"/"randomish"/"poor" used a fixed off-angle lean vector
    that fought the slope on many segments instead of roughly tracking it -
    that policy design was unrealistic enough that even "decent" arrived at
    the level-1 terrain gap under ~500px/s and reliably died there forever
    (a genuine infinite death-loop, caught via per-policy position/velocity
    tracing, not a bug in the death/respawn system itself - the checkpoint
    positions were already correct). Redesigned the weaker policies to still
    roughly track the ground tangent (with error/noise/reduced magnitude
    layered on top, not replacing it) and to commit to a clean, well-aimed
    approach specifically in the 500px before any known gap and full
    velocity-aligned air control while airborne over one (a real player lines
    up a landmark gap deliberately even if their general technique elsewhere
    is sloppy) - with that fix, perfect/decent/randomish all finish both
    levels cleanly and "poor" reliably dies at the gap and DNFs, a believable
    bronze-miss baseline. Results (level 1 / level 2): perfect 16.2s / 30.9s,
    decent 17.8s / 34.3s, randomish 24.8s / 48.9s, poor DNF / DNF. Bronze is
    set at the 3rd-place *finishing* policy's time (randomish) with a small
    rounding buffer, per the user's explicit "3rd place of benchmarks"
    framing; gold/silver sit at/above the perfect/decent times the same way.
    This bot was throwaway scaffolding (per this file's own headless-testing
    rules) and was not committed.
- **`scripts/Ghost.gd`** (new): a visual-only, collision-free replay of a
  level's best run - a translucent circle (same radius as the ball) that
  walks through a recorded array of `[x, y, roll_angle]` triples, one triple
  per physics frame.
  - **Real height bug found and fixed via playtest feedback**: the ghost
    rendered noticeably too low and hard to see. Root cause was a missing
    offset, not a visibility-only issue - Main.gd's recorded `[x, y, ...]`
    triples use `player.position.y`, which is the ball's GROUND-CONTACT
    point by convention, not its visual center (`Player`'s own `Visual`/
    `CollisionShape2D` nodes sit at a local `(0, -20)` offset from that
    point - see `PLAYER_GROUND_OFFSET`'s comment in Main.gd). `Ghost.gd`'s
    circle was drawn at local `(0, 0)`, i.e. centered exactly on the
    recorded ground-contact y instead of `RADIUS` px above it - about half
    the circle sat below the actual terrain surface, both reading as "off
    in height" and getting hidden behind the ground fill (the ghost's
    `z_index = -1`, same as the ball's own shadow, only stays invisible-free
    of the terrain because it sits in the open space above the surface -
    Player._make_shadow() proves that z at the correct height is fine).
    Fixed by giving the ghost's `Polygon2D` the same `(0, -RADIUS)` local
    offset Player's own Visual uses, so the two conventions finally match -
    verified headlessly that the ghost's resulting world-space y for a given
    recorded frame now lands exactly at `recorded_y - RADIUS`, the same
    place the real ball's visual center would be for that position.
  - Separately, also raised opacity (0.5 -> 0.8) and added a bright
    `Line2D` rim outline, since even correctly positioned a pale translucent
    blue circle read as faint against this project's similarly pale-blue
    sky/hill palette (see Background.gd) - the outline keeps the silhouette
    readable regardless of what's directly behind it.
  - Deliberately frame-indexed rather than time-indexed:
    Main.gd's new `_physics_process()` records the live run's own position into
    `_ghost_recording` on the exact same physics tick it calls
    `_ghost.advance_frame()`, so recording and playback share one clock by
    construction - no separate interpolation/timing-drift logic needed, and a
    faster or slower live run naturally pulls ahead of or falls behind the
    ghost exactly like racing a real recorded lap. The ghost does NOT reset on
    death (`_on_death()` never touches it) for the same reason `_elapsed`
    doesn't: both stay in lockstep with the live run through a death exactly as
    they do through the rest of it. It does reset on an explicit Restart (`
    _ghost.stop()`, restarting again from frame 0 once the next attempt's timer
    starts), matching the live run's own full reset there.
- **Level unlock gate**: `SaveManager.is_level_unlocked(level)` - level 1 is
  always unlocked; level N (N>1) needs level N-1's best time at or under
  `Medals.bronze_time(N-1)`. Wired into the existing `LevelButton` rather
  than a new menu screen (still off-limits per the top of this file): the
  button's label now shows "(Locked)" when the target level isn't unlocked
  yet, and pressing it while locked shows the existing one-shot event banner
  (already used for CHECKPOINT/DIED) naming the bronze time still needed,
  instead of swapping scenes. `_update_level_button_label()` is called both
  at `_ready()` and right after a new best time is recorded, since crossing
  bronze on THIS run should unlock the next level's button immediately, not
  just after a scene reload.
- Verified with a real full-course headless run through the actual game (not
  a synthetic isolated check): a finished run persists via the real
  `_on_end_zone_body_entered` path, a deliberately-worse fake repeat result
  does not overwrite it, a deliberately-better one does, the level-2 unlock
  flips from false to true the instant level 1's bronze is beaten (with the
  button label updating in the same frame), a freshly-built `Ghost` loaded
  from the saved recording advances through every frame without erroring and
  correctly hides itself once its recording runs out, and a real
  `change_scene_to_file` level switch through the now-unlocked button lands
  on the correct level. Re-ran the standard clean-reimport + both-scenes
  smoke test afterward per this file's own validation rules - no errors on
  either level.
- **Level 3** (`Terrain._level_3_keyframes()`/`_level_3_zones()`/
  `_level_3_gaps()`/`_level_3_checkpoints()`, `scenes/Level3.tscn`): the third
  step toward the user's larger 10-level ask, built with the same rigor as
  levels 1/2 rather than guessed. Longest course yet (`course_end_x` ~23800,
  vs level 2's ~19300), and deliberately harder in the ways level 2 already
  established work: two bhop corridors (corridor 1 ~48deg peak/4 cycles,
  corridor 2 ~47deg peak but 8 cycles - the longest sustained bump stretch in
  the game), a longer flow gauntlet (7700px vs level 2's 6300px, same
  ~28-32deg peak angles level 2 already proved hold Flow uninterrupted), one
  ice patch, one mud patch, one launch pad, two boost pads, and - the one
  genuinely new element - **two** terrain gaps instead of one, both 300px
  (the width established as the minimum that can't be crossed on momentum
  alone - see "Gaps, Death, and Checkpoints" below).
  - Both gaps sit inside deliberately long, fully flat runs (500-900px of
    flat ground before each - gap 1 at 9000-9300 inside the 8600-9500 flat
    stretch after crest 2, gap 2 at 21900-22200 inside the 21400-22400 flat
    stretch after bhop corridor 2) - this is MORE generous than level 1/2's
    gap placements, deliberately, so a longer/harder course doesn't also
    stack a tighter jump-timing window on top of everything else that's
    already harder about it.
  - All 7 checkpoints (2250, 5750, 7200, 8850, 13650, 17850, 21750) were
    verified headlessly against the exact "cresting" re-grounding bug found
    and fixed on Level 2's original 17950 checkpoint: reset the player at
    each one and count frames until `is_on_floor()` re-establishes. All 7
    came back at 0 frames - unlike level 2, none needed moving.
  - Verified with a real full-course headless run (not synthetic): a
    tangent-tracking bot that jumps once per gap from the flat run just
    before it (matching the established "jump from flat ground, not while
    still climbing" finding) finishes clean with zero deaths in 39.2s. A
    control run with the identical lean policy but jumping disabled reliably
    dies at gap 1 (~x=8850, right at the gap mouth) - confirming the gap
    genuinely requires a real jump, momentum alone doesn't clear it. Landing-
    event tracing also confirmed no unwanted bounce on ordinary slopes
    outside the bhop corridors/gaps/launch pad (only 3 "extra" landings
    outside the two bhop corridors, and they're fully accounted for: the one
    launch-pad landing plus the two gap-jump landings, not stray bounce).
  - Medal thresholds measured with the same 4-policy bot as levels 1/2, with
    one real difference worth recording: on levels 1/2, "poor" DNFs (dies
    repeatedly at the gap); on level 3, thanks to the more generous flat-run
    gap placement above plus the same "commit to a clean aimed approach in
    the final 500px before a gap" concession every policy gets, "poor"
    actually clears both gaps too - it's still a believable bronze-miss
    baseline, just via being dramatically slower overall (276.2s vs 39.2s
    perfect) from weak technique on the rest of the course, not a literal
    gap death. The "3rd place of benchmarks" rule still applies identically:
    all four policies finished, so bronze = randomish's time (the 3rd
    finisher), same rule as levels 1/2, just a different route to the same
    ranking. Measured: perfect 39.2s, decent 56.1s, randomish 66.3s, poor
    276.2s (zero deaths on every policy). Thresholds set the same way as
    levels 1/2 (gold/silver near perfect/decent with a small buffer, bronze
    at randomish's time with a small buffer): gold 40.0, silver 57.5,
    bronze 68.0 - see `Medals.gd`.
  - **LevelButton generalized from a 2-level toggle to an N-level cycle**:
    with a 3rd level, the old `_update_level_button_label()`/
    `_on_level_button_pressed()` logic (hardcoded `2 if terrain.level == 1
    else 1`) would have sent Level 2's button backward to Level 1 instead of
    forward to Level 3. Replaced with `(terrain.level % TOTAL_LEVELS) + 1`
    (a new `Main.gd` const, bumped as levels are added) plus a
    `_scene_path_for_level()` helper (level 1 -> `Main.tscn`, level N>1 ->
    `Level%d.tscn`) so the button now cycles forward through however many
    levels exist and wraps back to 1 after the last, instead of only ever
    toggling between two. Verified headlessly across all three scenes: level
    1's button reads "Level 2", level 2's reads "Level 3 (Locked)" (level 3
    correctly gated on level 2's not-yet-beaten bronze time), level 3's
    reads "Level 1" (wraps around) - and all three scenes still boot with
    zero errors.
  - Re-ran the standard clean-reimport smoke test on all three scenes after
    every change in this section (terrain, medals, button logic) per this
    file's own validation rules - no errors on any level, and levels 1/2's
    own numbers are untouched since none of the shared Player.gd/Joystick.gd
    physics logic changed, only new level-3-only data and a strictly-additive
    `Main.gd` generalization.
- **Level 4, "Grapple Gauntlet"** - the user's explicit ask: a level where
  "the majority is grapple only, so from 1 grabbed to the next one without
  anywhere to roll on... by far the majority of the map." A genuinely
  different KIND of level from 1-3, not just harder terrain: there is no
  hill content at all. `_level_4_keyframes()` is flat at y=600 for the
  entire course; every bit of real, rollable ground lives in ten short
  platforms (spawn, eight rest platforms, finish) that `_build_ground()`
  leaves standing between nine `gaps` entries - everywhere else is a real
  hole, exactly like every other gap in this game, just far bigger and far
  more of the course (~78% void by construction - see
  `LEVEL_4_VOID_WIDTH`/`LEVEL_4_CYCLE_WIDTH`). Each void section is crossed
  by chaining 3 grapple points together (27 points total), landing on the
  next rest platform's checkpoint before diving into the next void.
  - **Point spacing and chain length were MEASURED, not guessed, via a long
    sequence of headless prototypes** - see `_level_4_grapple_points()`'s
    doc comment in Terrain.gd for the full blow-by-blow (spacing sweep,
    release-timing sweep, several rejected fixes). The short version: an
    isolated test chain established 300px spacing with release timing
    20-30% of the rope's length past the bottom of the arc as a reliably
    completable pattern (real margin, not a knife's edge) for chains up to
    ~12 points; a real full-COURSE run then needed shorter (3-point)
    sections to stay safely inside that margin over a much longer 27-point
    chain.
  - **The real, hard-won discovery: a full course run kept failing at the
    very last swing of every section, and it took a proper root-cause trace
    to find why.** The failure looked like a level-design problem (wrong
    spacing, wrong timing) but was actually a TERRAIN problem: a rope swing
    with no reel-in mechanic naturally sinks 250-400px below its own anchor
    by the time of release (confirmed directly in a headless trace, and
    confirmed again that a small release-timing fraction only recovers a
    tiny fraction of that height - a pendulum only truly climbs back near
    its entry height swinging almost all the way to the far side, not at
    20-30% past the bottom). Every existing gap in this game has a sheer
    vertical wall at its edge (fine for a JUMP arcing in from above, which
    is how every other gap in levels 1-3 is crossed), but a swing release
    approaches LOW, from underneath that edge - so the ball was slamming
    into the platform's leading edge like a wall (caught unambiguously in
    the trace: `velocity.x` snapped from ~460 to exactly `0.0` in a single
    frame at the platform's edge) and either sticking there or sliding
    beneath it into the void, never once reaching the top, no matter how
    the spacing, buffer size, or anchor height were tuned - because none of
    those addressed the actual cause.
  - **The fix: a real sloped landing ramp into every platform** (`
    LEVEL_4_RAMP_LENGTH`/`LEVEL_4_RAMP_RISE`, added via two extra keyframes
    per platform - `_level_4_keyframes()`), using the exact same smoothstep
    curve interpolation every other slope in this game already relies on.
    A low, sunk approach now rolls up the ramp onto the platform instead of
    crashing into a wall - the same fix a real platformer reaches for when
    an approach comes in from below a ledge. Only needed on the ENTRY side
    of each platform; the exit side was never the problem (leaving a
    platform under normal rolling control is the same well-tested pattern
    used everywhere else in this game). The ramp is ADDED after the void,
    not carved out of it, so the actual swing-chain distance and the last
    grapple point's position over open air are completely unchanged - the
    fix only changes what's waiting at the far end.
  - **Verified headlessly, and this time it's a real pass, not a near-miss**:
    all 8 checkpoints re-establish `is_on_floor()` within 0 frames of a
    reset. A full-course chain-swing bot using release timing 25%, 30%, and
    35% (three different values, not one lucky number) all cleared the
    entire 27-point course with **zero deaths**, in 54.3s/56.6s/59.0s
    respectively - confirming a real margin exists, not a razor's edge.
  - **Medal thresholds measured with a 4-policy bot adapted for this
    level's actual skill expression** - since there's no ground to
    lean-track in a void, skill here is release-TIMING precision and
    consistency instead: perfect hits the validated release window exactly
    every time, decent/randomish add growing timing jitter around it, poor
    is centered on a genuinely too-early release (the realistic novice
    mistake this level actually punishes, not just noise) plus jitter.
    Measured: perfect 54.3s, decent 53.9s, randomish 56.5s (1 death), poor
    DNF (23 deaths, still retrying at the frame budget) - a believable
    bronze-miss baseline, same pattern as every other level. Bronze set at
    randomish's time (3rd-place-of-benchmarks), same rule as levels 1-3.
    See `Medals.gd` for the numbers (gold 55.0, silver 58.0, bronze 60.0).
- Levels 5 through 10 don't exist yet and are the next planned increments
  toward the user's 10-level ask, each needing the same treatment levels
  1-4 got (hand-tuned layout, headlessly-verified physics, measured medal
  thresholds) - substantial additional work, planned as further incremental
  commits one level at a time rather than invented wholesale in one pass,
  the same way each of levels 1-4 were built as separate efforts rather
  than all at once.

### Grapple Points

The user's explicit ask: "add a grapple effect and then adjust the level
designs so they match the abilit[y]." See "Grapple" under Movement design
below for the swing physics itself (Player.gd) - this section is the
world/terrain side of it: where the anchor points live and how they're
drawn.

- **`Terrain.grapple_points: Array[Vector2]`** (new) - world positions a
  grapple can attach to. A plain array of points, not a `{start, end}` zone
  dict like ice/mud/boost/etc., since an attach point is a single location,
  not a range - populated per-level in `_configure_level()` the same way
  gaps/checkpoints are, via `_level_N_grapple_points()` functions.
- **Placement is deliberately additive, not a replacement for the existing
  gap-jump challenge.** Every gap-jump width/checkpoint position/medal time
  documented under "Persistence, Ghosts, and Level Unlocks" above was
  measured against a jump-only 4-policy bot - if a gap became a *mandatory*
  grapple crossing, every one of those numbers would need re-measuring, and
  a whole new "poor" baseline would need establishing for a mechanic that
  didn't exist when bronze was set. One grapple point floats above each of
  the game's four gaps (one on level 1, one on level 2, two on level 3),
  positioned 220px above the flat run's height so it's a genuine swing
  rather than a trivial hop, and comfortably within `Player.grapple_max_range`
  (600px) from anywhere along that flat approach - giving a player who's
  unlocked the ability a faster/flashier alternative to jumping, without
  changing what jumping alone already reliably accomplishes. The existing
  jump-only benchmark bots (and their medal times) are untouched by
  construction - they never call `try_grapple()`, and confirmed headlessly
  to still finish in exactly the same time as before this feature existed
  (level 3's perfect-policy time matched to the millisecond: 39.20s both
  before and after).
- **Expanded to "a lot of spots" on a direct follow-up ask.** The first pass
  above only put a grapple point at each gap - the user came back and
  explicitly asked for "a lot of grappling spots all around the maps, so it
  becomes a choice in a lot of places," not just at the one crossing every
  level already had. Each level now has a point over (or near) every zone
  with real traversal weight - the ice valley, the mud valley, each bhop
  corridor, plus the gap point(s) - same 220px-above-local-ground rule as
  the original points, so every one is still a genuine swing, not a trivial
  hop: level 1 went from 1 point to 4, level 2 from 1 to 6, level 3 from 2
  to 7 (see each level's `_level_N_grapple_points()` for the exact
  coordinates and per-point reasoning). The one deliberate exception: each
  level's flow gauntlet (the long, gentle-hill zone built specifically for
  *sustained, uninterrupted* grounded contact - see the flow-zone note under
  "Level 2" below) gets exactly ONE point, positioned to swing over a single
  hill's dip rather than the whole gauntlet, so the new points add choice
  without undercutting the one zone whose entire design purpose is staying
  on the ground. Verified headlessly on all three levels: every one of the
  17 points now in the game engages cleanly from a realistic approach
  distance, swings with a stable rope (no NaN, distance never runs away from
  the nominal length), and - same check as before - the jump-only benchmark
  bot's finish time is unaffected by the added data (level 1 and 2 matched
  their prior times exactly; level 3 was within a single physics frame,
  ordinary run-to-run noise on a ~2360-frame simulation, not a regression).
- **`TerrainRenderer._add_grapple_markers()`** draws a small ring + center
  dot at each point (vivid cyan, `grapple_point_color` - distinct from every
  zone accent color, and matching `Player.grapple_rope_color` so the rope
  and the point it's attached to visually read as the same system) plus a
  thin translucent guide line straight down to the ground, so a point
  floating in open air still reads as anchored to the course rather than
  randomly placed - same visual language the rim highlight already uses for
  the ground curve, just for a point instead of a line. Rebuilt alongside
  every other visual in `_rebuild()` (including on a palette
  `refresh_colors()` call), so it can never desync from the rest of the
  ground fill.
- No aiming reticle or second stick - `Player.try_grapple()` just grabs the
  *nearest* point in `terrain.grapple_points` within `grapple_max_range` of
  the ball's current position, matching this project's low-machinery stance
  on UI (there's nowhere to add a second input without crowding the existing
  joystick/Jump/Restart/Level button layout, and one point in easy reach at
  a time is all any level currently has anyway).

## Movement design (as of this writing — check `Player.gd` for the actual
## current formulas, this is a summary not a source of truth)

- Accel scales linearly with lean magnitude; top speed scales with lean
  magnitude raised to an exported exponent (steep curve — committing to
  near-full lean unlocks disproportionately more speed than moderate lean).
- Velocity persists independent of lean; a friction constant bleeds
  ground-speed every physics frame regardless of input.
- Lean force is applied along the actual ground tangent (not a fixed
  world-horizontal axis), so slope matters, not just "how hard forward."
  The tangent itself comes from `Terrain.tangent_at(x)` - an analytic
  derivative of `height_at()` - rather than `get_floor_normal()`. Switched
  after the ball-visual conversion made a real, pre-existing roughness
  problem visible for the first time: `get_floor_normal()` turned out to
  be genuinely noisy frame-to-frame against the collision polygon (up to
  ~1.5deg of sign-flipping jitter per frame on an ordinary slope, even
  after quadrupling the polygon's sample resolution - so not a segment-
  quantization artifact, something in how Godot resolves contact normals
  for a rolling `CircleShape2D`). That noise fed straight into the
  acceleration direction and speed ceiling every frame - invisible on the
  old humanoid, whose tilt only ever reflected lean input, but a real
  source of choppy movement once the ball's spin started tracking actual
  physics output every frame. `height_at()` is itself perfectly smooth
  (every keyframe is a zero-slope point by construction, per the
  smoothstep note above), so differentiating it directly gives an
  exactly-as-smooth tangent by definition, independent of collision
  polygon resolution. Verified headlessly: frame-to-frame tangent-angle
  and velocity deltas on an ordinary curved slope went from erratic
  sign-flipping noise to a clean, continuously-varying curve; the full
  4-policy benchmark and the launch pad/bhop-section checks all came back
  materially unchanged (times/launches/chain all consistent with before).
  Also switched the launch pad's impulse direction to derive from this
  same tangent (it previously read `get_floor_normal()` directly) so
  every use of "the ground direction" in a single frame agrees.
- Acceleration toward the speed ceiling is capped to the remaining
  headroom each frame (`min(accel_force * delta, headroom)`) rather than
  added-then-clamped-back-down - the old approach snapped velocity to
  exactly the ceiling every frame it was reached, which combined with
  friction pulling a little off that same ceiling every frame regardless
  into a repeating oscillation right at the ceiling. Investigated as part
  of the same smoothness pass above; capping to headroom makes the
  approach asymptotic (settles at whatever equilibrium each frame's capped
  step offsets that frame's friction loss) instead of oscillating between
  overshoot and clamp.
- The player's lean *angle* is expected to track the slope: pointing the
  stick down-and-forward on a downhill and up-and-forward on an uphill is
  mechanically rewarded over just holding a flat push-forward. Getting this
  wrong isn't a hard clamp to zero — it's a smooth effectiveness penalty.
  A note from tuning this: the angle-mismatch penalty and the exponential
  top-speed curve compound multiplicatively, and on a steep uphill with
  weak/unaimed input this crushed the ceiling to a near-crawl (~38 px/s in
  testing) - not literally zero, but close enough to read as an effective
  soft-lock, which cuts against the "no hard clamp to zero" principle even
  though no single mechanic was "wrong" on its own. Fixed with
  `min_ceiling_with_any_lean` (a small absolute floor whenever there's any
  real lean intent) rather than touching the exponent or alignment formula
  themselves - both are deliberate, explicitly-requested design elements.
  If tuning this system further, a 3-tier bot benchmark (perfect/decent/
  poor simulated policies racing the same course) is the fastest way to
  check that skill differentiation stays meaningful without any policy
  soft-locking - see git history around the `min_ceiling_with_any_lean`
  commit for the harness.
- Downhill and uphill passive gravity assist use independent coefficients
  (`gravity_slope_assist_downhill`/`_uphill`), not one shared value.
  Playtest feedback said downhill rolling felt too weak - a real ball
  should visibly pick up speed on a slope with zero lean input. Raising
  the old single shared `gravity_slope_assist` (0.2) high enough to fix
  that reopened the `min_ceiling_with_any_lean` soft-lock from above: a
  strong enough passive term let gravity's drag on a climb overpower a
  weak/badly-aimed uphill lean's tiny `accel_force` and stall it near 0,
  since the passive term applies unconditionally every frame regardless of
  the ceiling logic (the ceiling only bounds the *active* accel step, it
  doesn't protect against a strong enough opposing passive force). Caught
  with the exact same weak-uphill headless check used to find the original
  soft-lock. Splitting the coefficient fixed it cleanly: uphill drag is
  now byte-for-byte the original 0.2 (re-verified identical time-to-crest
  and no stall), while downhill can roll as strong as feels good (0.6)
  with zero uphill risk, since the two no longer share a value at all.
- Leaning hard, in any direction, for any length of time, never cuts speed
  or locks out input by itself - the only consequence of a *bad angle* is
  the smooth effectiveness penalty above. This used to also mean there was
  no fall/wipeout mechanic at all; that's no longer true since the user
  asked for the game to be more punishing - see "Gaps, Death, and
  Checkpoints" below. The distinction that survives: bad *technique* (angle,
  timing) is still never a hard clamp to zero, but a bad *landing* now
  scrubs a lot more speed than it used to, and missing a jump over an actual
  gap is real death, not a speed penalty.
- The lean/alignment formulas are symmetric: leaning backward and matching
  the reverse direction is exactly as effective as leaning forward. A
  sustained hard reverse lean therefore builds real speed the same way
  forward play does, which is enough to blow through the runway buffer
  behind spawn (or overshoot the finish straight the same way going
  forward) and fall off the edge of the terrain into open space - an
  unbounded fall with no recovery, found via a hard-reverse-lean stress
  test, not something a normal test of forward play would ever surface.
  Fixed with a universal safety net in Main.gd: if the player's y ever
  exceeds `terrain.lowest_surface_y() + FALL_RECOVERY_MARGIN`, it's
  treated as having fallen off the world - this catches either edge, a
  missed gap jump, or any future terrain gap, without needing a
  precisely-tuned boundary wall. It used to trigger the same full reset as
  the Restart button; now it triggers death/checkpoint-respawn instead (see
  "Gaps, Death, and Checkpoints" below) - the catch itself didn't change,
  only what happens once it fires. Worth re-running a sustained-reverse-lean
  test after any terrain layout change, since a longer/differently-shaped
  course could shift where this matters.
- The finish end had the same class of problem from ordinary play, not just
  a stress test: there's deliberately no results screen, so crossing the
  end-zone only stops the timer - it doesn't freeze the player. But the
  actual ground polygon used to stop exactly at `course_end_x()`, with only
  Main.gd's small `END_ZONE_MARGIN` (100px) of flat buffer beyond the
  trigger - under 0.2s of travel at the 1000+ px/s this course produces. A
  player who crosses the line without instantly releasing the stick (i.e.
  nearly everyone) would run clean off the true edge a moment later and
  silently trigger the fall-recovery reset above, wiping a run that had
  just finished. Found the same way as the reverse-lean fall: by continuing
  to feed forward lean past the finish in a headless test instead of
  assuming play stops the instant the line is crossed. Fixed with
  `Terrain.finish_runway`: `_build_ground()` extends the physical polygon
  that much further past the last keyframe, flat, purely as a safety
  buffer - `course_end_x()` still returns the original keyframe position
  unchanged, so the finish line itself doesn't move and normal race times
  are unaffected (bots/players that ease off at the line never reach the
  extra ground). Same pattern already used for the runway behind spawn,
  applied to the other end of the course.
- Flow state: technique compounds instead of resetting between sections.
  Landing a jump redirects velocity onto the new slope's tangent, scaled by
  how well your airborne velocity matched it — land clean, keep/gain speed;
  land sideways, lose some, but always a clean tunable multiplier, never a
  double-penalty from also colliding with the floor. Separately, a Flow
  meter (HUD bar) builds from sustained well-aimed lean and raises your
  accel/ceiling while it's up, fading if technique lapses or you go
  airborne — so a good stretch of riding makes the next stretch faster too.
  Which of the two tangent directions a landing/launch redirects onto is
  chosen by the sign of `velocity.dot(tangent)` (along-slope direction), not
  raw `velocity.x` (world-x) - they can disagree on a steep slope, since a
  jump impulse is added along the floor *normal*, which has its own
  x-component. Using world-x let a single ambiguous frame (barely-negative
  world-x while still clearly traveling forward along the tangent) throw the
  *entire* speed magnitude onto the wrong tangent, discovered via a headless
  bot combining aimed lean with repeated jumping that got stuck oscillating
  on hill 1's climb forever, at real speed (600-800 px/s), never actually
  progressing - not a smooth penalty like every other system here, a full
  momentum reversal from one frame's noise.
- Trackmania/Quake-Defrag-inspired: launch quality is landing's symmetric
  counterpart — leaving the ground with velocity matching the slope you're
  leaving gives a small speed pop, leaving badly costs a little (mild
  either way, a launch isn't really a "mistake" the way a bad landing is).
  Separately, air control lets you build extra speed mid-air by pointing
  the stick along your current trajectory (not world-horizontal) - an
  air-strafe-style reward for aiming where you're already going instead of
  coasting passively through a jump.
- Manual jump: a JUMP button (bottom-right, thumb-opposite the joystick)
  adds `jump_impulse` along the *floor normal* (not world-up), so a jump off
  an incline pops away from the surface consistent with how lean/gravity
  already treat the real slope as the reference axis. Standard forgiveness
  pairing on top of the raw impulse: `coyote_time` lets a press just after
  walking off a ledge/crest still fire as grounded, `jump_buffer_time`
  queues a press made slightly too early (already airborne) to fire the
  instant you land, and `jump_cooldown` (kept above coyote_time) blocks
  re-firing across adjacent frames without needing separate double-jump
  bookkeeping. A buffered jump fires *after* that frame's landing-redirect,
  not before, so it reads as a hop off the landing instead of being
  immediately flattened back onto the tangent by that same redirect. A
  jump feeds into the existing launch-quality system exactly like a
  terrain-launched hop — aimed well with your current travel, same small
  bonus a clean crest pop gets. Verified via headless bot that spamming
  jump every grounded frame with zero lean can't grind out free downhill
  speed (a jump has no directional intent of its own without lean): that
  policy only covered 16% of the course in 90s, worse than the weakest
  lean-only policy.
- Bhop-style chain: consecutive good-quality landings within a few seconds
  of each other build a streak (HUD: "CLEAN Chain x3"), each link adding a
  capped bonus to the ceiling/accel on top of Flow - a gap that's too long
  or a bad landing resets it. Rewards stringing jumps together rather than
  landing once and coasting.
- Landing and launch quality each drive a brief one-shot visual (squash on
  a rough landing, stretch on a clean launch, both decaying back to
  neutral in a fraction of a second), so an impact/pop actually reads as a
  physical event instead of just a speed number changing a moment later.
  The same two events also
  drive camera feedback in Main.gd: a rough landing shakes `Camera2D.offset`
  (not `.position`, so the jolt is instant and independent of the eased
  lookahead lerp), and a clean launch briefly zooms the camera out
  (`MAX_LAUNCH_ZOOM_KICK`) as launch's mild, "not a mistake" symmetric
  counterpart to the landing shake — it only fires on good launches, never
  bad ones. Both track `player.landing_event_id`/`launch_event_id` rather
  than polling quality values, since quality alone can't distinguish "a new
  landing happened" from "no landing happened yet, still -1."
- The character also tints from `normal_color` toward `flow_color` as Flow
  rises toward 1.0, so Flow reads as a visible in-the-moment state on the
  character itself, not just a HUD bar you have to glance away to check.
- One low-friction ice patch (valley 1's floor, pale blue) and its
  opposite, one high-friction mud patch (valley 2's floor, brown) -
  `friction_decay` is scaled way down on ice (carry much more speed
  through it) and way up in mud (aggressively bleeds speed). Both are
  Trackmania-style momentum tests, but complementary: ice rewards/punishes
  how you *arrive* (coast far on good entry speed/aim, or slide out of
  control on a bad one), mud rewards/punishes how you *leave* (a
  consistently-leaning rider barely notices it since they're already
  accel-bound near their ceiling, not coasting on stored momentum - it's
  specifically the "built huge speed and now coasting passively" style of
  play that mud punishes). `Terrain.friction_multiplier_at(x)` is queried
  by Player.gd every physics frame while grounded; `Terrain.zone_name_at(x)`
  feeds an `[ICE]`/`[MUD]`/`[BOOST]`/`[LAUNCH]`/`[BHOP]`/`[FLOW]` tag onto the
  speed HUD readout (whichever `zones` entry covers that x - see
  Architecture) so a speed change is never ambiguous between terrain and
  technique. A generalized `_add_visual_segment` helper in Terrain.gd carves
  the ground visual into as many colored zones as needed while collision
  stays one unified polygon throughout.
- A Trackmania-style boost pad (a `"boost"`-type entry in `Terrain.zones`,
  electric yellow-gold) gives a one-shot flat multiplier
  (`Player.boost_multiplier`) to velocity's current magnitude the instant
  you enter it while grounded - unlike ice/mud (a continuous per-frame
  friction scale), it's an edge-triggered kick, same pattern as
  `_apply_launch`, gated by `_was_in_boost_zone` so it fires once per
  crossing, not every frame you're inside it. First placed on crest 2's
  flat top (right before hill 2's descent) as a reward for a good mud-patch
  climb, but a headless bot test caught a bad interaction: the extra speed
  sent the bot into a bigger arc off that descent, and the resulting worse
  landing angle fed straight into `_apply_landing`'s mismatch penalty,
  eating back most of the boost and making every simulated policy's overall
  time *worse*, not better - the boost mechanic worked exactly as designed,
  the placement just handed extra momentum straight to the one system built
  to punish exactly that. Moved to the flat run after the bhop section
  (x=8700-8900) instead, where there's no more terrain to launch off before
  the flat finish straight - re-verified with the same bot that it no
  longer goes airborne or gets scrubbed by a landing, and the full 4-policy
  benchmark came back at least as fast as the pre-boost baseline for every
  policy. Worth remembering for any future zone/pad placement: extra
  momentum dropped right before a crest or launch point can come back to
  bite you through the landing-quality system - a flat, launch-free runway
  is the safe kind of place to hand out free speed. (Level 1 keeps its one
  boost pad at x=8700-8900; level 2 has two, see the level-2 layout note below.)
- A launch pad (a `"launch"`-type entry in `Terrain.zones`, vivid spring
  green) is the terrain-triggered counterpart to the manual jump: an automatic pop
  along the floor normal (`Player.launch_pad_impulse`, same axis as
  `jump_impulse`) the instant a grounded player crosses it - no button
  needed. Same edge-triggered one-shot pattern as the boost pad
  (`_was_in_launch_pad_zone` mirrors `_was_in_boost_zone`), but adds impulse
  along the normal (a real launch) rather than scaling velocity's magnitude
  (a speed kick), so it feeds the existing launch-quality/chain systems the
  same way any other liftoff does. Placed on crest 1's flat top
  (x=3100-3200, well inside the 2900-3300 flat run) rather than right at
  either crest's edge, applying the lesson from the boost pad's placement
  mistake above - verified with a headless bot that the resulting arc lands
  back on flat/gently-curving ground (0.84 landing quality after ~1s of air)
  instead of getting dumped into a slope and eaten by the landing penalty.
- With jump, boost, and the launch pad all landed, ran a combined-systems
  stress test that calls `jump()` unconditionally on *every single physics
  frame* (60/sec) while also tangent-tracking lean perfectly, racing the
  whole course. It went chaotic: continuous mid-air bouncing, speeds past
  1500 px/s, and one run reversed hard enough to fly backward off the
  spawn-side runway. Root cause: calling `jump()` every frame keeps
  `_jump_buffer_remaining` perpetually re-armed while airborne (it only
  needs re-arming faster than `jump_buffer_time`, 0.12s), so literally
  every landing gets an automatic instant re-launch before the character
  ever settles, and a landing redirect off a chaotic bounce can legitimately
  point in an unexpected direction. Turned out to be unreachable in
  practice, not a bug to fix: Main.gd wires `player.jump()` to the JUMP
  button's `button_down` *signal*, which Godot fires exactly once per
  physical touch-down with no auto-repeat - no human tap sequence can
  replicate a 60Hz unconditional call. Re-ran the identical policy at ~10
  taps/sec (already faster than anyone can realistically mash a touchscreen
  button, and still faster than `jump_buffer_time`) and it finished clean,
  no reversal, no runaway. And even the impossible 60Hz case never produced
  an unrecoverable state - it fell off the world exactly like the earlier
  reverse-lean bug used to, and the existing fall-recovery safety net caught
  it and reset the run same as always. Left as-is; recorded here so it
  isn't independently "discovered" and chased again later.
- **Level 2** (`Terrain._level_2_keyframes()`/`_level_2_zones()`): roughly
  2x level 1's length (course_end_x ~19300 vs ~9400), built around one long
  signature "flow" gauntlet - six gentle rolling hills in a row (peak slope
  ~28deg, deliberately gentler than anything else in either level) with no
  flat valley floor anywhere in the middle to break grounded contact.
  Bracketed by two bhop-style bump corridors (the second bigger/harder than
  the first: ~47deg peak vs ~44deg, six cycles vs four), plus one ice patch,
  one mud patch, one launch pad, and two boost pads (one right before the
  flow gauntlet, one right before the finish). The flow gauntlet exists
  specifically because Player.gd's Flow meter only builds from *sustained,
  uninterrupted* grounded alignment - level 1's shorter, choppier hills and
  its bhop corridor's repeated jump-then-reset-Flow-on-landing cycle never
  gave a skilled rider enough uninterrupted room to actually max Flow out
  and feel it hold there. Verified headlessly: a tangent-tracking rider
  holds Flow >= 0.9 for 73.6% of the time spent in the gauntlet, peaking at
  1.0. Both boost pads and the launch pad were placed following the
  boost-placement lesson above (flat ground, no descent immediately after)
  and verified the same way - no airborne-after-boost, no landing-quality
  scrubbing, clean launch-pad landing. Full 4-policy benchmark all finish
  with no DNFs (perfect ~33s / decent ~39s / poor ~196s / randomish ~100s -
  roughly double level 1's times, tracking the roughly-2x length, with
  "poor" scaling somewhat worse than 2x - a reasonable "harder" signal
  since it's still nowhere near the benchmark's very generous timeout).
  Reused level 1's exact validated slope ratios throughout (peak angle =
  ~1.5x the average rise/run, from smoothstep's derivative shape - see the
  bhop-tuning note above) rather than inventing new ones, specifically to
  avoid re-discovering the same slope-safety/floor_snap_length lessons from
  scratch.
- Discovered while investigating what looked like a level-1 regression
  during the Terrain.gd zone-system refactor that made two levels possible
  (see Architecture): the regression was fake, caused by a broken headless
  test methodology, not the refactor. See "Validating changes headlessly"
  above for the full writeup of the bug (manually calling
  `_physics_process()` races against the engine's own automatic ticking)
  and the fix (`await get_tree().physics_frame` + `--fixed-fps 60`). Worth
  remembering: any precise timing number reported in this file from before
  that fix landed was measured with the broken methodology and may carry
  more run-to-run noise than the categorical finding (soft-lock found/
  fixed, bad placement caught, etc.) it was attached to - the categorical
  findings themselves don't wash out as noise the way exact timings can,
  so they remain trustworthy even where the specific numbers might not be.
- Every constant governing the above is an `@export` specifically so it can
  be retuned from playtesting feedback without touching the logic.

### Gaps, Death, and Checkpoints

The user's explicit ask: "if you lad [land] bad and let there be gaps you
have to jump as well, if you dont make it you die and restart at a
checkpoint." Three changes together:

- **Harsher landing punishment**: `landing_penalty_worst` dropped from 0.75
  to 0.4 - a completely mismatched landing now scrubs 60% of speed instead
  of 25%. Verified headlessly that this doesn't reopen a soft-lock the way
  the `min_ceiling_with_any_lean` fix had to guard against: a worst-case
  repeated-bad-landing bhop-section stress test hit `current_speed == 0.0`
  at one point but still recovered and finished the section, since nothing
  about the ceiling/accel system itself changed - only the one-shot landing
  multiplier got harsher.
- **Real terrain gaps** (`Terrain.gaps`, `{start, end}` entries, one per
  level): a genuine absence of ground, not a cosmetic zone like ice/mud.
  `height_at()`/`tangent_at()` stay pure curve math across a gap's x-range
  (needed for continuity elsewhere - camera lookahead, checkpoint fallback
  positions), but `Terrain._build_ground()` splits collision into one
  `CollisionPolygon2D` per contiguous stretch BETWEEN gaps, skipping any
  segment inside one, and `TerrainRenderer._rebuild()` does the same for the
  visual fill and the rim highlight (now built as one `Line2D` per solid
  stretch instead of one continuous line for the whole course) - so a gap
  shows real empty space (the Background visible through it), not a
  painted-over hole. `Terrain.is_gap_at(x)` is the query Main.gd uses to
  tell "fell into a gap" apart from nothing.
  - Level 1's gap sits on crest 2's flat top (5980-6280, otherwise unclaimed
    by any zone). Level 2's sits on the flat run between bhop corridor 2 and
    boost pad #2 (18000-18300), deliberately NOT inside the flow gauntlet
    (which needs uninterrupted grounded contact for its own reasons - see
    the flow-zone note above). Both are 300px wide - a first attempt at
    200px turned out trivial: verified via headless bot that even a
    meaningfully slower approach (mismanaged mud-zone speed) still cleared
    it with 100+px to spare, because `jump_impulse`'s fixed ~0.65s flight
    time combined with `air_control_accel`'s constant forward push during
    that flight dominates over modest pre-jump speed differences - so
    pre-jump speed barely matters here, which is fine: the real skill check
    this design ends up testing is "did you actually press jump," a robust,
    binary thing to require on a touchscreen, not a finicky exact-speed
    window that would feel unfair on mobile.
  - **Real finding, not obvious in advance**: the jump has to be thrown from
    solid, already-flat ground, not while still climbing toward the crest.
    A sweep of jump positions at the 300px width found x>=5850 (near/on the
    flat top) reliably clears the gap, while x<=5800 (still on the climbing
    slope) reliably falls short and falls in - jumping off an upward-angled
    floor normal doesn't carry the same effective distance as jumping off a
    flat one, even with the same forward speed. This makes the real,
    learnable skill "wait until you're over flat ground, then jump," not
    "jump the instant you see the gap" - narrower than it first looks, but
    still a comfortably human ~100-130px/150-200ms window, not frame-perfect.
    Any bot/test approaching either gap needs to jump from at or after the
    flat run begins, not from an arbitrary lookahead distance - an earlier
    version of the benchmark bot below jumped up to 260px early (still
    mid-climb) and died in a loop over and over despite "correctly" pressing
    jump every single approach.
- **Checkpoints and death** (`Terrain.checkpoints`, an `Array[float]` of
  x-positions per level; tracking and the actual death/respawn logic live in
  Main.gd): checkpoints move the respawn point forward, one-way, as the
  player's x passes each one - `Main._check_checkpoints()` only runs while a
  run is actually in progress (`_timer_running and not _finished`), so
  coasting through the finish runway or idling before the timer starts can't
  claim one. Placed with real thought about WHERE, not just "near each
  hazard": a checkpoint right at the mouth of a gap (e.g. 50px before it)
  turned out to be a real bug, not just tight - a respawned player starts a
  few px above the surface with a teleported position, and if that spot
  happens to sit right at one of this course's already-documented
  "cresting" curve transitions (see the `floor_snap_length` history above),
  the ball can fail to re-establish `is_on_floor()` for many frames, meaning
  a death right at the gap could make the VERY NEXT life un-jumpable before
  even reaching the edge. Level 2's last checkpoint moved from 17950 (right
  at a keyframe transition) to 17750 (cleanly mid-slope, verified to
  re-ground within 0 frames of a reset) for exactly this reason. Level 1's
  checkpoints didn't need moving (all three re-ground within 0-3 frames as
  originally placed).
  - Falling into a gap, or off the world edge (the existing reverse-lean
    safety net) now triggers `Main._on_death()`: respawn at
    `_last_checkpoint_position` (spawn if none claimed yet) and a brief red
    "DIED - RESPAWNED" banner - but deliberately does NOT reset `_elapsed`,
    `_timer_running`, or best-time state, unlike the explicit Restart
    button. The lost time is the punishment; death doesn't wipe it away.
    The Restart button (`_on_restart_pressed()`) still does a full reset,
    including checkpoint progress back to spawn and `_next_checkpoint_index`
    back to 0 - it's a deliberate "start the whole level over," not a
    lighter option than death.
  - **Real engine bug found and fixed along the way**: `Player.reset()` did
    a raw `global_position` teleport with no floor re-check, which left
    Godot's own `is_on_floor()` cache stale (reflecting wherever the body
    was collision-wise BEFORE the teleport) until the next real
    `move_and_slide()` call happened to run. This could let a spurious
    landing-redirect fire against freshly-reset velocity, and separately
    could make `jump()`'s own grounded check unreliable for the first frame
    after a respawn. Fixed by calling `apply_floor_snap()` right after the
    position assignment in `reset()` - Godot's own built-in tool for "I just
    moved this body, is it on a floor now," which forces an accurate
    re-check at the new position instead of trusting stale cached state.
    Caught via a headless bot that fell into a genuine death-loop at a
    checkpoint (100+ deaths, never progressing) despite what looked like a
    correctly-timed automatic jump.
  - A benchmark bot needs to be gap-aware or it isn't testing anything
    representative: the standard 4-policy harness now checks
    `terrain.gaps` and fires `player.jump()` once per approach when a gap's
    start is within a tested-safe lookahead of the player's current x (see
    the jump-position finding above for why that lookahead has to be
    narrow, not just "somewhere before the gap"), and detects a
    death-triggered respawn (a sudden backward x jump) so it's willing to
    jump again on the retry. With that in place, all three policies
    (perfect/decent/poor) clear both gaps with zero deaths and finish at
    times close to the pre-gap baseline on both levels.

### Spam-jumping should never be your fastest strategy

The user's explicit complaint: they didn't want to be able to just mash the
JUMP button and have that be their best time, full stop - not "gaps should
be more punishing" (the previous section), a completely separate concern
about whether SKILL (aimed lean) beats MASHING overall. Measured first,
fixed second, same as everywhere else in this file: a headless bot that
does nothing but hold forward lean and press `jump()` every single grounded
frame (zero aiming skill at all) finished level 1 in 13.2s, a full 22%
**faster** than a bot perfectly tangent-tracking the whole course with no
manual jumping at all (16.9s). That's a real, serious problem for a game
whose entire premise is that aimed lean is the skill that matters. Root
Caused to two independent bugs, not one:

- **Air control had no speed ceiling at all.** The ground-acceleration
  block a few lines above it (toward `max_speed_this_frame`) already runs
  regardless of `on_floor` - it uses `tangent`, which just defaults to
  `Vector2.RIGHT` when airborne, so ceiling-capped forward acceleration was
  always happening in the air too. Air control was a SECOND, completely
  separate addition to velocity on top of that, gated only by
  `air_alignment` with no cap whatsoever - `velocity += vel_dir *
  air_alignment * air_control_accel * delta`, every single airborne frame,
  for the ball's entire ~0.65s flight time. Repeated jumping means repeated
  ~0.65s windows of this free, uncapped acceleration, compounding well past
  whatever ceiling actual ground technique would ever earn. Fixed by
  computing the exact same ceiling formula for air control (using
  `air_alignment` in place of `directional_magnitude`, since there's no
  ground tangent to measure lean against mid-air) and capping the
  acceleration step to the remaining headroom under it, identical in shape
  to the ground block. `combined_multiplier` (Flow/Chain/slope) is now
  computed once and shared by both blocks instead of being local to the
  ground block, since both need it.
- **Mud's friction scale didn't just add "more friction," it scaled
  catastrophically with speed.** The per-frame loss is a PERCENTAGE of
  current speed (`ground_speed_now * (effective_friction_decay - 1.0)`),
  while the acceleration fighting it is a roughly fixed absolute rate
  (`accel_force * delta`, a few dozen px/s per frame regardless of current
  speed). At the realistic 800-1000+ px/s this course routinely produces
  after this session's various speed-boosting additions (gravity assist,
  Flow, Chain), the old `mud_friction_scale` of 6.5 crushed even a
  perfect, full-lean rider from ~1000 px/s to ~120 px/s in well under a
  second crossing the mud zone - nowhere near the design intent documented
  above ("a consistently-leaning rider barely notices it since they're
  already accel-bound near their ceiling"). That catastrophic, unsurvivable
  drop is exactly what made simply staying airborne over the mud patch (via
  jumping) so much better than actually riding through it as designed.
  Lowered to 2.0: verified a full-lean rider now settles in the mid-400s
  px/s crossing it - a real, clearly-felt slowdown, not a near-total wipe.
- Together these two fixes cut the level-1 spam-jump advantage from 22%
  down to about 8% (14.9s perfect vs 13.75s spam-jump), and on level 2 a
  bot that does nothing but hold forward and mash jump doesn't even finish
  the course (gets stuck well past the flow gauntlet) - so on the level
  actually built to reward sustained aimed-lean Flow, mashing jump is
  outright worse, not better.
- **The remaining ~8% on level 1 is real and localized to the bhop
  section specifically**, not spread across the course - verified by
  isolating just that section (6900-8700) with a fixed start
  velocity/position: riding the bumps as designed (either tangent-tracking
  or a fixed lean, matching the existing "test bhop with momentum-coast,
  not tangent-hugging" guidance above) takes ~3.5-3.8s, mashing jump
  through the same stretch takes ~3.0s. This looks like the ball's arc
  skipping over 2-3 bumps at once and landing on a later bump that happens
  to be favorably oriented, since the bump pattern is periodic - closer to
  a real bunny-hop technique (which this project is explicitly inspired by)
  than an obviously-broken exploit. Tried the one other lever that looked
  promising - raising `jump_cooldown` to space out how often mashing can
  re-fire relative to the bumps' own rhythm - and rejected it: the effect
  was NOT monotonic (0.15 favored spam, 0.22-0.25 favored it even MORE by
  accidentally resonating better with the bump spacing, 0.35 overcorrected
  to favor riding instead), meaning any specific value would be fragile
  and terrain-spacing-dependent rather than a real fix. Left at the
  original 0.15. If this residual margin needs closing too, it likely
  needs a real distinction between a jump-induced launch and a
  terrain-induced one in the landing/launch-quality system, not another
  constant tweak - flagged here rather than guessed at.

### Grapple

The user's explicit ask: "add a grapple effect." A genuinely new movement
tool (`Player.try_grapple()`/`release_grapple()`), not a reskin of lean or
jump - see "Grapple Points" under Architecture above for where the anchor
points live and how the level designs were adjusted to actually use it.

- **A real rope-swing constraint, not a fixed-speed pull-to-point.**
  Pressing the GRAPPLE button (`%GrappleButton`, bottom-right, left of JUMP)
  attaches a rope to the nearest point in `terrain.grapple_points` within
  `grapple_max_range` (600px) of the ball - the rope's length is fixed at
  whatever the actual distance was at that instant, exactly like a real
  grapple/ninja-rope. Every physics frame after that, if the ball is at or
  past that length AND still moving further away, the OUTWARD radial
  velocity component (the part of velocity pointing away from the anchor)
  gets zeroed - the ball can still move closer (slack, unconstrained) or
  swing tangentially (also unconstrained), it just can never move further
  from the anchor than the rope allows. Combined with gravity (already
  applied unconditionally every frame), this is the standard "circle
  constraint" trick games use for pendulum swings: zeroing the radial
  velocity component every frame produces a real swinging arc without ever
  solving the pendulum equation directly. A small direct position
  correction on top (snapping back onto the rope's radius whenever a
  frame's velocity integration overshoots it) keeps the rope visually taut
  instead of slowly stretching - verified headlessly that max observed
  distance during a multi-second swing stayed within ~1.5% of the nominal
  rope length on every level, not growing over time.
- **Deliberately no reel-in in this first pass.** A pure swing (no "hold to
  pull closer") is simpler to reason about, already gives real traversal
  value (an alternative to jumping across a gap, or a shortcut over a
  valley), and avoids adding a second tunable "how fast does reeling feel
  right" system on top of an already-large tuning surface. Flagged here
  rather than guessed at - reel-in could be a real follow-up ability
  upgrade if asked for.
- **The ground-acceleration block is suppressed while grappling, air control
  isn't.** The ground-accel block doesn't check `on_floor` at all (see the
  air-control comment further down for why - it's deliberate, and already
  established behavior for ordinary jumps too), so left unguarded during a
  swing it would keep shoving velocity toward a horizontal ceiling on top of
  the rope constraint, fighting the swing instead of feeling like one.
  Air control (the same system that already lets a player steer during an
  ordinary jump) stays active during a swing, so leaning still gives real
  aiming agency mid-swing without a second, competing forward-thrust system
  layered on top of the pendulum physics.
- **Auto-release needed a real fix, not just an obvious guard.** The first
  version released the instant `is_on_floor()` was true, meant to detach
  cleanly on landing - but a headless test caught it releasing after a
  single physics frame every time, because the check didn't distinguish
  "just landed after swinging" from "was already standing on the ground the
  moment you pressed the button" (the latter is allowed on purpose - a
  player should be able to tether up a cliff face from a standing start).
  Fixed with `_grapple_left_ground`, a flag only set once the player has
  actually been airborne at least one frame since engaging - auto-release
  on landing now only fires after that, closing the false-positive without
  blocking the from-the-ground use case. A `grapple_max_duration` (4.0s)
  safety timeout still applies regardless, for the same reason
  `FALL_RECOVERY_MARGIN` exists elsewhere - a missed release input (or a
  genuinely stable-feeling orbit) shouldn't be able to strand a run forever.
- **Verified headlessly on all three levels**: engaging at realistic
  approach speed/position produces a stable multi-second swing with no NaN
  and no runaway distance growth, releasing (button-up) mid-swing correctly
  detaches with whatever velocity the swing built up, pressing the button
  with nothing in range is a clean no-op, and - most importantly - a
  no-grapple 4-policy-style regression run (the same tangent-tracking
  "perfect" bot used for every level's medal benchmark, which never calls
  `try_grapple()`) finishes in EXACTLY the same time as before this feature
  existed on every level (level 3: 39.20s both before and after, to the
  millisecond) - confirming the new constraint code, which only ever runs
  inside `if _grappling:`, can't have silently perturbed ordinary play.
- **Visual**: a bright cyan `Line2D` rope (`Player._make_grapple_line()`,
  `top_level = true` so it stays in world space like TrailEffect) drawn from
  the ball's actual visual center - `position - (0, ball_radius)`, the same
  ground-contact-vs-visual-center distinction Ghost.gd's own height fix
  documents above - to the anchor point, visible only while attached.

## Working style expected on this project

- The user plays on a phone only, via the Godot Android editor. There is no
  desktop testing loop on their end — your headless validation here is the
  only safety net before they ever see a change.
- When asked to improve/tune physics, prefer adjusting exported constants
  and well-justified formula changes over adding new systems. Validate with
  a headless smoke test that actually measures the numbers, don't just
  "should work" it.
- Player.gd/Joystick.gd are shared by both levels now - a physics tuning
  change affects both, so re-run the full-course benchmark on *both*
  `Main.tscn` and `Level2.tscn` (swap `run/main_scene` in `project.godot`
  temporarily to point at whichever scene you're validating) before calling
  a physics change done, not just the level you happened to be thinking
  about.
- Don't add UI, menus, persistence, or scope beyond what's asked. A stray
  extra system is a bigger cost here than it looks — this is deliberately a
  minimal feel-test, not a growing game, unless the user says otherwise.
- Commit messages should explain *why* a physics formula changed, including
  any wrong-first-attempt and how testing caught it — that history matters
  more here than in typical app code, since the "correctness" is entirely
  about subjective feel plus the few things that are objectively checkable
  (numbers moving in the right direction, no NaNs, no gaps in terrain).
