class_name EncounterDirector
extends Node

## What should happen for this to remain a good horror encounter (director.md).
##
## LEVEL-SCOPED, NOT PER-CREATURE. It owns facts no single alien can legitimately own: time
## since the last encounter anywhere, the state of every player, the tempo of the session so
## far. Party-wide state -- lull, session history -- lives here; menace, phase, target and the
## timers live on one EncounterTrack per registered creature.
##
## IT CALLS INTO NOTHING. Once per tick it publishes one EncounterDirective per creature and
## Behavior reads it. There is no method here that transitions an HFSM, issues a destination,
## writes a belief or touches a sense -- not "should not": the interfaces do not exist, and
## `tools/verify_director_static.gd` fails the build if one appears.
##
## THE TICK, AND WHY IT IS ITS OWN _physics_process:
##
## ```text
## _physics_process(delta) -> advance(delta)     integrate, derive, arbitrate, publish
## exchange(creature, report)                    file the report, hand back the directive
## ```
##
## `exchange()` INTEGRATES NOTHING, and that is the load-bearing half of the split. It is
## called once per creature per frame from CreatureBehavior's step 4, so a Director that
## accumulated there would advance the PARTY-WIDE lull once per creature -- a level with two
## aliens would get bored twice as fast, in tree order, with nothing in the log. Deriving a
## delta from `report.time_in_state` is worse still: that field resets to 0.0 on every
## transition, so the difference is NEGATIVE on exactly the tick a hunt begins, and menace
## would silently fail to integrate on the one edge this module exists to price.
##
## `Time.get_ticks_msec()` IS BANNED HERE, and correctly -- it ignores get_tree().paused and
## Engine.time_scale, and no test could drive it. The injected delta is the only time.
##
## CreatureBehavior._mute_subsystems() SWITCHES OFF ITS SIBLINGS' _physics_process AND DOES
## NOT NAME THIS NODE. That is currently true by omission, which is not a property, so the
## static verifier reads that function's body and fails if `director` ever appears in it, and
## the runtime verifier asserts this clock advances once per frame rather than zero or twice.
##
## THE DIRECTIVE A CREATURE READS WAS INTEGRATED THIS FRAME OR LAST, depending on tree order.
## Put this node ABOVE the creatures in the level scene and it is this frame. That is a
## freshness preference and never a correctness requirement: two report fields are already
## deliberately one tick behind, for the reason the module README gives -- 16 ms fresher,
## against a menace curve priced in seconds.

## Every override is attributable. director.md: "the alien left" is not a bug report; "the
## alien left, SATED, menace 1.00 at t+47" is.
signal encounter_phase_changed(
	creature: Node, from: EncounterDirective.Phase, to: EncounterDirective.Phase
)
signal target_changed(creature: Node, from: Node, to: Node)
signal disengage_requested(creature: Node, reason: EncounterDirective.Reason)
signal lethality_changed(creature: Node, lethality: EncounterDirective.Lethality)

## Exchanges taken with the clock still at zero before this node says so. One warning, not one
## per frame: a Director whose advance() is never called publishes a permanently neutral
## directive, which looks exactly like no Director at all and is the harder bug of the two.
const INERT_EXCHANGE_WARNING: int = 120

@export var config: DirectorConfig = null
## Forwarded to the party. Explicit wiring wins; the group is the fallback.
@export var players: Array[Node3D] = []
@export var player_group: StringName = &"player"
## Creatures to pace. Optional -- exchange() registers an unknown creature on sight, so a
## level that writes `behavior.director = director` and nothing else works.
@export var creatures: Array[Node] = []

## The Director's own clock, from the delta it is handed. See the class docstring.
var clock: float = 0.0
## 0..1, PARTY-WIDE. Accumulated dead air.
var lull: float = 0.0
## The only thing in this module that knows where anybody actually is.
var party: DirectorParty = null

