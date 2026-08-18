class_name DirectorConfig
extends Resource

## Every tunable in the director module, in one Resource (director.md, "Configuration").
##
## THIS IS THE WHOLE PACING DIAL, in the same way PerceptionConfig is the whole difficulty
## dial and BehaviorConfig the whole temperament dial. How long dead air is allowed to last,
## how much pressure an encounter must deliver before its ending is earned, how long the game
## leaves you alone afterwards -- all of it is here and none of it is anywhere else.
##
## DIFFICULTY IS NOT HERE. Hearing range, vision cone and sense weights live on
## PerceptionConfig, and director.md is emphatic about the split: if the Director could
## deafen the alien to relieve pressure, noise discipline would stop being a real mechanic.
## Difficulty lives there. Pacing lives here.
##
## EVERY DEFAULT IS DERIVED, AND director.md SUPPLIES NO NUMBERS. The spec names all of these
## fields and values none of them; its only calibration is the worked encounter, so that
## trace is what these were solved against:
##
## ```text
## t+0    lull .6 after two quiet minutes  ->  lull_full_s 200      (120/200 = .6)
## t+0    lull .6 -> roam +.6, bias +.3    ->  max_roam_bias 1.0, ratio 0.5
## t+31   hunt begins
## t+58   menace 1.00 -> PEAK              ->  27 s of typical chase fills the meter
## t+58   RELIEF: roam -.8, bias -.4       ->  relief_roam_bias -.8, the SAME 1:2 ratio
## t+71   separation met -> UNALERTED
## t+79   cooldown expires -> QUIET        ->  cooldown_s 20, from entering RELIEF
## ```
##
## THE RATES ARE THE PART WORTH CHECKING, because they are what the trace actually pins:
##
## ```text
## full pressure   close + seen + in reach   .008+.018+.010+.014 = .050/s  ->  20 s
## typical chase   close + seen              .008+.018+.010      = .036/s  ->  28 s
## lurk at a mouth close + unseen + lurking  .008+.018+.010      = .036/s  ->  28 s
## bare presence   hunting, nothing else     .008                = .008/s  ->  125 s
## ```
##
## The trace's hunt runs t+31 to t+58 -- 27 seconds. Bare presence takes longer than
## hunt_max_duration_s, which is the rule rather than the rounding: see w_time.
##
## A bare DirectorConfig.new() is fully usable, so a test and a freshly dropped
## EncounterDirector both run without a .tres.

## Menace is clamped to 1.0, so a peak_threshold above it is unreachable and every encounter
## in the game would end STALLED. Asserted in invariant_failures().
const MAXIMUM_PEAK_THRESHOLD: float = 1.0

