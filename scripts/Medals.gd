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
## Level 4 ("Grapple Gauntlet" - see CLAUDE.md) is a different KIND of level
## entirely: no ground to lean-track at all, just a chain of grapple swings.
## Skill here is release-TIMING precision, not lean tracking, so the 4
## policies became "how close to the validated safe release window (25-35%
## of rope length past the bottom of the swing)": perfect hits it exactly
## every time, decent/randomish add growing timing jitter, poor is centered
## on a genuinely too-early release (the realistic novice mistake this
## level actually punishes) plus jitter. poor DNFs (23 deaths, still
## retrying at the frame budget) - a believable bronze-miss baseline, same
## as levels 1/2. perfect/decent/randomish all finish within a tight band
## (53.9-56.5s) since release timing affects cycle count more than raw
## speed on this level. Bronze = randomish's time (3rd-place-of-benchmarks),
## same rule as every other level. Measured: perfect 54.3s, decent 53.9s,
## randomish 56.5s (1 death), poor DNF.
const GOLD: Dictionary = {1: 16.5, 2: 31.5, 3: 40.0, 4: 55.0}
const SILVER: Dictionary = {1: 18.5, 2: 35.5, 3: 57.5, 4: 58.0}
const BRONZE: Dictionary = {1: 25.5, 2: 50.0, 3: 68.0, 4: 60.0}


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
