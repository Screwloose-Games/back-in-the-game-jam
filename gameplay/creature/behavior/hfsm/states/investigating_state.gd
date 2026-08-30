class_name InvestigatingState
extends BehaviorState

## Resolve uncertainty about a PLACE (fsm.md; behavior.md section 25).
##
## The alien has a hotspot worth walking to. It travels, searches, and lets Perception's
## disconfirmations resolve or fail to resolve the belief. It does not have a target; it has
## a location.
##
## ```text
## Selector
## |-- Sequence
## |   |-- Condition  arrived_at_goal
## |   +-- Cooldown   search_area
## +-- Action         investigate_location
## ```
##
## `refresh` RUNS BEFORE THE TREE, EVERY TICK, and it is the load-bearing part of this
## state. The best unresolved location MOVES as searching disconfirms sub-regions -- that
## motion is the whole of suspicion.md's spatial resolution, and it is what lets the alien
## work its way into a hotspot rather than standing on the first point it picked. Doing that
## work inside a condition would make the condition side-effecting, which the reactive
## re-tick cannot survive; doing it inside the action would leave the condition testing a
## stale point.
##
## IT ALSO RE-LEADS. behavior.md section 25's first branch is "current hotspot resolved? ->
## select another hotspot", so a lead dying mid-approach picks the next one rather than
## dropping straight back to UNALERTED. Only an empty board ends the state.
##
## AND IT GIVES UP. `_note_progress` watches whether the approach is working at all; once it
## has not been for `give_up_s`, the `futile` row hands over to RECONSIDERING, which writes the
## lead off. Without it a lead the creature cannot physically reach holds the state for the
## whole of `investigate_timeout_s` and is then re-selected on the next tick, because
## `_take_lead` takes the strongest board entry and has no memory of having just failed on it.

var memory: InvestigatingMemory = null

## Behavior-clock time at which the approach stopped working, or -1.0 while it is working.
## Shaped exactly like HuntingState._starved_since, and read by the same kind of row.
var _futile_since: float = -1.0
## Closest the creature has come to the CURRENT lead. The watermark, not the last sample:
## measuring against the previous tick calls a single slow frame failure, and measuring
## against the start calls a route that legitimately doubles back failure.
var _closest: float = INF
## The last thing a LIVE route said about this lead: could it actually get there?
##
## LATCHED, BECAUSE THE ROUTE IS NOT THERE WHEN YOU LOOK. `investigate_location` releases the
## goal the moment `search_area` becomes the running leaf, and releasing a goal clears the
## route -- so for most of the ticks the creature spends at a wall there is no route to ask,
## and a check that read the route directly would find nothing and reset itself forever. Which
## is exactly the loop this file is about, arrived at from the other side.
var _lead_reachable: bool = true
## Where the lead was when the give-up clock last restarted, and whether there is one.
##
## A PLACE, NOT AN ID, and the difference is the whole reason the clock ever reaches its
## deadline. Hotspot identity is carried by shared contributing evidence, so a lead being
## searched -- which prunes evidence and adds disconfirmations -- is renumbered every few
## seconds while sitting still. Restarting on the id restarts on the bookkeeping; measured,
## it renumbered twice inside eight seconds and the 5 s deadline was never once reached.
var _lead_anchor: Vector3 = Vector3.ZERO
var _has_lead_anchor: bool = false
var _search_gate: BtCooldown = null


func _init() -> void:
	memory = InvestigatingMemory.new()
	_search_gate = BtCooldown.new(&"search_gate", 1.0, BtSearchArea.new(memory))
	var branch: Array[BtNode] = [BtArrivedAtGoal.new(memory), _search_gate]
	var root: Array[BtNode] = [
		BtSequence.new(&"search_here", branch),
		BtInvestigateLocation.new(memory),
	]
	tree = BehaviorTree.new(BtSelector.new(&"investigating", root))


func state_id() -> CreatureState.State:
	return CreatureState.State.INVESTIGATING