var _tracks: Dictionary = {}
var _respawn_at: Dictionary = {}
var _watched: Dictionary = {}
var _session_reached_peak: bool = false
var _exchanges_while_inert: int = 0
var _warned_inert: bool = false


func _init() -> void:
	# Built here rather than in _ready(), so a Director created with .new() and never added to
	# a tree is fully usable -- the property the four shipped creature facades have, and the
	# reason this whole module tests without a scene.
	party = DirectorParty.new()
	party.name = "DirectorParty"


func _ready() -> void:
	if config == null:
		config = DirectorConfig.new()
		push_warning("EncounterDirector has no DirectorConfig; running on script defaults.")
	_bind()


func _physics_process(delta: float) -> void:
	advance(delta)


## The party is built in _init() and only ADOPTED once this node is in a tree, so a Director
## that never entered one owns a Node nothing will ever free. That is every GUT fixture in
## this module, and it shows up as an orphan count rather than as a failure.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and party != null and party.get_parent() == null:
		party.free()


## The single tick entry point, public so a test or a headless tool can drive it exactly.
func advance(delta: float) -> void:
	_bind()
	clock += delta
	party.refresh()
	_advance_lull(delta)
	for track: EncounterTrack in _tracks.values():
		_advance_track(track, delta)


## One struct up, one struct down. Called from CreatureBehavior's step 4, once per creature
## per tick, and it accumulates nothing -- see the class docstring.
##
## RETURNS THE SAME OBJECT EVERY TICK. director.md's "exactly one directive is in effect per
## creature per tick, no mid-frame revisions" is easier to hold when there is literally one.
func exchange(creature: Node, report: EncounterReport) -> EncounterDirective:
	var track: EncounterTrack = register(creature)
	if track == null:
		return EncounterDirective.neutral()
	if report != null:
		track.report = report
	_warn_if_inert()
	return track.directive


## Idempotent. Explicit `suspicion` wins; otherwise it is read off the creature's own wiring.
func register(creature: Node, suspicion: CreatureSuspicion = null) -> EncounterTrack:
	if creature == null:
		return null
	var key: int = creature.get_instance_id()
	var track: EncounterTrack = _tracks.get(key)
	if track == null:
		track = EncounterTrack.new(creature, _resolve_suspicion(creature, suspicion))
		_tracks[key] = track
	elif suspicion != null:
		track.suspicion = suspicion
	_watch_attacks(creature)
	return track


func unregister(creature: Node) -> void:
	if creature == null:
		return
	var key: int = creature.get_instance_id()
	_tracks.erase(key)
	if _watched.erase(key) and creature.has_signal(&"attack_landed"):
		for connection: Dictionary in creature.get_signal_connection_list(&"attack_landed"):
			if (connection.callable as Callable).get_object() == self:
				creature.disconnect(&"attack_landed", connection.callable)


## Arms respawn grace for one player. OPT-IN, and nothing in the project calls it today.
##
## The Director may know the truth, but a respawn is an EVENT rather than a state, and there
## is nothing to poll -- so the level connects it in the one line the README documents:
##
## ```gdscript
## player.respawned.connect(func() -> void: director.note_respawn(player))
## ```
func note_respawn(player: Node) -> void:
	if player == null:
		return
	_respawn_at[player.get_instance_id()] = clock


func track_for(creature: Node) -> EncounterTrack:
	return _tracks.get(creature.get_instance_id()) if creature != null else null


func tracks() -> Array:
	return _tracks.values()


## One line answering "why is the scene like this": phase, both meters, and what is forced.
func describe() -> String:
	var track: EncounterTrack = _first_track()
	if track == null:
		return "DIRECTOR  no creature registered"
	var forcing: String = (
		EncounterDirective.reason_name(track.disengage_reason)
		if track.disengage_reason != EncounterDirective.Reason.NONE
		else "--"
	)
	return (
		"%s  menace %.2f  lull %.2f  forcing %s"
		% [EncounterDirective.phase_name(track.phase), track.menace, lull, forcing]
	)


