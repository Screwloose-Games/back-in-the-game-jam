class_name HuntingState
extends BehaviorState

## Pursue a credible PLAYER (fsm.md; behavior.md section 26).
##
## ```text
## Selector
## |-- Cooldown[Sequence[can_attack, attack]]
## |-- Sequence[has_target_estimate, chase_target]
## |-- Sequence[target_beyond_reach, lurk_at_tunnel_mouth]
## +-- Cooldown[search_area]
## ```
##
## THE ORDER IS THE PRIORITY CLAIM: bite beats pursue beats wait beats search.
##
## HUNT SUSTAIN IS WHAT MAKES HUNTING A COMMITMENT, and it is the reason this state carries
## memory at all. It is lost only when BOTH hold: no candidate above
## `hunt_sustain_threshold` for a continuous `hunt_sustain_grace_s`, AND no unresolved
## suspicion within `hunt_sustain_radius` of the last credible target position. Losing sight
## of the player does not end a hunt -- the alien searches where it last believed you were.
##
## `refresh` RUNS BEFORE THE TREE, EVERY TICK, and here it does three jobs a condition could
## not. It reads the estimate off the credible hotspot; it ages that estimate on SUSPICION's
## clock; and it works out whether the creature's own graph can actually reach it. All three
## are questions with answers that move, and a condition that recomputed one would either be
## side-effecting or would have to command navigation to find out -- and the reactive re-tick
## survives neither.
##
## THE REACH LATCH IS ALSO WHERE THIS DEVIATES FROM fsm.md. The spec puts chase above lurk and
## gives chase no failure clause for a route that stops short, so read literally the lurk
## branch is unreachable exactly when it has somewhere to lurk. Making chase fail on PARTIAL
## instead would hand the goal back and forth between the two leaves every tick, and
## BehaviorGoal re-issues unconditionally on a change of owner -- which nulls the route and
## resets navigation's stuck watchdog every frame. Deciding it once, up here, costs one route
## query on the ticks where the estimate has moved and nothing at all on the rest.

var memory: HuntingMemory = null

## Behavior-clock time at which the candidate first fell below the sustain threshold, or
## -1.0 while it is above. The grace is measured from here.
var _starved_since: float = -1.0
var _bite_gate: BtCooldown = null
var _search_gate: BtCooldown = null


func _init() -> void:
	memory = HuntingMemory.new()
	var bite: Array[BtNode] = [BtCanAttack.new(memory), BtAttack.new(memory)]
	# The rate limit is a decorator rather than a timer inside `attack`, so `can_attack` and
	# the encounter report can go on meaning the same thing: the target is IN REACH. Folding
	# the cooldown into the condition would leave `attack_window_open` true for the one frame
	# a strike fires, and the Director would price a whole encounter at roughly no pressure.
	_bite_gate = BtCooldown.new(&"bite_gate", 1.0, BtSequence.new(&"bite", bite))
	_search_gate = BtCooldown.new(&"search_gate", 1.0, BtSearchArea.new(memory))
	var pursue: Array[BtNode] = [BtHasTargetEstimate.new(memory), BtChaseTarget.new(memory)]
	var wait: Array[BtNode] = [BtTargetBeyondReach.new(memory), BtLurkAtTunnelMouth.new(memory)]
	var root: Array[BtNode] = [
		_bite_gate,
		BtSequence.new(&"pursue", pursue),
		BtSequence.new(&"wait", wait),
		_search_gate,
	]
	tree = BehaviorTree.new(BtSelector.new(&"hunting", root))


func state_id() -> CreatureState.State:
	return CreatureState.State.HUNTING


func enter(ctx, _from: BehaviorState) -> void:
	_starved_since = -1.0
	memory.forget()
	_apply_cooldowns(ctx)
	refresh(ctx)


func refresh(ctx) -> void:
	if ctx.suspicion == null:
		return
	var hotspot: SuspicionHotspot = _credible_hotspot(ctx)
	if hotspot != null:
		memory.last_credible_target_position = hotspot.position
		memory.has_target_estimate = true
	_track_starvation(ctx)
	_track_estimate_age(ctx)
	memory.beyond_reach = _probe_reach(ctx)
	memory.attack_window_open = _attack_window(ctx)


func next_transition(ctx, _time_in_state: float) -> BehaviorTransition:
	# The latch, not the live field. director.md has the HFSM consume force_disengage "at its
	# next transition check", and min_dwell_s routinely means that check is several ticks
	# after the Director asked.
	if ctx.hfsm != null and ctx.hfsm.disengage_pending():
		ctx.hfsm.consume_disengage()
		return BehaviorTransition.make(CreatureState.State.RETREATING, &"director", 1.0, 1.0)
	if _sustain_lost(ctx):
		return BehaviorTransition.make(
			CreatureState.State.RETREATING,
			&"lost",
			ctx.clock - _starved_since,
			ctx.config.hunt_sustain_grace_s
		)
	return null


