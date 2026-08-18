class_name SuspicionConfig
extends Resource

## Every tunable in the suspicion module, in one Resource (suspicion.md, "Parameters").
##
## THIS IS THE WHOLE MEMORY DIAL, in the same way PerceptionConfig is the whole
## difficulty dial. Making the alien more tenacious, more forgetful, more willing to
## re-check a room it already swept means editing numbers here and nothing else. That
## property only survives if nothing outside this file hardcodes a decay rate or a
## merge distance.
##
## A bare SuspicionConfig.new() is fully usable -- every field has a working default,
## so tests and a freshly dropped CreatureSuspicion both run without a .tres.
##
## Decay rates are per-second exponential. Half-life is the number worth thinking in:
##
##     half_life = ln(2) / decay_rate       decay_rate = 0.693 / half_life
##
## so 0.06 is about a twelve-second half-life, and the shipped defaults give hearing
## ~12 s, vision ~20 s and touch ~6 s. Touch starts strongest and goes stale fastest,
## which is exactly what suspicion.md asks for: being grabbed is enormous news about
## right now and says very little thirty seconds later.

## Sense count that earns a search full disconfirmation credit. Perception's activity
## scan reports VISION and TOUCH; hearing is event-driven and never deliberately
## checks a region, so two is the realistic maximum and a blind creature's sweep
## clears half as much.
const DEFAULT_SENSES_FOR_FULL_CREDIT: int = 2

@export_group("Evidence")
## Below this effective strength, a record is dropped. Not a timeout -- evidence stops
## mattering gradually and is deleted only once it no longer changes any answer.
##
## Deliberately far below anything that could form a hotspot on its own. A drill heard
## faintly through a wall arrives at about 0.02 after Perception has attenuated it for
## both distance and obstruction, and a single one of those should not make the creature
## come running -- but five of them in a row should. Set this at hotspot strength and
## faint evidence is thrown away instead of accumulating, so a player can drill through
## a wall indefinitely and never be noticed at all.
@export_range(0.0, 1.0, 0.001) var evidence_min_retention_strength: float = 0.005
## Used when an observation reports no uncertainty at all. Zero would claim perfect
## knowledge, which is the one thing the perception layer exists to avoid saying.
@export_range(0.1, 40.0, 0.1, "suffix:m") var default_uncertainty_radius: float = 3.0
## Hard cap on remembered records. A player drilling continuously produces evidence
## faster than it decays, and an uncapped array is a frame spike with no error in it.
## The weakest records are dropped first.
@export_range(4, 512, 1) var max_evidence_count: int = 64

@export_subgroup("Per-sense decay")
@export_range(0.0, 2.0, 0.001, "suffix:/s") var hearing_decay_rate: float = 0.06
@export_range(0.0, 2.0, 0.001, "suffix:/s") var vision_decay_rate: float = 0.035
@export_range(0.0, 2.0, 0.001, "suffix:/s") var touch_decay_rate: float = 0.12

@export_subgroup("Per-sense influence")
## A noise is worth slightly less than seeing something: it is the same amount of news
## about a much vaguer place.
@export_range(0.0, 4.0, 0.01) var hearing_weight: float = 0.85
@export_range(0.0, 4.0, 0.01) var vision_weight: float = 1.0
@export_range(0.0, 4.0, 0.01) var touch_weight: float = 1.0