@export_group("Menace")
## Per-second menace from the clock alone, with no contact of any kind.
##
## DELIBERATELY TOO SLOW TO EVER SATE, and that is a rule rather than a rounding. At 0.008 a
## hunt delivering nothing else needs 125 s to fill a meter it is only given
## hunt_max_duration_s (90 s) to fill -- so a stalemate CANNOT end SATED. It times out
## STALLED and the alien leaves quietly. Raise this past peak_threshold/hunt_max_duration_s
## and a player who hid successfully for a minute gets the same triumphant exhale as one who
## was chased down a corridor, which is the exact failure the SATED/STALLED split exists to
## prevent. Asserted.
@export_range(0.0, 0.2, 0.001, "suffix:/s") var w_time: float = 0.008
## Per-second menace at zero route distance, spent at menace_range_m.
##
## The largest sustained term, because dread is mostly "how close is it, along a path it can
## actually walk".
@export_range(0.0, 0.5, 0.001, "suffix:/s") var w_proximity: float = 0.018
## Per-second menace while the encounter report claims visual contact.
@export_range(0.0, 0.5, 0.001, "suffix:/s") var w_sight: float = 0.01
## Per-second menace while a strike would connect.
##
## Prices being INSIDE ITS REACH, not "it swung". EncounterReport.attack_window_open stays
## true across BehaviorConfig.attack_cooldown_s because HuntingState puts the rate limit in a
## BtCooldown decorator OUTSIDE the condition -- deliberately, so this weight prices a
## sustained window rather than a single frame. A per-strike impulse would double-count and
## would need a field director.md does not name.
@export_range(0.0, 0.5, 0.001, "suffix:/s") var w_attack: float = 0.014
## Per-second menace while the alien waits out a gap its own graph cannot follow you through.
##
## EQUAL TO w_sight ON PURPOSE: a lurk SUBSTITUTES for the sight term. You cannot see it; you
## know exactly where it is. Equal weights make waiting you out deliver the same pressure as
## chasing you, which is the claim behind behavior.md section 29 -- set it lower and hiding
## in a hole the alien cannot enter becomes a free reset.
@export_range(0.0, 0.5, 0.001, "suffix:/s") var w_lurk: float = 0.01
## Per-second menace SUBTRACTED while the target is unreachable outright.
##
## STRICTLY GREATER THAN w_time + w_proximity, so a genuinely unreachable target DRAINS
## menace rather than merely slowing its rise. Otherwise a stalemate slowly accrues a SATED
## exit and the game congratulates a player who did nothing. Asserted.
##
## Not the same as lurking. A PARTIAL route still stops at the mouth and still frightens
## somebody; an UNREACHABLE one means the alien is walking at rock somewhere else entirely.
@export_range(0.0, 0.5, 0.001, "suffix:/s") var w_stall: float = 0.03
## Route distance at which the proximity term is fully spent.
##
## PATH LENGTH, NEVER EUCLIDEAN -- director.md's own line is that an alien twelve metres away
## through forty metres of tunnel is not delivering twelve metres of dread. At 30 m a 12 m
## route reads 0.60, and the number sits between BehaviorConfig.retreat_separation_m (25) and
## nest_distance_span (60) so the three scales stay legible against each other.
@export_range(1.0, 200.0, 0.5, "suffix:m") var menace_range_m: float = 30.0
## Per-second menace decay whenever the creature is not hunting.
##
## 20 s to shed a full ceiling -- the same order as cooldown_s, so the "Behavior gave up on
## its own" exit and the "Director ordered a disengage" exit take about the same time to
## return to QUIET and read as one game.
@export_range(0.0, 2.0, 0.005, "suffix:/s") var menace_relief_rate: float = 0.05
## Menace at which the encounter has delivered its payoff and the exit is earned.
@export_range(0.1, 1.0, 0.01) var peak_threshold: float = 1.0
## Hard cap on one hunt. Exceeding it with menace still low is the STALLED exit.
##
## Must clear the time a SUCCESSFUL hunt takes -- 20 s at full pressure, 28 s typical -- or a
## good encounter gets cut off and then mislabelled as unearned. 90 s leaves 3x headroom and
## is long enough that a player who genuinely evaded feels the alien give up rather than
## simply time out. Asserted against the weights in both directions.
@export_range(5.0, 600.0, 1.0, "suffix:s") var hunt_max_duration_s: float = 90.0

@export_group("Escalation gate")
## How long RELIEF lasts at minimum, measured from the disengage.
##
## One half of the RELIEF -> QUIET rule, which director.md names and never defines. 20 s puts
## the worked encounter's t+58 disengage at t+78, one second off its stated t+79.
@export_range(0.0, 300.0, 0.5, "suffix:s") var cooldown_s: float = 20.0
## How far the creature must get from where it disengaged before RELIEF may end.
##
## The other half. Must sit AT OR BELOW BehaviorConfig.retreat_separation_m (25 m), or the
## Director's gate outlasts Behavior's retreat: the alien reaches UNALERTED while the
## Director is still refusing to permit a hunt, and nothing on screen says why. Asserted
## cross-config.
@export_range(0.0, 200.0, 0.5, "suffix:m") var cooldown_separation_m: float = 20.0
## escalation_bias as a fraction of roam_bias. The two always move together.
##
## DERIVED FROM BOTH TRACE LINES, which agree exactly. At t+0: roam +.6, bias +.3. At t+58:
## roam -.8, bias -.4. Both are 1:2, so willingness is always half the drift. That coupling
## is also the only one that reads correctly in play -- a Director that pulled the alien
## TOWARD the party while making it LESS willing to act would look broken rather than paced.
## Exposed so the magnitudes can be decoupled; the sign is forced to agree.
@export_range(0.0, 1.0, 0.05) var escalation_bias_ratio: float = 0.5
## roam_bias published throughout RELIEF. Strongly negative, so a retreat creates real space.
##
## Read straight off the trace. escalation_bias follows at escalation_bias_ratio, giving the
## -.4 the same line states.
@export_range(-1.0, 0.0, 0.05) var relief_roam_bias: float = -0.8