func debug_state() -> Dictionary:
	var found: Array = []
	for track: EncounterTrack in _tracks.values():
		found.append(track.to_dictionary())
	return {
		"clock": clock,
		"lull": lull,
		"session_reached_peak": _session_reached_peak,
		"party": party.size(),
		"anchor": party.anchor(),
		"tracks": found,
	}


## Back to the top of the session. Clears the peak history too, so a reset level teaches again.
func reset() -> void:
	clock = 0.0
	lull = 0.0
	_session_reached_peak = false
	_respawn_at.clear()
	for track: EncounterTrack in _tracks.values():
		track.end_encounter()
		track.phase = EncounterDirective.Phase.QUIET
		track.directive = EncounterDirective.neutral()


## Idempotent, and re-run every tick rather than only in _ready(): @export-injected siblings
## have no guaranteed _ready() order relative to a node that is not their ancestor.
func _bind() -> void:
	if config == null:
		config = DirectorConfig.new()
	party.players = players
	party.player_group = player_group
	if party.get_parent() == null and is_inside_tree():
		add_child(party)
	for creature: Node in creatures:
		register(creature)


## Read off the creature's own public wiring, purely to obtain the read-only belief facade the
## spec grants the Director. A creature with none gets a track with no target arbitration, and
## the debug panel says so rather than the encounter silently never naming anybody.
func _resolve_suspicion(creature: Node, explicit: CreatureSuspicion) -> CreatureSuspicion:
	if explicit != null:
		return explicit
	return creature.get(&"suspicion") as CreatureSuspicion


## Connected once per creature and tracked by id, because Callable.bind() returns a NEW
## Callable every call -- so is_connected() would answer false forever and the handler would
## be connected once per frame.
func _watch_attacks(creature: Node) -> void:
	var key: int = creature.get_instance_id()
	if _watched.has(key) or not creature.has_signal(&"attack_landed"):
		return
	_watched[key] = true
	creature.connect(&"attack_landed", _on_attack_landed.bind(creature))


## Dead air, party-wide. Rises only while EVERY track is QUIET and belief is genuinely calm.
##
## THE PARTY SUSPICION IS A MAX, NOT A MEAN. One stalked player stops the clock; averaging
## would let a second, calm creature dilute the first one's belief and the Director would go
## on getting bored while somebody was being hunted.
func _advance_lull(delta: float) -> void:
	if _any_track_engaged() or _party_suspicion() >= config.calm_suspicion_threshold:
		return
	lull = minf(lull + delta / maxf(config.lull_full_s, 0.001), EncounterPacing.FULL)


func _any_track_engaged() -> bool:
	for track: EncounterTrack in _tracks.values():
		if track.in_encounter():
			return true
	return false


func _party_suspicion() -> float:
	var highest: float = 0.0
	for track: EncounterTrack in _tracks.values():
		if track.suspicion != null:
			highest = maxf(highest, track.suspicion.get_overall_suspicion())
	return highest


## The per-track order, and the order IS the design. Integrate, derive, act on the edges,
## arbitrate, resolve lethality, publish, then say what changed.
func _advance_track(track: EncounterTrack, delta: float) -> void:
	var report: EncounterReport = track.report
	_integrate(track, report, delta)
	var before: EncounterDirective.Phase = track.phase
	track.phase = EncounterPacing.derive_phase(track, report, config)
	_resolve_edges(track, report, before)
	_arbitrate(track)
	_resolve_lethality(track)
	_publish(track)
	if track.phase != before:
		encounter_phase_changed.emit(track.creature, before, track.phase)


## Menace rises ONLY while hunting and decays in every other state, so a one-tick flicker out
## of HUNTING costs w_time rather than the encounter.
func _integrate(track: EncounterTrack, report: EncounterReport, delta: float) -> void:
	var hunting: bool = track.is_hunting()
	var rate: float = config.menace_rate(report, hunting)
	track.menace = clampf(track.menace + rate * delta, 0.0, EncounterPacing.FULL)
	if hunting:
		track.hunt_elapsed += delta
	if track.disengage_reason != EncounterDirective.Reason.NONE:
		track.cooldown_remaining = maxf(track.cooldown_remaining - delta, 0.0)
		track.relief_elapsed += delta


