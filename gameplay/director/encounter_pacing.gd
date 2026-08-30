class_name EncounterPacing
extends RefCounted

## The Director's decisions, as pure functions of a track, a report and a config.
##
## ALL STATIC, ALL PURE, NOTHING MUTATED. director.md's claim is that the whole coupling is
## "a pure function of two structs, so it tests without a scene, a body, or a baked graph" --
## and that is only literally true if the deciding lives somewhere that cannot reach a node,
## a clock or a signal. This is that somewhere. EncounterDirector integrates the accumulators
## and emits the signals; every judgement call is here, and every one of them is checkable by
## handing it three values and reading the answer.
##
## THE PHASE IS DERIVED, NOT DRIVEN. director.md is explicit that it is "not a second
## hand-written state machine -- it is a value computed from the accumulators". So there is
## no set_phase, no transition table and no per-edge handler: `derive_phase` is evaluated
## from scratch every tick, in order, first match wins. The only latch anywhere in it is
## `disengage_reason`, and director.md declares force_disengage a latch outright.

## Menace and lull are both 0..1 by definition, and every clamp in the module quotes this
## rather than a bare literal.
const FULL: float = 1.0


## Whether the creature has got far enough from where it gave up for RELIEF to be allowed to
## end. One half of the RELIEF -> QUIET rule (director.md names cooldown_separation_m and
## never defines the rule; this is it).
##
## REACHING UNALERTED SATISFIES IT OUTRIGHT, and that is not a shortcut. `RETREATING ->
## UNALERTED` is Behavior's alone, gated on retreat_min_s AND retreat_separation_m, with
## retreat_max_s as a hard backstop -- so a creature in UNALERTED has already passed a
## separation test of its own, and a Director second-guessing it would be the Director
## CONDUCTING a retreat rather than asking for one. It is also what stops RELIEF hanging
## forever: retreat_max_s guarantees UNALERTED arrives, where a pure distance gate against a
## creature whose only nests sit nearby would never open.
static func separated(
	track: EncounterTrack, report: EncounterReport, config: DirectorConfig
) -> bool:
	if report.state == CreatureState.State.UNALERTED:
		return true
	return track.disengage_position.distance_to(report.position) >= config.cooldown_separation_m


## Whether the cooldown is still running. Both clauses, never either.
##
## A timer alone lets a creature that never actually left -- one whose nearest nest is where
## the encounter happened -- re-arm the whole cycle on the player's doorstep. A distance gate
## alone lets a creature that sprints away re-arm in three seconds, and the exhale has no
## length. Neither failure errors; both read as the alien cheating its own retreat.
static func in_relief(
	track: EncounterTrack, report: EncounterReport, config: DirectorConfig
) -> bool:
	if track.disengage_reason == EncounterDirective.Reason.NONE:
		return false
	if track.cooldown_remaining > 0.0:
		return true
	return not separated(track, report, config)


## The scene's arc, computed fresh every tick. In order; first match wins.
##
## RELIEF OUTRANKS EVERYTHING, so a hunt cannot restart inside a cooldown however loudly the
## player behaves. PEAK is reached only from menace, and menace only rises while HUNTING, so
## PEAK implies the creature was hunting on the crossing tick.
##
## BUILD KEYS OFF report.state AS WELL AS MENACE, and it has to. Menace integrates only while
## HUNTING, so an investigation carries zero menace -- and the worked encounter's t+12 edge
## into BUILD is an INVESTIGATING edge with the meter still at nothing. Without the state
## clause the lull would go on rising through the whole investigation.
##
## ONCE A DISENGAGE IS ORDERED THE ONLY PHASES LEFT ARE RELIEF AND QUIET, and that clause is
## load-bearing rather than tidy. Without it the cooldown expiring hands the derivation back
## to the menace-and-state test while the creature is still walking away, and the phase log
## reads `relief -> build -> quiet` -- which is a lie about the one thing the log exists to
## say. It also briefly restores permit_hunt mid-retreat. An encounter that has been told to
## end cannot build again; it can only finish.
static func derive_phase(
	track: EncounterTrack, report: EncounterReport, config: DirectorConfig
) -> EncounterDirective.Phase:
	if track.disengage_reason != EncounterDirective.Reason.NONE:
		return (
			EncounterDirective.Phase.RELIEF
			if in_relief(track, report, config)
			else EncounterDirective.Phase.QUIET
		)
	if track.menace >= config.peak_threshold:
		return EncounterDirective.Phase.PEAK
	if track.menace > 0.0 or _is_engaged(report.state):
		return EncounterDirective.Phase.BUILD
	return EncounterDirective.Phase.QUIET


## Whether this strike kills (director.md, "Kill grace").
##
## THE LATCH IS TESTED FIRST, because the spec says it holds "regardless of any condition
## above". After one near-miss the encounter is lethal for the rest of its length even with
## menace still under the threshold -- otherwise a player eventually notices they are safe.
static func lethality_for(
	track: EncounterTrack, config: DirectorConfig, session_reached_peak: bool, respawn_fresh: bool
) -> EncounterDirective.Lethality:
	if track.grace_consumed:
		return EncounterDirective.Lethality.LETHAL
	if config.first_encounter_grace and not session_reached_peak:
		return EncounterDirective.Lethality.GRACE
	if respawn_fresh:
		return EncounterDirective.Lethality.GRACE
	if track.menace < config.lethal_menace_threshold:
		return EncounterDirective.Lethality.GRACE
	return EncounterDirective.Lethality.LETHAL


