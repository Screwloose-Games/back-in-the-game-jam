class_name CreatureBehavior
extends Node

## The hinge: the only system that turns belief into action (fsm.md).
##
## Everything upstream -- Perception, Suspicion -- describes the world. Everything downstream
## -- Navigation, Movement -- executes. This decides.
##
## ONE _physics_process, ONE ORDER, NO EXCEPTIONS:
##
## ```text
## 1  clock += delta                        injected, never a wall clock
## 2  perception.advance(delta)             emits evidence / disconfirmation
## 3  suspicion.advance(delta)              decay, hotspot merge, pruning
## 4  directive = director.exchange(...)    report up, directive down, ONCE
## 5  hfsm.evaluate_transitions()           once; a change aborts the old tree
## 6  perception.set_alertness_context()    per-state, from the NEW state
## 7  tree[state].tick(context)             may command navigation
## 8  navigation.advance(delta, position)
## 9  the motor consumes navigation.command
## ```
##
## Steps 2 and 3 are ordered: evidence must land before decay runs and before any query
## reads it. Step 4 happens once, and the directive is held constant for the whole tick.
##
## STEP 6 IS AFTER THE TRANSITION AND BEFORE THE TREE, WHICH MATTERS. Perception has already
## run this tick under the PREVIOUS state's alertness, so the new value takes effect next
## tick -- setting it from a `state_changed` handler instead would apply it a tick early and
## the two would never agree. It is also the one place Behavior writes to Perception, and it
## is legitimate: vision is designed to sharpen once the creature is already suspicious. That
## is the creature's attention responding to its own belief. The Director has no such channel.
##
## `drive_subsystems` SWITCHES OFF THE OTHERS' AUTO-TICK, and that is not tidiness. All three
## facades run their own `_physics_process`, so leaving them on double-advances every clock:
## navigation would age its knowledge twice and emit `motion_planned` TWICE PER FRAME with
## the same body state, and the motor would consume both.
##
## COLLABORATORS ARE PUBLIC FIELDS RATHER THAN GETTERS, following CreatureNavigation. It
## keeps this class under gdlint's public-method cap and lets a debug panel read
## `hfsm.time_in_state` without the facade growing an accessor per thing worth knowing.

## Carries the reason, in the signal and in debug. Every transition has one.
signal state_changed(from: CreatureState.State, to: CreatureState.State, reason: StringName)
## The running leaf changed. Animation and audio read this rather than the state.
signal action_changed(action: StringName)

@export var suspicion: CreatureSuspicion = null
@export var perception: CreaturePerception = null
@export var navigation: CreatureNavigation = null
@export var config: BehaviorConfig = null
## The body this creature moves. Read for facing only -- position goes through
## `body_position`, which is resolved with an is_inside_tree() guard.
@export var body: Node3D = null
## Level-scoped, and duck-typed on purpose: `EncounterDirective` and `EncounterReport` ship
## without an EncounterDirector, so this holds anything with
## `exchange(creature, report) -> EncounterDirective`. Null means the neutral directive.
@export var director: Node = null
## Explicit nests win; the CreatureNest group is the fallback. Empty and ungrouped means the
## alien has nowhere to wander, and UNALERTED will say so once rather than every frame.
@export var nests: Array[Node3D] = []
## When true this node owns the whole tick and mutes the other three facades. See the class
## docstring. Set false and `advance()` runs only steps 4-7.
@export var drive_subsystems: bool = true

## Behavior's own clock, from the delta it is handed. NEVER Time.get_ticks_msec(), which
## ignores get_tree().paused and Engine.time_scale and cannot be driven from a test.
var clock: float = 0.0
var hfsm: CreatureHfsm = null
var goal: BehaviorGoal = null
var context: BehaviorContext = null
## The directive in effect for this tick. Replaced once per tick, never mid-tick.
var directive: EncounterDirective = null

var _last_vision_at: float = -INF
var _muted: bool = false
var _nests_loaded: bool = false
var _started: bool = false


func _init() -> void:
	# Built here rather than in _ready(), so a facade created with .new() and never added to
	# a tree is fully usable -- which is what lets the whole HFSM be tested in GUT with no
	# scene, matching how the three shipped facades do it.
	directive = EncounterDirective.neutral()
	hfsm = CreatureHfsm.new()
	goal = BehaviorGoal.new()
	context = BehaviorContext.new()
	hfsm.add_state(UnalertedState.new())
	hfsm.add_state(InvestigatingState.new())
	hfsm.add_state(HuntingState.new())
	hfsm.add_state(RetreatingState.new())
	hfsm.state_changed.connect(_on_state_changed)


