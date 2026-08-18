class_name EncounterDirective
extends RefCounted

## What the Director asks of one creature, for one tick (director.md, "The single output").
##
## PRESSURE AND PERMISSION, NEVER A FACT. Every field here is how willing the creature
## should be, how close it should drift, whether a hunt may begin or must end. None of it
## is a position the alien navigates to or a piece of evidence it believes -- `target` is
## an arbitration result the creature must still find for itself, and `roam_anchor`
## weights a list of nests it already knows. That asymmetry is what keeps the Director
## from being a cheat.
##
## THE DIRECTOR ITSELF IS NOT BUILT. This is the value type Behavior reads, shipped ahead
## of its producer so every fsm.md transition guard can be written as specified rather
## than rewritten later. `neutral()` is what Behavior uses when no Director is present.

enum Phase { QUIET, BUILD, PEAK, RELIEF }

## Why a hunt ended. SATED is the earned exit and leaves loudly; STALLED is the unearned
## one and leaves quietly, because nothing was earned.
enum Reason { NONE, SATED, STALLED }

## GRACE resolves an attack as a near-miss. Behavior owns the animation and the damage;
## the Director owns only the flag.
enum Lethality { GRACE, LETHAL }

var phase: Phase = Phase.QUIET
## 0..1. How much pressure THIS creature's encounter has actually delivered.
var menace: float = 0.0
## 0..1, party-wide. Accumulated dead air.
var lull: float = 0.0

## The arbitrated hunt target. May be null, and Behavior falls back to hotspot search when
## it is. Never a position -- the alien still has to find this player itself.
var target: Node = null
var target_committed_at: float = 0.0

## Hard gate on entering HUNTING, from any source. False throughout RELIEF.
var permit_hunt: bool = true
## Forces HUNTING -> RETREATING. A LATCH the HFSM consumes at its next transition check,
## never a mid-action interrupt: a leap or an attack animation is allowed to finish.
var force_disengage: bool = false
var disengage_reason: Reason = Reason.NONE

## -1..+1. Shifts the investigate and hunt thresholds by `bias * BehaviorConfig.bias_span`.
## Negative during RELIEF, positive as lull grows. It does NOT shift direct_hunt_threshold.
var escalation_bias: float = 0.0
var lethality: Lethality = Lethality.LETHAL
## -1..+1, toward or away from the party. One extra weighting term on nest choice.
var roam_bias: float = 0.0
## What "toward" means. Derived from real player positions, so it may weight nest odds and
## may never be navigated to or measured from.
var roam_anchor: Vector3 = Vector3.ZERO


## The no-Director directive: no pressure, no permission withheld, no bias.
##
## `permit_hunt` is TRUE and `lethality` is LETHAL, which is the pair worth arguing about.
## A neutral directive must not be a silent difficulty setting -- an alien that cannot hunt
## because nobody wired a Director reads as a broken HFSM, and first-encounter grace is a
## pacing decision that only a Director has the session history to make.
static func neutral() -> EncounterDirective:
	return EncounterDirective.new()


static func phase_name(value: Phase) -> String:
	match value:
		Phase.QUIET:
			return "quiet"
		Phase.BUILD:
			return "build"
		Phase.PEAK:
			return "peak"
		Phase.RELIEF:
			return "relief"
	return "?"


static func reason_name(value: Reason) -> String:
	match value:
		Reason.NONE:
			return "none"
		Reason.SATED:
			return "sated"
		Reason.STALLED:
			return "stalled"
	return "?"


func to_dictionary() -> Dictionary:
	return {
		"phase": phase_name(phase),
		"menace": menace,
		"lull": lull,
		"target": target,
		"permit_hunt": permit_hunt,
		"force_disengage": force_disengage,
		"disengage_reason": reason_name(disengage_reason),
		"escalation_bias": escalation_bias,
		"lethality": "grace" if lethality == Lethality.GRACE else "lethal",
		"roam_bias": roam_bias,
	}
