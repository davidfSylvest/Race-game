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
## "randomish" / weak "poor") raced both existing levels start to finish.
## "poor" DNFs (dies repeatedly at the terrain gap) on both levels - a
## deliberate, believable bronze-miss baseline, consistent with the rest of
## this project's "measure, don't guess" culture (see CLAUDE.md). Bronze is
## set at the 3rd-place *finishing* policy's time (perfect/decent/randomish
## all finish; poor doesn't), per the user's explicit "3rd place of
## benchmarks" framing, with a small rounding buffer so a human replicating
## that policy's rough skill level can actually clear it, not just an
## idealized bot landing on the exact frame.
const GOLD: Dictionary = {1: 16.5, 2: 31.5}
const SILVER: Dictionary = {1: 18.5, 2: 35.5}
const BRONZE: Dictionary = {1: 25.5, 2: 50.0}


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
