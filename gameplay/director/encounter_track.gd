class_name EncounterTrack
extends RefCounted

## One creature's pacing state, and the directive it is published (director.md, "Scope").
##
## PARTY-WIDE STATE IS NOT HERE. Lull and session history belong to the level and live on
## EncounterDirector; menace, phase, target and the timers are properties of ONE creature's
## encounter and live here. That split is what lets the Director direct the one alien today
## and extend to several without redesign.
##
## THE DIRECTIVE IS ONE OBJECT, REUSED FOREVER. It is mutated in place and republished every
## tick, never reallocated -- `behavior_test_case.gd` already establishes that shape by
## mutating the stub's directive and expecting the creature to see it, and director.md's
## "exactly one directive is in effect per creature per tick" is easier to hold when there is
## literally one.
##
## IT STARTS NEUTRAL, WHICH IS THE PROMISE THE MODULE README MAKES. A creature that exchanges
## before the Director's first `advance()` gets exactly EncounterDirective.neutral() -- so
## "the day the Director lands nothing in Behavior changes" is true on frame one rather than
## approximately true.

## The creature this track paces. Held rather than looked up, because EncounterDirector keys
## its tracks by instance id and a dictionary key is not a reference.
var creature: Node = null
## The creature's belief, READ-ONLY AND FOREVER. director.md grants exactly three reads and
## no writes: Suspicion has three doors -- evidence, disconfirmation, the clock -- and the
## Director is not one of them.
var suspicion: CreatureSuspicion = null

## The one directive, mutated in place. See the class docstring.
var directive: EncounterDirective = null
## The last report Behavior filed. Never mutated here; the Director reads it and nothing else.
var report: EncounterReport = null

## 0..1. How much pressure THIS encounter has actually delivered.
var menace: float = 0.0
## Derived every tick from the accumulators. NOT a second state machine -- see
## EncounterPacing.derive_phase, which is the whole of it.
var phase: EncounterDirective.Phase = EncounterDirective.Phase.QUIET

## The arbitrated target. A Node, never a position.
var target: Node = null
## Director clock at the last commit. The field EncounterDirective carries under this name has
## no other documented owner, and nothing in the project reads it yet.
var target_committed_at: float = 0.0
## Debug only: who came second, and by how much the held target leads them.
var runner_up: Node = null
var runner_up_margin: float = 0.0

## Seconds this creature has spent in HUNTING during this encounter. Drives the STALLED cap.
var hunt_elapsed: float = 0.0
## Seconds left on the RELIEF timer. One half of the RELIEF -> QUIET rule.
var cooldown_remaining: float = 0.0
## Seconds since the disengage was ordered, for debug and for the phase log.
var relief_elapsed: float = 0.0
## Why this encounter is ending, and the ONLY latch in the phase derivation. Behavior reads it
## once on entering RETREATING to pick the loud or the quiet exit.
var disengage_reason: EncounterDirective.Reason = EncounterDirective.Reason.NONE
## Where the creature was standing when the disengage was ordered. The other half of the
## RELIEF -> QUIET rule measures from here, NOT from a player or from roam_anchor -- an anchor
## that tracked the party could hold a creature in RELIEF indefinitely by moving.
var disengage_position: Vector3 = Vector3.ZERO

var lethality: EncounterDirective.Lethality = EncounterDirective.Lethality.LETHAL
## Set the moment a GRACE strike lands, cleared only at the end of the encounter.
##
## ONE NEAR-MISS PER ENCOUNTER, and this is the whole of it. Without the latch a player
## eventually notices they are safe, and a horror game the player knows cannot kill them has
## no remaining mechanism.
var grace_consumed: bool = false

## Encounters this creature has had. Debug, and the thing that makes a log line placeable.
var encounter_index: int = 0


func _init(p_creature: Node = null, p_suspicion: CreatureSuspicion = null) -> void:
	creature = p_creature
	suspicion = p_suspicion
	directive = EncounterDirective.neutral()
	report = EncounterReport.new()


## True while Behavior says the creature is actually hunting, which is the only state menace
## integrates in. Everything else decays it.
func is_hunting() -> bool:
	return report != null and report.state == CreatureState.State.HUNTING


## True while the creature is in an encounter at all, which is any phase but QUIET.
func in_encounter() -> bool:
	return phase != EncounterDirective.Phase.QUIET


## The QUIET -> BUILD edge. Called once, by the Director, when the phase leaves QUIET.
func begin_encounter() -> void:
	encounter_index += 1
	menace = 0.0
	hunt_elapsed = 0.0
	relief_elapsed = 0.0
	cooldown_remaining = 0.0
	grace_consumed = false
	disengage_reason = EncounterDirective.Reason.NONE
	disengage_position = Vector3.ZERO


## Either edge back to QUIET: RELIEF -> QUIET after a disengage, or BUILD -> QUIET when
## Behavior lost the hunt on its own and menace decayed away.
##
## RELEASES THE TARGET. Stickiness is a commitment to an encounter, not to a person, and a
## creature that walked away still holding you would resume a hunt already arbitrated onto
## somebody it has not seen for a minute.
func end_encounter() -> void:
	menace = 0.0
	hunt_elapsed = 0.0
	relief_elapsed = 0.0
	cooldown_remaining = 0.0
	grace_consumed = false
	disengage_reason = EncounterDirective.Reason.NONE
	target = null
	runner_up = null
	runner_up_margin = 0.0


## Arms the disengage and the cooldown together, because they are one decision.
##
## `at` is where the creature is standing, captured ONCE. The separation clause measures from
## here for the whole of RELIEF, so a live read could never make the distance shrink.
func order_disengage(reason: EncounterDirective.Reason, at: Vector3, cooldown: float) -> void:
	disengage_reason = reason
	disengage_position = at
	cooldown_remaining = cooldown
	relief_elapsed = 0.0


func commit_target(to: Node, now: float) -> void:
	target = to
	target_committed_at = now


## Everything the debug panel needs, in one call, so the panel reads no private state.
func to_dictionary() -> Dictionary:
	return {
		"encounter": encounter_index,
		"phase": EncounterDirective.phase_name(phase),
		"menace": menace,
		"hunt_elapsed": hunt_elapsed,
		"cooldown_remaining": cooldown_remaining,
		"relief_elapsed": relief_elapsed,
		"disengage_reason": EncounterDirective.reason_name(disengage_reason),
		"lethality": "grace" if lethality == EncounterDirective.Lethality.GRACE else "lethal",
		"grace_consumed": grace_consumed,
		"target": target.name if is_instance_valid(target) else "--",
		"runner_up": runner_up.name if is_instance_valid(runner_up) else "--",
		"runner_up_margin": runner_up_margin,
	}