@export_group("Lull")
## Seconds of unbroken dead air that fill the lull meter.
##
## Long, and it should be. This is the throttle on a game about waiting, and a short one
## turns "the alien has not bothered me in a while" into "the alien arrives on a schedule",
## which is the one thing a player can learn to plan around. Derived: the trace's "lull .6
## after two quiet minutes" is 120/200.
@export_range(10.0, 900.0, 1.0, "suffix:s") var lull_full_s: float = 200.0
## Overall suspicion below which the scene counts as dead air at all.
##
## MUST CLEAR THE MOST-SHIFTED INVESTIGATE THRESHOLD, or the lull keeps rising after the
## creature has already committed to a lead and the Director adds pressure to a scene that is
## already building. The floor is BehaviorConfig.investigate_threshold (0.25) minus the
## largest shift this config can ask for -- max_roam_bias x escalation_bias_ratio x
## bias_span = 1.0 x 0.5 x 0.15 = 0.075 -- so 0.175. Asserted cross-config.
@export_range(0.0, 1.0, 0.01) var calm_suspicion_threshold: float = 0.15
## roam_bias at full lull. The published bias is `lull * this`.
##
## Derived: the trace's lull .6 producing roam +.6 puts the multiplier at 1.0.
@export_range(0.0, 1.0, 0.05) var max_roam_bias: float = 1.0
## The lull an encounter is re-seeded at when it ended STALLED. A SATED exit re-seeds at zero.
##
## The player got the whole beat from a SATED exit and has earned the quiet. A stalemate
## earned nothing, and giving it the same reset would reward hiding with silence. At 0.4 the
## Director rebuilds after about 80 s of dead air instead of 200, while still leaving a real
## exhale. At 1.0 the alien turns straight back around. Asserted below 1.0.
@export_range(0.0, 1.0, 0.05) var stalled_lull_retention: float = 0.4

@export_group("Target arbitration")
## How far a rival candidate must exceed the held target before the encounter switches.
##
## director.md's two worked lines bracket it: .72 against .76 is a margin of .04 and holds,
## .55 against .94 is a margin of .39 and switches. 0.25 sits between them and nearer the
## switch, so a decisive rival wins and an oscillating one never does.
@export_range(0.0, 1.0, 0.01) var retarget_margin: float = 0.25
## How long a target must have been held before any rival may take it, at any margin.
##
## Matched to BehaviorConfig.hunt_sustain_grace_s (8 s). The creature will chase a lost
## estimate for that long before its own sustain is even at risk, so a Director that could
## swap sooner would swap while the creature was still committed to the old estimate -- and
## the swap would be invisible in play. Asserted cross-config.
@export_range(0.0, 60.0, 0.1, "suffix:s") var min_target_commit_s: float = 8.0

@export_group("Lethality")
## Menace below which an attack resolves as a near-miss: the encounter has not earned it.
##
## About ten seconds into a typical hunt. An alien that rounds a corner and instantly kills
## is not an encounter, it is a trap. Must stay below peak_threshold or no strike could ever
## be lethal -- the encounter would sate and disengage first. Asserted.
@export_range(0.0, 1.0, 0.01) var lethal_menace_threshold: float = 0.35
## How long after a respawn the player keeps grace.
##
## Long enough to walk out of a spawn room, short enough that it cannot be farmed by dying on
## purpose. Being killed by the thing that just killed you, in the same place, before you
## have your bearings, reads as the game malfunctioning rather than as a predator.
@export_range(0.0, 300.0, 0.5, "suffix:s") var respawn_grace_s: float = 20.0
## Whether the first encounter of the session may kill at all.
##
## "The first one teaches, it does not kill." Exposed rather than hardcoded because a level
## that is nothing BUT the alien has already taught it.
@export var first_encounter_grace: bool = true


