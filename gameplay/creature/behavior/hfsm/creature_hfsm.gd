class_name CreatureHfsm
extends RefCounted

## The four modes and the rules for moving between them (fsm.md, "Transitions").
##
## TRANSITIONS ARE EVALUATED ONCE PER TICK, BEFORE THE TREE TICKS, IN TABLE ORDER, FIRST
## MATCH WINS. A change aborts the outgoing tree before the incoming one runs, so no leaf
## ever holds a goal across a mode change.
##
## `min_dwell_s` IS A PRE-GUARD ON EVERY ROW, NOT A ROW. Nothing transitions out of a state
## until it has been in it that long. It is easy to omit while implementing "the transition
## table" and it is the whole of what stops an alien on a threshold boundary flickering.
##
## `force_disengage` IS LATCHED HERE. director.md has the HFSM consume it "at its next
## transition check", which is not the same as reading it: with min_dwell_s blocking that
## check, a directive rebuilt each tick would drop the disengage entirely and the encounter
## would never end. Observed on any tick, consumed on the next check, cleared after.

## Carries the reason into debug and into anything watching. Every transition has one.
signal state_changed(from: CreatureState.State, to: CreatureState.State, reason: StringName)

var current: CreatureState.State = CreatureState.State.UNALERTED
var time_in_state: float = 0.0
## The last row that fired, kept for the debug line. Null until something transitions.
var last_transition: BehaviorTransition = null

var _states: Dictionary = {}
var _disengage_latched: bool = false


func _init(states: Dictionary = {}) -> void:
	_states = states


func add_state(state: BehaviorState) -> void:
	_states[state.state_id()] = state


func state_of(id: CreatureState.State) -> BehaviorState:
	return _states.get(id) as BehaviorState


func active_state() -> BehaviorState:
	return state_of(current)


## Step 1 of the tick contract. Injected delta, never a wall clock.
func advance_clock(delta: float) -> void:
	time_in_state += delta


## True when the directive has asked for a disengage and it has not been acted on yet.
func disengage_pending() -> bool:
	return _disengage_latched


## Step 5. Returns true when the state changed, which is also when the outgoing tree was
## aborted.
func evaluate_transitions(ctx) -> bool:
	_observe_directive(ctx)
	var state: BehaviorState = active_state()
	if state == null:
		return false
	if time_in_state < _min_dwell(ctx):
		return false
	var transition: BehaviorTransition = state.next_transition(ctx, time_in_state)
	if transition == null:
		return false
	_change_to(transition, ctx)
	return true


## Step 7. The tree only ever runs after transitions have settled.
func tick(ctx) -> void:
	var state: BehaviorState = active_state()
	if state != null:
		state.tick(ctx)


func running_action() -> StringName:
	var state: BehaviorState = active_state()
	return state.running_action() if state != null else &"none"


## Puts the machine in a state without a transition, for construction and for tests. Emits
## nothing: there is no reason to carry, and a synthetic one in the log would be a lie.
func reset_to(id: CreatureState.State, ctx) -> void:
	var previous: BehaviorState = active_state()
	if previous != null:
		previous.exit(ctx)
	current = id
	time_in_state = 0.0
	last_transition = null
	_disengage_latched = false
	var state: BehaviorState = active_state()
	if state != null:
		state.enter(ctx, previous)


## One line answering "why is it doing that": mode, how long, action, and the value that put
## it here.
func describe() -> String:
	var line: String = (
		"%s %.1fs %s" % [CreatureState.state_name(current), time_in_state, running_action()]
	)
	if last_transition != null:
		line += " <- " + last_transition.describe()
	return line


## Latched on observation, never on the check. See the class docstring.
func _observe_directive(ctx) -> void:
	if ctx.directive != null and ctx.directive.force_disengage:
		_disengage_latched = true


## Consumed by HuntingState the moment it acts on the latch.
func consume_disengage() -> void:
	_disengage_latched = false


func _min_dwell(ctx) -> float:
	return ctx.config.min_dwell_s if ctx.config != null else 0.0


func _change_to(transition: BehaviorTransition, ctx) -> void:
	var from: CreatureState.State = current
	var previous: BehaviorState = active_state()
	if previous != null:
		previous.exit(ctx)
	current = transition.to
	time_in_state = 0.0
	last_transition = transition
	var state: BehaviorState = active_state()
	if state != null:
		state.enter(ctx, previous)
	state_changed.emit(from, current, transition.reason)
