class_name HuntingMemory
extends SearchMemory

## What HUNTING remembers between ticks: where it believes its target is, whether it can get
## there, and the two deadlines the tree runs on.
##
## A SEPARATE OBJECT FROM THE STATE, the same way UnalertedMemory and InvestigatingMemory are,
## so the tree's leaves can be typed against it without the state and its actions referring to
## each other in a circle -- and so a leaf is unit-testable against three fields and no HFSM.
##
## `last_credible_target_position` IS BELIEF, NEVER TRUTH. It is read off the hotspot the
## creature attributes to its target, so it is wrong exactly as often as the creature is.
## RETREATING borrows it as the point separation is measured from, which is the only other
## consumer.
##
## `beyond_reach` AND THE STALENESS FLAG ARE WHAT KEEP THE CHASE AND LURK BRANCHES APART.
## Both are refreshed once per tick before the tree runs, which is the same arrangement
## INVESTIGATING uses and for the same reason: a condition that worked either out for itself
## would be side-effecting or would command, and the reactive re-tick survives neither.

## Emitted when a strike lands. `lethality` is read off the directive and never decided here;
## the Director owns the flag, Behavior owns the consequence. Relayed by CreatureBehavior,
## which is what animation and damage hang off -- neither exists yet, and neither belongs in
## the decision layer when it does.
signal attack_landed(target: Node, lethality: EncounterDirective.Lethality)

## Where the creature believes the target is, from the hotspot it attributes to them.
var last_credible_target_position: Vector3 = Vector3.ZERO
var has_target_estimate: bool = false
## True when the creature's own graph reaches toward the estimate and stops short.
##
## THAT IS THE WHOLE OF behavior.md SECTION 29'S INFERENCE. The navigation graph is the
## creature's knowledge of which passages it can use, so a place it cannot route to IS a
## place it believes it cannot follow into -- no marker, no flag, no layer, and the reasoning
## generalises to every gap too tight for it rather than to the ones somebody tagged.
var beyond_reach: bool = false
## True when nothing has NAMED the target recently -- no live candidate, or one whose last
## evidence is older than `target_estimate_max_age_s`. Aged on SUSPICION's clock.
##
## IT GATES THE BITE AND NOTHING ELSE. An alien that has lost sight of you still walks to
## where it last believed you were and sweeps that region, which is behavior.md section 28;
## what it may not do is swing at a position it is no longer being told about. Only vision and
## touch set `source_confidence`, so in practice this closes the moment the creature stops
## seeing you -- which is exactly the moment a strike would be a guess.
var estimate_is_stale: bool = true
## Whether the target is inside striking distance right now -- IN REACH, not "about to bite".
##
## The rate limit is a BtCooldown around the bite branch, deliberately not folded in here, and
## the difference is the whole value of the field to the Director. Menace is the pressure of
## having an alien on top of you, which lasts for as long as it is there; folding the cooldown
## in would leave `attack_window_open` true for the single frame a strike fires and false the
## rest of the time, and `w_attack` would price a whole encounter at roughly zero.
##
## Computed by HuntingState.refresh rather than by the condition that gates the bite, so the
## branch that fires and the number the Director reads can never disagree. Two halves that
## each look right on their own is not a bug anybody finds.
var attack_window_open: bool = false
## Behavior-clock time a lurk ends. Zero means "not started", matching
## UnalertedMemory.dwell_until.
var lurk_until: float = 0.0


## Everything a new hunt must not inherit from the last one.
##
## `last_credible_target_position` deliberately survives: it is the only thing RETREATING has
## to measure separation from, and a hunt that starts by forgetting where it thought you were
## has nowhere to go on its first tick.
func forget() -> void:
	has_target_estimate = false
	beyond_reach = false
	estimate_is_stale = true
	attack_window_open = false
	lurk_until = 0.0


func has_search_centre() -> bool:
	return has_target_estimate


func search_centre() -> Vector3:
	return last_credible_target_position