## The hotspot the creature attributes to whoever it is hunting, preferring the Director's
## arbitrated target when there is one. Falls back to the strongest lead, because an alien
## that has lost the attribution has not necessarily lost the trail.
func _credible_hotspot(ctx) -> SuspicionHotspot:
	var target: Node = ctx.directive.target if ctx.directive != null else null
	var leads: Array[SuspicionHotspot] = ctx.suspicion.get_hotspots_above(
		ctx.config.attention_floor
	)
	if target != null:
		for hotspot: SuspicionHotspot in leads:
			if hotspot.likely_source == target:
				return hotspot
	return leads[0] if not leads.is_empty() else null


func _track_starvation(ctx) -> void:
	var candidate: PlayerSuspicionCandidate = ctx.suspicion.get_best_player_candidate()
	var fed: bool = candidate != null and candidate.suspicion >= ctx.config.hunt_sustain_threshold
	if fed:
		_starved_since = -1.0
	elif _starved_since < 0.0:
		_starved_since = ctx.clock


## AGED ON SUSPICION'S CLOCK, WHICH IS NOT THIS ONE. `last_evidence_at` is stamped by
## CreatureSuspicion, whose clock starts when that node is constructed; subtracting Behavior's
## from it compiles, runs, and produces garbage whenever the two nodes were not built on the
## same frame. No candidate at all counts as stale: an attribution the creature no longer
## holds is not fresh knowledge of where anybody is.
func _track_estimate_age(ctx) -> void:
	var candidate: PlayerSuspicionCandidate = ctx.suspicion.get_best_player_candidate()
	if candidate == null:
		memory.estimate_is_stale = true
		return
	var age: float = ctx.suspicion.clock - candidate.last_evidence_at
	memory.estimate_is_stale = age > ctx.config.target_estimate_max_age_s


## Whether the graph reaches toward the estimate and stops short of it.
##
## FREE IN THE STEADY STATE. While chase or lurk holds a goal at the estimate the live route
## has already answered the question, so nothing is searched twice; the one-off `plan_route`
## runs only on the ticks where nobody is committed there -- and it is a query that does not
## disturb the route navigation is actually following. A goal that has been issued but whose
## route has not come back yet reads as "not beyond reach" for one tick, which is correct:
## one more stride toward a gap it cannot enter is what the alien would do anyway.
func _probe_reach(ctx) -> bool:
	if not memory.has_target_estimate or ctx.navigation == null:
		return false
	var estimate: Vector3 = memory.last_credible_target_position
	var committed: bool = (
		ctx.goal != null
		and ctx.goal.has_goal()
		and ctx.goal.committed().distance_to(estimate) <= ctx.config.goal_refresh_m
	)
	if committed:
		return ctx.goal.is_partial()
	var route: NavRoute = ctx.navigation.plan_route(ctx.body_position, estimate)
	return route != null and route.status == NavRoute.Status.PARTIAL


## MEASURED TO THE ESTIMATE, NEVER TO A PLAYER. Behavior decides from belief, so an alien
## with a stale idea of where you are swings at where it thinks you are -- which is the
## behaviour the design wants and the only one the module is allowed to produce.
func _attack_window(ctx) -> bool:
	if not memory.has_target_estimate or memory.estimate_is_stale:
		return false
	var reach: float = ctx.body_position.distance_to(memory.last_credible_target_position)
	return reach <= ctx.config.attack_range_m


## BOTH conditions, and the `and` is the whole design. Either one alone ends a hunt the
## moment the player breaks line of sight, which is precisely what behavior.md section 26
## says must not happen.
func _sustain_lost(ctx) -> bool:
	if _starved_since < 0.0:
		return false
	if ctx.clock - _starved_since < ctx.config.hunt_sustain_grace_s:
		return false
	if not memory.has_target_estimate:
		return true
	var nearby: float = ctx.suspicion.get_suspicion_near(
		memory.last_credible_target_position, ctx.config.hunt_sustain_radius
	)
	return nearby <= ctx.config.attention_floor


## Both gates are config numbers, but BtCooldown takes its interval at construction and the
## state is built before it has ever seen a config. Aborting them here is what BtCooldown's own
## `abort` is for: a new encounter must not inherit the last one's timers, or the first strike
## of a hunt silently waits out a cooldown armed minutes ago.
func _apply_cooldowns(ctx) -> void:
	_bite_gate.abort(ctx)
	_search_gate.abort(ctx)
	if ctx.config != null:
		_bite_gate.seconds = ctx.config.attack_cooldown_s
		_search_gate.seconds = ctx.config.search_cooldown_s