func _ready() -> void:
	if config == null:
		config = BehaviorConfig.new()
		push_warning("CreatureBehavior has no BehaviorConfig; running on script defaults.")
	_start()


func _physics_process(delta: float) -> void:
	advance(delta)


## The single tick entry point, public so a test or a headless tool can drive it exactly.
func advance(delta: float) -> void:
	if config == null:
		config = BehaviorConfig.new()
	_start()
	clock += delta

	if drive_subsystems:
		_mute_subsystems()
		if perception != null:
			perception.advance(delta)
		if suspicion != null:
			suspicion.advance(delta)

	directive = _exchange()
	_refresh_context()

	hfsm.advance_clock(delta)
	hfsm.evaluate_transitions(context)

	if perception != null:
		perception.set_alertness_context(config.alertness_for(hfsm.current))

	hfsm.tick(context)

	if drive_subsystems and navigation != null:
		navigation.set_body_position(context.body_position)
		navigation.advance(delta, context.body_position)


## What only Behavior knows, for the Director. Public because a debug panel wants it too.
func build_report() -> EncounterReport:
	var report := EncounterReport.new()
	report.state = hfsm.current
	report.time_in_state = hfsm.time_in_state
	report.position = context.body_position
	report.route_distance = _route_distance()
	report.target_reachable = _target_reachable()
	report.has_visual_contact = clock - _last_vision_at <= config.visual_contact_grace_s
	# Owed to the HUNTING tree. Hardcoded false zeroes the Director's w_attack and w_lurk
	# terms, so this is a stub rather than tuning.
	report.attack_window_open = false
	report.lurking_at_crevice = false
	return report


func state() -> CreatureState.State:
	return hfsm.current


func running_action() -> StringName:
	return hfsm.running_action()


## One line answering "why is it doing that": state, time in state, active action, the value
## that fired the last transition, and what the directive is currently constraining.
func describe() -> String:
	var gate: String = "hunt" if directive.permit_hunt else "NO-HUNT"
	return (
		"%s | bias %+.2f roam %+.2f %s"
		% [hfsm.describe(), directive.escalation_bias, directive.roam_bias, gate]
	)


func debug_state() -> Dictionary:
	return {
		"state": CreatureState.state_name(hfsm.current),
		"time_in_state": hfsm.time_in_state,
		"action": running_action(),
		"goal": goal.committed() if goal.has_goal() else null,
		"directive": directive.to_dictionary(),
		"report": build_report().to_dictionary(),
	}


## Binds, then enters the initial state exactly once.
##
## DRIVEN FROM advance() AS WELL AS _ready(), so a facade built with .new() and never added
## to a tree behaves identically to one in a scene. That is the property the three shipped
## facades have and the reason the whole HFSM is testable without a scene, a body or a baked
## graph -- a `_ready()`-only entry would leave every GUT fixture in a state it had never
## entered, with no tree ticking and nothing to say why.
func _start() -> void:
	_bind()
	if _started:
		return
	_started = true
	_refresh_context()
	hfsm.reset_to(CreatureState.State.UNALERTED, context)


## Idempotent, and re-run every tick rather than only in _ready(): @export-injected siblings
## have no guaranteed _ready() order relative to a node that is not their ancestor, so a
## one-shot bind can miss a reference that arrives a frame later.
func _bind() -> void:
	goal.navigation = navigation
	goal.config = config
	if not _nests_loaded:
		_load_nests()
	_connect_signals()


func _refresh_context() -> void:
	context.suspicion = suspicion
	context.navigation = navigation
	context.perception = perception
	context.goal = goal
	context.config = config
	context.directive = directive
	context.hfsm = hfsm
	context.body = body
	context.body_position = _body_position()
	context.clock = clock


## Node3D.global_position needs the node to be in a tree. Reading `position` for a detached
## node is exact for a lone node and keeps the whole facade usable in GUT -- the same guard
## CreaturePerception._own_position() uses, and for the same reason.
func _body_position() -> Vector3:
	if body == null:
		return Vector3.ZERO
	return body.global_position if body.is_inside_tree() else body.position