## Who this creature should be hunting, given who it currently holds.
##
## STICKINESS LIVES HERE RATHER THAN IN SUSPICION because Suspicion's job is to be accurate,
## and accuracy oscillates. Committing to a slightly-wrong target is a Director decision.
##
## A NULL BEST CANDIDATE DOES NOT DROP A COMMITTED TARGET. Hunting is a commitment that
## survives brief perception loss -- HuntingState already falls back to the strongest lead
## when the target has no attributed hotspot -- so the target is released only by becoming
## invalid, by losing the margin test, or by the encounter ending.
static func arbitrate(track: EncounterTrack, config: DirectorConfig, now: float) -> Node:
	var current: Node = track.target
	if is_dead(current):
		# Released outright, and the commit window deliberately does not apply: the commitment
		# was to a node that no longer exists. Publishing a dangling one would have
		# HuntingState comparing hotspot attribution against garbage.
		current = null
	if track.suspicion == null:
		return current
	var best: PlayerSuspicionCandidate = track.suspicion.get_best_player_candidate()
	if best == null or best.player == current:
		return current
	if current == null:
		return best.player
	if now - track.target_committed_at < config.min_target_commit_s:
		return current
	var held: float = track.suspicion.get_player_suspicion(current)
	return best.player if best.suspicion - held >= config.retarget_margin else current


## The strongest candidate who is NOT the held target, for the debug panel's margin.
##
## DEBUG ONLY, AND IT READS A COLLABORATOR FIELD. `get_best_player_candidate()` cannot answer
## "who came second" when the best IS the target, so this reaches `suspicion.player_beliefs`
## -- the same idiom CreatureBehavior documents when it keeps collaborators as public fields
## so "a debug panel can read hfsm.time_in_state without the facade growing an accessor per
## thing worth knowing". Arbitration above uses only the three methods director.md names, so
## the spec's interface claim stays literally true.
static func runner_up(track: EncounterTrack) -> PlayerSuspicionCandidate:
	if track.suspicion == null or track.suspicion.player_beliefs == null:
		return null
	var best: PlayerSuspicionCandidate = null
	for candidate: PlayerSuspicionCandidate in track.suspicion.player_beliefs.get_candidates():
		if candidate.player == track.target:
			continue
		if best == null or candidate.suspicion > best.suspicion:
			best = candidate
	return best


## Whether a held target is still a thing that can be hunted.
##
## THE PARAMETER IS UNTYPED, AND IT HAS TO BE. Passing a freed object to a `Node`-typed
## parameter is itself an engine error -- "the Object-derived class of argument 1 (previously
## freed) is not a subclass of the expected argument class" -- so a liveness check that
## declared the type it is checking for could never be called on the one value it exists to
## reject. Every caller therefore passes through Variant, and this is the only place in the
## module that does.
##
## FREED ONLY, NOT DETACHED. A node outside the tree is not gone -- every GUT fixture in this
## project builds detached nodes on purpose, and CreatureBehavior._body_position() and
## DirectorParty both tolerate them rather than treating them as dead. Requiring
## is_inside_tree() here would release the target on the first tick of every test.
static func is_live(node: Variant) -> bool:
	return typeof(node) == TYPE_OBJECT and is_instance_valid(node)


## Whether a target was somebody and has since been freed, as opposed to never being set.
##
## `typeof` RATHER THAN `!= null`, AND THE DIFFERENCE IS THE WHOLE FUNCTION. A freed object
## compares EQUAL to null in GDScript, so `target != null and not is_live(target)` -- the
## obvious way to write this -- is false for exactly the value it is meant to catch, and the
## dangling reference sails through onto the directive. A freed Variant is still TYPE_OBJECT;
## an unset one is TYPE_NIL. That is the only test that tells them apart, and the distinction
## matters because releasing an unset target every tick would re-stamp target_committed_at
## and quietly disable min_target_commit_s.
static func is_dead(node: Variant) -> bool:
	return typeof(node) == TYPE_OBJECT and not is_instance_valid(node)


## Whether Behavior is actively pursuing something, as opposed to wandering or leaving.
##
## RETREATING IS NOT ENGAGED, and excluding it is deliberate. behavior.md section 30 defines
## that state as ending the encounter legibly -- it has exactly one exit and it is not
## HUNTING -- so counting it as a reason to be in BUILD would hold the phase open on a
## creature that is definitionally finished. What keeps the encounter alive through a retreat
## the Director never ordered is the menace clause above: the pressure is still on the board
## until it has drained, and then the encounter is over whatever the creature is still doing
## with its feet.
static func _is_engaged(state: CreatureState.State) -> bool:
	return (
		state == CreatureState.State.INVESTIGATING
		or state == CreatureState.State.HUNTING
		# RECONSIDERING is a pause INSIDE an investigation, not the end of one. Reading it as
		# disengaged drains the track toward QUIET for the few seconds the creature stands
		# still and re-arms the moment it moves again, which flaps the phase over a beat the
		# player is meant to read as the creature thinking.
		or state == CreatureState.State.RECONSIDERING
	)