func enter(ctx, _from: BehaviorState) -> void:
	memory.forget()
	_forget_progress()
	_apply_cooldown(ctx)
	refresh(ctx)


## Drops a lead the moment Suspicion says it is gone, rather than one hotspot rebuild later.
## Wired by CreatureBehavior; the state does not reach for the signal itself.
func on_hotspot_resolved(hotspot_id: int) -> void:
	if hotspot_id == memory.hotspot_id:
		memory.forget()


func refresh(ctx) -> void:
	if ctx.suspicion == null:
		memory.forget()
		_forget_progress()
		return
	if ctx.suspicion.get_hotspot(memory.hotspot_id) == null and not _take_lead(ctx):
		memory.forget()
		_forget_progress()
		return
	# For a LIVE hotspot this always answers with a real point -- the sampler falls back to
	# the hotspot's own position -- so the Vector3.ZERO that a dead id returns is exactly
	# what the liveness check above has already excluded.
	memory.desired_location = ctx.suspicion.get_best_unresolved_location(memory.hotspot_id)
	memory.has_location = true
	_track_futility(ctx, ctx.suspicion.get_hotspot(memory.hotspot_id))


func next_transition(ctx, time_in_state: float) -> BehaviorTransition:
	var shift: float = 0.0
	if ctx.directive != null:
		shift = ctx.config.threshold_shift(ctx.directive.escalation_bias)
	var threshold: float = ctx.config.hunt_threshold - shift
	var hunt: BehaviorTransition = hunt_transition(ctx, threshold, &"candidate")
	if hunt != null:
		return hunt
	# ABOVE THE TIMEOUT ROW, because 5 s of getting nowhere is a better answer than 45 s of it,
	# and because only this row writes the lead off -- dropping out on `timeout` leaves it top
	# of the board and UNALERTED walks straight back in on the next tick.
	if _futile_since >= 0.0 and ctx.clock - _futile_since >= ctx.config.give_up_s:
		return BehaviorTransition.make(
			CreatureState.State.RECONSIDERING,
			&"futile",
			ctx.clock - _futile_since,
			ctx.config.give_up_s
		)
	if time_in_state > ctx.config.investigate_timeout_s:
		return BehaviorTransition.make(
			CreatureState.State.UNALERTED,
			&"timeout",
			time_in_state,
			ctx.config.investigate_timeout_s
		)
	var leads: Array[SuspicionHotspot] = ctx.suspicion.get_hotspots_above(
		ctx.config.attention_floor
	)
	if leads.is_empty():
		return BehaviorTransition.make(
			CreatureState.State.UNALERTED, &"nothing_left", 0.0, ctx.config.attention_floor
		)
	return null


## The strongest hotspot still worth attention. `get_hotspots_above` already sorts
## descending, so the first entry is the lead.
func _take_lead(ctx) -> bool:
	var leads: Array[SuspicionHotspot] = ctx.suspicion.get_hotspots_above(
		ctx.config.attention_floor
	)
	if leads.is_empty():
		return false
	memory.hotspot_id = leads[0].id
	return true


## Whether the creature is getting anywhere, and for how long it has not been.
func _track_futility(ctx, hotspot: SuspicionHotspot) -> void:
	if hotspot == null or ctx.navigation == null:
		# Every clause below is a question about a route. With no navigation wired there is no
		# route and no notion of reaching anywhere, so the honest answer is to say nothing
		# rather than to give up on a creature that was never able to travel in the first place.
		_forget_progress()
		return
	# A new lead is a new question, and carrying the old watermark into it would give up on a
	# fresh approach almost immediately. SCALED TO THE HOTSPOT rather than to a fixed distance,
	# because a hotspot centre wanders inside its own extent: this one is capped at
	# `hotspot_max_radius` (14 m) by repeated noise, and its centre was measured jumping 4 m
	# between rebuilds while the creature stood still. Against a fixed 3 m that reset the clock
	# every few seconds and the deadline was never reached. Inside the hotspot's own radius is
	# the same place; outside it is somewhere else.
	var moved: float = maxf(hotspot.radius, ctx.config.arrive_distance)
	if not _has_lead_anchor or hotspot.position.distance_to(_lead_anchor) > moved:
		_forget_progress()
	_lead_anchor = hotspot.position
	_has_lead_anchor = true
	_note_route(ctx)
	if _note_progress(ctx, hotspot):
		_futile_since = -1.0
		return
	if _futile_since < 0.0:
		_futile_since = ctx.clock