## Menace per second from one encounter report. Pure, so director.md's formula is checkable
## against two structs with no creature, no scene and no baked graph attached.
##
## Menace only INTEGRATES while hunting; every other state decays it. That is what makes a
## one-tick flicker out of HUNTING cost 0.0008 rather than a whole encounter.
func menace_rate(report: EncounterReport, hunting: bool) -> float:
	if not hunting:
		return -menace_relief_rate
	var rate: float = w_time + w_proximity * proximity_pressure(report.route_distance)
	if report.has_visual_contact:
		rate += w_sight
	if report.attack_window_open:
		rate += w_attack
	if report.lurking_at_tunnel_mouth:
		rate += w_lurk
	if not report.target_reachable:
		rate -= w_stall
	return rate


## 1.0 at arm's length, 0.0 at menace_range_m or with no route at all.
##
## NO ROUTE MEANS NO PRESSURE, and it has to be spelled or the term reads backwards.
## EncounterReport.NO_ROUTE_DISTANCE is INF for exactly this division; the raw 0.0 that
## RouteFollower returns without a route would arrive here as maximum dread from an alien
## idling at a nest, forever, with nothing in the log.
func proximity_pressure(route_distance: float) -> float:
	if not is_finite(route_distance):
		return 0.0
	return 1.0 - clampf(route_distance / maxf(menace_range_m, 0.001), 0.0, 1.0)


## The (escalation_bias, roam_bias) pair a given lull earns, locked at escalation_bias_ratio.
func lull_outputs(lull: float) -> Vector2:
	var roam: float = clampf(lull, 0.0, 1.0) * max_roam_bias
	return Vector2(roam * escalation_bias_ratio, roam)


## The same pair during RELIEF, where the sign is inverted and the ratio still holds.
func relief_outputs() -> Vector2:
	return Vector2(relief_roam_bias * escalation_bias_ratio, relief_roam_bias)


## Cross-field rules no single @export_range can express, mirroring
## BehaviorConfig.invariant_failures() and SuspicionConfig.invariant_failures().
##
## `behavior` is optional because three of these rules are about how this config sits against
## THAT one, and a DirectorConfig on its own genuinely cannot know. Every one of the three is
## silent: the encounter runs, and is quietly wrong about something nobody is measuring.
func invariant_failures(behavior: BehaviorConfig = null) -> PackedStringArray:
	var failures := PackedStringArray()
	failures.append_array(_menace_failures())
	failures.append_array(_pacing_failures())
	failures.append_array(_behavior_failures(behavior))
	return failures


## Whether menace can fill at all, and which exit it produces when it does.
func _menace_failures() -> PackedStringArray:
	var failures := PackedStringArray()
	if peak_threshold > MAXIMUM_PEAK_THRESHOLD:
		(
			failures
			. append(
				(
					"peak_threshold %.2f is above %.2f, and menace is clamped there: PEAK would be unreachable and every encounter in the game would end STALLED"
					% [peak_threshold, MAXIMUM_PEAK_THRESHOLD]
				)
			)
		)
	if w_stall <= w_time + w_proximity:
		(
			failures
			. append(
				(
					"w_stall %.3f does not exceed w_time + w_proximity %.3f: an unreachable target still accrues menace, so a stalemate ends SATED and the game congratulates a player who did nothing"
					% [w_stall, w_time + w_proximity]
				)
			)
		)
	if w_time * hunt_max_duration_s >= peak_threshold:
		(
			failures
			. append(
				(
					"w_time %.3f fills peak_threshold %.2f within hunt_max_duration_s %.1f on the clock alone: an alien merely standing in a corridor would earn the exit"
					% [w_time, peak_threshold, hunt_max_duration_s]
				)
			)
		)
	var rise: float = w_time + w_proximity + w_sight + w_attack + w_lurk
	if rise * hunt_max_duration_s < peak_threshold:
		(
			failures
			. append(
				(
					"even full pressure %.3f/s cannot reach peak_threshold %.2f inside hunt_max_duration_s %.1f: every encounter in the game would end STALLED"
					% [rise, peak_threshold, hunt_max_duration_s]
				)
			)
		)
	if menace_relief_rate <= 0.0:
		(
			failures
			. append(
				"menace_relief_rate is zero: menace never sheds, so the second hunt of a level starts at the ceiling and sates instantly"
			)
		)
	return failures