## The four edges. director.md's diagram draws three; the fourth is real and has to be named.
##
## QUIET -> BUILD   the encounter begins, and the lull is zeroed.
## -> PEAK          the earned exit: order SATED, which arms the cooldown, which makes the
##                  NEXT tick derive RELIEF. PEAK therefore lasts exactly one tick, and that
##                  is deliberate -- a phase log containing PEAK is the log saying the exit
##                  was earned, so swallowing it would make the two exits indistinguishable.
## hunt overran     the unearned exit: order STALLED. It never passes through PEAK, because
##                  it fires precisely when menace failed to get there.
## -> QUIET         the encounter ends, from RELIEF after a disengage or from BUILD when
##                  Behavior lost the hunt on its own and menace decayed away. THE FOURTH
##                  EDGE: nothing was ever forced, so disengage_reason stays NONE and
##                  Behavior's own `lost` reason is what carries downstream.
func _resolve_edges(
	track: EncounterTrack, report: EncounterReport, before: EncounterDirective.Phase
) -> void:
	var now: EncounterDirective.Phase = track.phase
	if before == EncounterDirective.Phase.QUIET and now != EncounterDirective.Phase.QUIET:
		track.begin_encounter()
		lull = 0.0
	if track.disengage_reason == EncounterDirective.Reason.NONE:
		if now == EncounterDirective.Phase.PEAK:
			_session_reached_peak = true
			_order_disengage(track, report, EncounterDirective.Reason.SATED)
		elif track.hunt_elapsed >= config.hunt_max_duration_s:
			_order_disengage(track, report, EncounterDirective.Reason.STALLED)
	if before != EncounterDirective.Phase.QUIET and now == EncounterDirective.Phase.QUIET:
		_finish_encounter(track)


func _order_disengage(
	track: EncounterTrack, report: EncounterReport, reason: EncounterDirective.Reason
) -> void:
	track.order_disengage(reason, report.position, config.cooldown_s)
	disengage_requested.emit(track.creature, reason)


## Re-seeds the party lull, but only once the WHOLE party is out of an encounter: a second
## alien still hunting is not dead air, whatever this one just did.
func _finish_encounter(track: EncounterTrack) -> void:
	var stalled: bool = track.disengage_reason == EncounterDirective.Reason.STALLED
	track.end_encounter()
	if _any_track_engaged():
		return
	lull = config.stalled_lull_retention if stalled else 0.0


func _arbitrate(track: EncounterTrack) -> void:
	# THE DEAD TARGET GOES FIRST, and it has to. A FREED Node is not `== null` in GDScript --
	# it is a dangling reference that passes every null guard -- so a release left until after
	# the margin read would hand it to get_player_suspicion() and then assign it onto the
	# directive, which is two engine errors and a target nobody can hunt. Cleared silently:
	# there is no change to announce FROM a node that no longer exists, and the arbitration
	# immediately below announces whatever it picks instead.
	if EncounterPacing.is_dead(track.target):
		track.commit_target(null, clock)
	var runner: PlayerSuspicionCandidate = EncounterPacing.runner_up(track)
	track.runner_up = runner.player if runner != null else null
	track.runner_up_margin = _margin_over(track, runner)
	var chosen: Node = EncounterPacing.arbitrate(track, config, clock)
	if chosen == track.target:
		return
	var previous: Node = track.target
	track.commit_target(chosen, clock)
	target_changed.emit(track.creature, previous, chosen)


## How far the held target leads the runner-up. Debug only; nothing gates on it.
func _margin_over(track: EncounterTrack, runner: PlayerSuspicionCandidate) -> float:
	if track.suspicion == null or not EncounterPacing.is_live(track.target):
		return 0.0
	var held: float = track.suspicion.get_player_suspicion(track.target)
	return held - (runner.suspicion if runner != null else 0.0)