## One struct up, one struct down, once per tick. Duck-typed so nothing here depends on an
## EncounterDirector class that does not exist yet.
func _exchange() -> EncounterDirective:
	if director == null or not director.has_method(&"exchange"):
		return directive
	var published = director.exchange(self, build_report())
	return published if published is EncounterDirective else directive


## INF, not the raw value. RouteFollower.distance_remaining returns 0.0 when there is no
## route, and the Director's proximity term reads a small distance as maximum dread -- so an
## alien idling at a nest would report breathing down your neck, forever.
func _route_distance() -> float:
	if navigation == null or navigation.follower == null or not navigation.follower.has_route():
		return EncounterReport.NO_ROUTE_DISTANCE
	return navigation.follower.distance_remaining(context.body_position)


## True when there is no route at all. "Nowhere to go" is not "cannot reach you", and
## navigation's route is null before the first replan and after every clear_goal.
func _target_reachable() -> bool:
	if navigation == null or navigation.route == null:
		return true
	return navigation.route.status != NavRoute.Status.UNREACHABLE


func _mute_subsystems() -> void:
	if _muted:
		return
	_muted = true
	for node: Node in [perception, suspicion, navigation]:
		if node != null:
			node.set_physics_process(false)
	if perception == null or suspicion == null or navigation == null:
		push_warning(
			"CreatureBehavior drives the tick but a subsystem is missing; the alien is partly blind."
		)


func _connect_signals() -> void:
	if perception != null and not perception.evidence_observed.is_connected(_on_evidence):
		perception.evidence_observed.connect(_on_evidence)
	if suspicion != null and not suspicion.hotspot_resolved.is_connected(_on_hotspot_resolved):
		suspicion.hotspot_resolved.connect(_on_hotspot_resolved)
	var investigating := hfsm.state_of(CreatureState.State.INVESTIGATING)
	if (
		investigating != null
		and not investigating.tree.running_leaf_changed.is_connected(_on_action)
	):
		for id: int in [
			CreatureState.State.UNALERTED,
			CreatureState.State.INVESTIGATING,
			CreatureState.State.HUNTING,
			CreatureState.State.RETREATING,
		]:
			hfsm.state_of(id).tree.running_leaf_changed.connect(_on_action)


## Explicit wiring wins; the group is the fallback. Positions are copied out once -- the HFSM
## never holds a node, so the whole nest system is a PackedVector3Array to it.
func _load_nests() -> void:
	if not is_inside_tree() and nests.is_empty():
		return
	_nests_loaded = true
	var found: Array[Node3D] = nests
	if found.is_empty() and is_inside_tree():
		for node: Node in get_tree().get_nodes_in_group(CreatureNest.GROUP):
			var marker := node as Node3D
			if marker != null:
				found.append(marker)
	var positions := PackedVector3Array()
	for marker: Node3D in found:
		positions.append(marker.global_position if marker.is_inside_tree() else marker.position)
	set_nest_positions(positions)


## Nests as data. Public so a test, a tool or a level script can supply them without a scene.
func set_nest_positions(positions: PackedVector3Array) -> void:
	_nests_loaded = true
	var unalerted := hfsm.state_of(CreatureState.State.UNALERTED) as UnalertedState
	if unalerted != null:
		unalerted.memory.nests.remember(positions, config)


func _on_evidence(evidence: SuspicionEvidence) -> void:
	if evidence.sense != SuspicionEvidence.Sense.VISION:
		return
	# Filtered to the arbitrated target when there is one, so `has_visual_contact` means
	# contact with WHO the Director is pacing rather than with anybody at all.
	var target: Node = directive.target
	if target != null and evidence.source_player != target:
		return
	_last_vision_at = clock


func _on_hotspot_resolved(hotspot_id: int) -> void:
	var investigating := hfsm.state_of(CreatureState.State.INVESTIGATING) as InvestigatingState
	if investigating != null:
		investigating.on_hotspot_resolved(hotspot_id)


func _on_state_changed(
	from: CreatureState.State, to: CreatureState.State, reason: StringName
) -> void:
	state_changed.emit(from, to, reason)


func _on_action(_from: StringName, to: StringName) -> void:
	action_changed.emit(to)