## Records what a live route says about the current lead, and keeps saying it once the route
## is gone. See `_lead_reachable`.
##
## A PARTIAL ROUTE IS THE FAILURE NOTHING ELSE REPORTS. It is deliberately not an error -- the
## creature reaches the far end of what it can reach and acts from there -- so `route.status`
## reads PARTIAL, `is_usable` reads true, and `is_arrived` reads TRUE at the near face of a
## wall. The shortfall is how far short it stopped, and it is the only number that separates
## "nearly there" from "cannot get there at all".
func _note_route(ctx) -> void:
	if ctx.navigation == null or ctx.navigation.route == null:
		return
	if not ctx.goal.has_goal():
		# No goal means the route belongs to something else, or to nothing.
		return
	if ctx.goal.is_unreachable():
		_lead_reachable = false
		return
	_lead_reachable = ctx.navigation.route_shortfall() <= ctx.config.arrive_distance


## True while the approach is still worth continuing. Updates the watermark as it goes, which
## is why it is `note_` rather than `is_` -- the same shape, and for the same reason, as
## WiggleController.note_progress.
##
## TWO WAYS TO BE GETTING NOWHERE. The route said it cannot get there, which is the case this
## whole row exists for; or the route says it can and the body is not closing anyway, which is
## the wedge navigation's own watchdog also watches for and which no route status describes.
##
## Distance is EUCLIDEAN and measured to the hotspot rather than to `desired_location`, and
## both halves of that matter. Route distance is unavailable for most of these ticks -- the
## goal is released whenever `search_area` holds the tick. And the best unresolved location
## moves around inside the hotspot by design, several metres at a time, so a watermark against
## it would be reset by the sampler rather than by the creature getting anywhere.
func _note_progress(ctx, hotspot: SuspicionHotspot) -> bool:
	# FIRST, AND THE ORDER IS THE WHOLE FUNCTION. A route that cannot get there is not an
	# approach going slowly, and no arrival test may override it -- a hotspot grows to
	# `hotspot_max_radius` (14 m) on repeated noise, so "inside the hotspot" would call a
	# creature standing at a wall ten metres short of it arrived, every tick, forever.
	if not _lead_reachable:
		return false
	var to_lead: float = ctx.body_position.distance_to(hotspot.position)
	# Reachable and inside it: at the place. Standing in a hotspot sweeping it is the opposite
	# of futile, and it is exactly where closing on it is supposed to stop. Safe to be generous
	# here only because the clause above has already established the creature could get there.
	if to_lead <= maxf(hotspot.radius, ctx.config.arrive_distance):
		return true
	# The deadband is `goal_refresh_m` for the reason BehaviorGoal uses it: below that, closing
	# and not closing are indistinguishable from the hotspot's own drift.
	if to_lead < _closest - ctx.config.goal_refresh_m:
		_closest = to_lead
		return true
	_closest = minf(_closest, to_lead)
	return false


func _forget_progress() -> void:
	_futile_since = -1.0
	_closest = INF
	_lead_reachable = true
	_has_lead_anchor = false


## The cooldown gating `search_area` is a config number, but BtCooldown takes it at
## construction and the state is built before it has ever seen a config.
func _apply_cooldown(ctx) -> void:
	if ctx.config != null:
		_search_gate.seconds = ctx.config.search_cooldown_s