func _resolve_lethality(track: EncounterTrack) -> void:
	var next: EncounterDirective.Lethality = EncounterPacing.lethality_for(
		track, config, _session_reached_peak, _respawn_fresh(track.target)
	)
	if next == track.lethality:
		return
	track.lethality = next
	lethality_changed.emit(track.creature, next)


## Untyped for the reason EncounterPacing.is_live() documents: a freed target reaching a
## `Node`-typed parameter is an engine error before the body ever runs.
func _respawn_fresh(player: Variant) -> bool:
	if not EncounterPacing.is_live(player):
		return false
	var stamped: Variant = _respawn_at.get((player as Node).get_instance_id())
	return stamped != null and clock - float(stamped) < config.respawn_grace_s


## Writes every field of the one reused directive. The whole of what leaves this module.
##
## permit_hunt IS FALSE FOR EXACTLY THE LENGTH OF RELIEF, and force_disengage stays TRUE for
## the same span rather than for one frame. CreatureHfsm latches the flag on observation
## because min_dwell_s routinely delays the check by whole seconds -- but a directive that
## dropped it after one tick would still be betting the encounter on that latch, and the
## producer has no reason to make that bet.
func _publish(track: EncounterTrack) -> void:
	var directive: EncounterDirective = track.directive
	var biases: Vector2 = _biases(track)
	directive.phase = track.phase
	directive.menace = track.menace
	directive.lull = lull
	directive.target = track.target
	directive.target_committed_at = track.target_committed_at
	directive.permit_hunt = track.phase != EncounterDirective.Phase.RELIEF
	directive.force_disengage = track.disengage_reason != EncounterDirective.Reason.NONE
	directive.disengage_reason = track.disengage_reason
	directive.lethality = track.lethality
	directive.escalation_bias = biases.x
	directive.roam_bias = biases.y
	directive.roam_anchor = party.anchor()


## The (escalation_bias, roam_bias) pair, always locked at DirectorConfig's ratio.
##
## ROAM IS ZEROED WITH NOBODY IN THE PARTY, because DirectorParty.anchor() answers
## Vector3.ZERO then -- and the world origin is a real place, so a nest near it would collect
## a roam bonus for no reason at all. Zeroing the weight makes the anchor irrelevant rather
## than merely harmless.
func _biases(track: EncounterTrack) -> Vector2:
	var pair: Vector2 = (
		config.relief_outputs()
		if track.phase == EncounterDirective.Phase.RELIEF
		else config.lull_outputs(lull)
	)
	return Vector2(pair.x, 0.0) if party.size() == 0 else pair


func _first_track() -> EncounterTrack:
	for track: EncounterTrack in _tracks.values():
		return track
	return null


## Says so, once, if something is exchanging with a Director nobody is ticking.
func _warn_if_inert() -> void:
	if _warned_inert or clock > 0.0:
		return
	_exchanges_while_inert += 1
	if _exchanges_while_inert < INERT_EXCHANGE_WARNING:
		return
	_warned_inert = true
	push_warning(
		(
			(
				"EncounterDirector.exchange() has been called %d times and advance() never has; "
				+ "the creature is reading a permanently neutral directive and is unpaced."
			)
			% _exchanges_while_inert
		)
	)


func _on_attack_landed(
	_target: Node, lethality: EncounterDirective.Lethality, creature: Node
) -> void:
	# ONE NEAR-MISS PER ENCOUNTER. Only a GRACE strike spends the grace; a lethal one has
	# nothing to spend. The flip to LETHAL is published by _resolve_lethality on the next
	# tick, so exactly one place emits lethality_changed.
	if lethality != EncounterDirective.Lethality.GRACE:
		return
	var track: EncounterTrack = track_for(creature)
	if track != null:
		track.grace_consumed = true
