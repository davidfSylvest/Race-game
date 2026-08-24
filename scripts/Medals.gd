extends Node

## Trackmania-style medal thresholds per level, and the unlock rule built on
## top of them - the user explicitly asked for "unlock by beating the bronze
## time, the 3rd place of benchmarks," same idea as Trackmania's
## author/gold/silver/bronze ladder. An autoload (like SaveManager), not a
## class_name Resource - this project reserves class_name for the narrow
## Resource-subtype/exported-enum cases documented in CLAUDE.md
## (TimeOfDayPalette/PaletteController); a plain lookup singleton doesn't need
## it, and staying consistent with SaveManager's own autoload pattern avoids
## spreading that exception further.
##
## Every threshold here was MEASURED, not guessed: a throwaway 4-policy
## headless bot (perfect tangent-tracking / decent-but-imperfect / noisy
## "randomish" / weak "poor") raced every level start to finish.
## "poor" DNFs (dies repeatedly at the terrain gap) on levels 1/2 - a
## deliberate, believable bronze-miss baseline, consistent with the rest of
## this project's "measure, don't guess" culture (see CLAUDE.md). Bronze is
## set at the 3rd-place *finishing* policy's time, per the user's explicit
## "3rd place of benchmarks" framing, with a small rounding buffer so a human
## replicating that policy's rough skill level can actually clear it, not
## just an idealized bot landing on the exact frame.
##
## Level 3 measured differently, worth recording: all four policies finish
## (no DNF), because level 3's two gaps sit inside deliberately long, fully
## flat runs (500-900px of flat ground before each) - see Terrain.gd's
## _level_3_gaps() comment - so even "poor"'s weak/off-angle technique still
## clears them once combined with the same "commit to a clean aimed approach
## in the final 500px before a gap" concession every policy gets (matches
## the established design rationale: a real player lines up a landmark gap
## deliberately even if sloppy everywhere else). "poor" is still a believable
## bronze-miss baseline here, just via being dramatically slower overall
## (276.2s vs 39.2s perfect) from its weak technique on the rest of the
## course, rather than a literal DNF at the gap - the 3rd-place-of-benchmarks
## rule still applies identically: bronze = randomish's time (the 3rd
## finisher), same as levels 1/2. Measured: perfect 39.2s, decent 56.1s,
## randomish 66.3s, poor 276.2s (all four finished, zero deaths).
##
## Level 4 ("Grapple Gauntlet," REBUILT - see CLAUDE.md for why: the user
## rejected the original 9-identical-section version as repetitive and
## asked for real variety) is a different KIND of level entirely: no ground
## to lean-track at all through its four voids, just grapple-swing release
## timing - skill here is release-TIMING precision, not lean tracking.
## Re-measured from scratch after the rebuild, since the course layout,
## void count/shapes, and overall length all changed. A fixed-hold-duration
## bot (release N frames after each grab - more robust than a velocity/
## position-threshold rule, which proved fragile against this level's
## differently-shaped swings - see CLAUDE.md) swept several timing values:
## every "reasonable" timing (roughly 15-22 frames per hop, 32-48 frames on
## the void 3 big swing) finished cleanly within a tight 41.4-42.65s band -
## release timing on THIS rebuilt layout mostly affects which grapple point
## in a void's chain you end up needing, not overall pace, so the finishing
## band is naturally narrow. Timings further from that window (too early,
## too late, or inconsistent) reliably DNF (repeated deaths, never
## completing) - a believable bronze-miss baseline, same pattern as every
## other level. Gold/silver sit at/above the observed finishing band with a
## small buffer; bronze sits with a generous buffer above the whole band,
## since a human won't reproduce bot-precise timing on every one of the
## course's 10 grapple points. Measured finishing times: 41.383s, 41.900s,
## 42.167s, 42.650s (zero deaths on all four); DNF policies all died
## repeatedly at one of the four crossings without finishing.
const GOLD: Dictionary = {1: 16.5, 2: 31.5, 3: 40.0, 4: 42.0}
const SILVER: Dictionary = {1: 18.5, 2: 35.5, 3: 57.5, 4: 44.5}
const BRONZE: Dictionary = {1: 25.5, 2: 50.0, 3: 68.0, 4: 48.0}


func gold_time(level: int) -> float:
	return GOLD.get(level, INF)


func silver_time(level: int) -> float:
	return SILVER.get(level, INF)


func bronze_time(level: int) -> float:
	return BRONZE.get(level, INF)


## "" (no medal) / "BRONZE" / "SILVER" / "GOLD" for the given finish time on
## the given level. A negative time (no run yet) always returns "".
func medal_for(level: int, time: float) -> String:
	if time < 0.0:
		return ""
	if time <= gold_time(level):
		return "GOLD"
	if time <= silver_time(level):
		return "SILVER"
	if time <= bronze_time(level):
		return "BRONZE"
	return ""