## Whether the cycle turns over.
func _pacing_failures() -> PackedStringArray:
	var failures := PackedStringArray()
	if cooldown_s <= 0.0:
		(
			failures
			. append(
				"cooldown_s is zero: RELIEF would end on the tick it began, permit_hunt would withhold nothing, and a forced disengage would be followed immediately by permission to hunt again"
			)
		)
	if relief_roam_bias > 0.0:
		(
			failures
			. append(
				(
					"relief_roam_bias %.2f is positive: the exhale would drift the alien TOWARD the party, and a retreat that creates no space is not a retreat"
					% relief_roam_bias
				)
			)
		)
	if stalled_lull_retention >= 1.0:
		(
			failures
			. append(
				(
					"stalled_lull_retention %.2f re-arms a full lull after a stalemate: the alien turns straight back around and the unearned exit costs the player nothing"
					% stalled_lull_retention
				)
			)
		)
	if retarget_margin <= 0.0 or min_target_commit_s <= 0.0:
		(
			failures
			. append(
				(
					"retarget_margin %.2f / min_target_commit_s %.1f let the held target lose to any rival at all: arbitration oscillates, which is the whole thing stickiness exists to prevent"
					% [retarget_margin, min_target_commit_s]
				)
			)
		)
	if lethal_menace_threshold >= peak_threshold:
		(
			failures
			. append(
				(
					"lethal_menace_threshold %.2f is at or above peak_threshold %.2f: the encounter would sate and disengage before the threshold was crossed, so no strike could ever be lethal"
					% [lethal_menace_threshold, peak_threshold]
				)
			)
		)
	if calm_suspicion_threshold <= 0.0:
		(
			failures
			. append(
				"calm_suspicion_threshold is zero: dead air would only register with belief at exactly nothing, so the Director would never get bored"
			)
		)
	return failures


## The three rules that are about this config's fit with BehaviorConfig.
func _behavior_failures(behavior: BehaviorConfig) -> PackedStringArray:
	var failures := PackedStringArray()
	if behavior == null:
		return failures
	if cooldown_separation_m > behavior.retreat_separation_m:
		(
			failures
			. append(
				(
					"cooldown_separation_m %.1f is above BehaviorConfig.retreat_separation_m %.1f: the alien reaches UNALERTED while the Director is still refusing to permit a hunt, and nothing on screen says why"
					% [cooldown_separation_m, behavior.retreat_separation_m]
				)
			)
		)
	var shift: float = max_roam_bias * escalation_bias_ratio * behavior.bias_span
	if calm_suspicion_threshold >= behavior.investigate_threshold - shift:
		failures.append(
			(
				(
					"calm_suspicion_threshold %.2f is at or above the most-shifted investigate "
					+ "threshold %.2f: the lull keeps rising after the creature has committed to a "
					+ "lead, so the Director adds pressure to a scene that is already building"
				)
				% [calm_suspicion_threshold, behavior.investigate_threshold - shift]
			)
		)
	if min_target_commit_s < behavior.hunt_sustain_grace_s:
		failures.append(
			(
				(
					"min_target_commit_s %.1f is below BehaviorConfig.hunt_sustain_grace_s %.1f: "
					+ "the Director could swap targets while the creature was still committed to "
					+ "the old estimate, and the swap would be invisible in play"
				)
				% [min_target_commit_s, behavior.hunt_sustain_grace_s]
			)
		)
	return failures