@export_group("Hotspots")
## Evidence closer together than this joins one hotspot.
@export_range(0.5, 60.0, 0.5, "suffix:m") var hotspot_merge_distance: float = 6.0
## Raw support a cluster needs before it is a hotspot at all.
@export_range(0.0, 2.0, 0.01) var hotspot_min_strength: float = 0.05
## Cap on hotspot size. Without it a scatter of vague noises across a whole cave
## becomes one enormous hotspot whose centre is somewhere nobody has ever been.
@export_range(1.0, 80.0, 0.5, "suffix:m") var hotspot_max_radius: float = 14.0
## Fraction of the way a hotspot moves toward its recomputed centre each update. 1.0
## teleports; low values make a hotspot lag behind evidence that is genuinely moving.
@export_range(0.01, 1.0, 0.01) var hotspot_position_smoothing: float = 0.35
## Controls how quickly accumulated support saturates toward 1.0. Higher means a
## little evidence already reads as very suspicious.
##
## Calibrated against suspicion.md's own worked example -- "Evidence #1, strength .90"
## forming "Hotspot A, suspicion .84". At 3.0 a clear nearby drill lands almost exactly
## there. Halve it and the same drill reads .48, which is below most sensible
## investigate thresholds: the creature hears a player drilling twenty feet away and
## carries on with its day.
@export_range(0.05, 8.0, 0.05) var hotspot_saturation_rate: float = 3.0
## How often the hotspot set is rebuilt. Rebuilding every frame costs O(evidence^2)
## for no visible benefit; 0.0 is legal and is what the tests use.
@export_range(0.0, 2.0, 0.01, "suffix:s") var hotspot_update_interval: float = 0.2
## Points scored inside a hotspot when Behavior asks where to search next. This is the
## resolution of the spec's sample-cloud diagram, and the cost of asking.
@export_range(1, 128, 1) var hotspot_sample_count: int = 24
## Refuse to merge evidence that CreatureSuspicion.region_resolver puts in different
## spatial regions -- two sides of a thin cave wall, say. A no-op until something
## supplies a resolver, which is why it ships off.
@export var require_same_spatial_region_for_merge: bool = false

@export_group("Investigation")
## Global scale on how much a search is allowed to clear. Above 1.0 a thorough sweep
## can suppress a hotspot outright; below it, searching always leaves a residue.
@export_range(0.0, 4.0, 0.01) var disconfirmation_strength_multiplier: float = 1.0
## Searches weaker than this are discarded rather than stored. An aborted scan reports
## 0.0 and must never be remembered as evidence that somewhere was checked.
@export_range(0.0, 1.0, 0.01) var investigation_min_observation_strength: float = 0.02
## Hotspot suspicion below which the hotspot is resolved and dropped.
@export_range(0.0, 1.0, 0.01) var resolved_hotspot_threshold: float = 0.08
## How fast a searched area becomes interesting again. ~35 s half-life by default. At
## 0.0 a search rules an area out permanently, and a creature that can do that
## eventually rules out the whole level and stands still.
@export_range(0.0, 1.0, 0.001, "suffix:/s") var searched_area_recovery_rate: float = 0.02
## Senses that earn full disconfirmation credit. See DEFAULT_SENSES_FOR_FULL_CREDIT.
@export_range(1, 3, 1)
var disconfirmation_senses_for_full_credit: int = DEFAULT_SENSES_FOR_FULL_CREDIT
## Cap on remembered searches, for the same reason as max_evidence_count.
@export_range(4, 256, 1) var max_disconfirmation_count: int = 48

@export_group("Player association")
## Per-second rate at which a player's suspicion climbs toward the evidence attributed
## to them.
@export_range(0.01, 10.0, 0.01, "suffix:/s") var source_association_gain: float = 2.5
## Per-second rate at which it falls when nothing new names them.
@export_range(0.0, 2.0, 0.001, "suffix:/s") var source_association_decay: float = 0.15
## Saturation for per-player suspicion, as hotspot_saturation_rate is for hotspots.
@export_range(0.05, 8.0, 0.05) var player_suspicion_saturation_rate: float = 1.5

@export_group("Signals")
## Smallest change that re-emits overall_suspicion_changed. Suspicion moves every
## single frame, so without a threshold this fires 60 times a second forever and every
## listener does work for a change nothing could act on.
@export_range(0.0, 0.5, 0.001) var suspicion_change_epsilon: float = 0.01


func decay_rate_for(sense: SuspicionEvidence.Sense) -> float:
	match sense:
		SuspicionEvidence.Sense.VISION:
			return vision_decay_rate
		SuspicionEvidence.Sense.TOUCH:
			return touch_decay_rate
		_:
			return hearing_decay_rate


func weight_for(sense: SuspicionEvidence.Sense) -> float:
	match sense:
		SuspicionEvidence.Sense.VISION:
			return vision_weight
		SuspicionEvidence.Sense.TOUCH:
			return touch_weight
		_:
			return hearing_weight


## How much credit a search gets for the number of senses that took part. A sweep on
## no senses at all clears nothing, which is what an aborted scan should amount to.
func disconfirmation_sense_scale(sense_count: int) -> float:
	var full: int = maxi(disconfirmation_senses_for_full_credit, 1)
	return clampf(float(sense_count) / float(full), 0.0, 1.0)


## Map accumulated support onto 0..1 without a hard clamp, so more evidence always
## means more suspicion with diminishing returns. A clamp would make everything above
## the ceiling read identically, and "as suspicious as it is possible to be" would
## stop being distinguishable from "moderately suspicious".
func saturate(total: float, rate: float) -> float:
	if total <= 0.0:
		return 0.0
	return 1.0 - exp(-maxf(rate, 0.0) * total)


## Cross-field rules no single @export_range can express. Called by the static
## verifier and by the tests, mirroring PerceptionConfig.invariant_failures().
func invariant_failures() -> PackedStringArray:
	var failures := PackedStringArray()
	failures.append_array(_decay_failures())
	if evidence_min_retention_strength >= 1.0:
		failures.append(
			(
				"evidence_min_retention_strength %.2f is >= 1: no evidence is ever retained"
				% evidence_min_retention_strength
			)
		)
	if hotspot_merge_distance > hotspot_max_radius * 2.0:
		(
			failures
			. append(
				(
					"hotspot_merge_distance %.1f exceeds twice hotspot_max_radius %.1f: clusters form that cannot be represented"
					% [hotspot_merge_distance, hotspot_max_radius]
				)
			)
		)
	if resolved_hotspot_threshold >= 1.0:
		(
			failures
			. append(
				(
					"resolved_hotspot_threshold %.2f is >= 1: every hotspot resolves the moment it forms"
					% resolved_hotspot_threshold
				)
			)
		)
	if hotspot_sample_count < 1:
		(
			failures
			. append(
				"hotspot_sample_count is 0: get_best_unresolved_location can only ever return the hotspot centre"
			)
		)
	if hotspot_saturation_rate <= 0.0:
		failures.append(
			"hotspot_saturation_rate is 0: every hotspot reads 0 suspicion regardless of evidence"
		)
	if player_suspicion_saturation_rate <= 0.0:
		failures.append("player_suspicion_saturation_rate is 0: every player reads 0 suspicion")
	if source_association_gain <= 0.0:
		failures.append(
			"source_association_gain is 0: evidence never becomes associated with a player"
		)
	if disconfirmation_senses_for_full_credit < 1:
		failures.append(
			"disconfirmation_senses_for_full_credit is 0: no search ever clears anything"
		)
	return failures


## A negative rate is exp() of a POSITIVE exponent: the record grows without bound,
## the alien becomes permanently and increasingly certain about a footstep it heard
## once, and nothing anywhere errors.
func _decay_failures() -> PackedStringArray:
	var failures := PackedStringArray()
	var rates: Dictionary = {
		"hearing_decay_rate": hearing_decay_rate,
		"vision_decay_rate": vision_decay_rate,
		"touch_decay_rate": touch_decay_rate,
		"searched_area_recovery_rate": searched_area_recovery_rate,
		"source_association_decay": source_association_decay,
	}
	for field: String in rates:
		if float(rates[field]) < 0.0:
			failures.append(
				"%s is negative (%.3f): belief would grow without bound" % [field, rates[field]]
			)
	return failures
