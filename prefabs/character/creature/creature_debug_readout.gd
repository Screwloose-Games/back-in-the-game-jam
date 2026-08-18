class_name CreatureDebugReadout
extends Node3D

## What the alien is doing, why, and whether it is actually getting anywhere -- floating
## over its head.
##
##     hunting  12.4s  3/min
##     <- investigating (candidate 0.31 v 0.25)
##
##     chase_target
##     goal cmd 2.0/s  owner flip 0.0/s  churn 0.4m/s
##
##     route COMPLETE #a3f1  idx 3/9 ^3  2.1m
##     wander 4.8x  |v| 5.9  closing -0.1
##     replan 2.1/s  reroll 1.4/s  trips 0 (net)
##     mode TUNNEL_SWIM (advisory)  short 0.0m
##     ORBIT  fast but not closing on the anchor
##
## EVERY RATE ON IT IS A RATE ON PURPOSE. A creature going in circles holds a perfectly
## ordinary state, a perfectly ordinary action and a perfectly ordinary route; what is wrong
## is how often it changes its mind, and no snapshot of a level shows that. The fingerprint
## `#a3f1` is a hash of the route's graph node ids -- two ways round a loop cost nearly the
## same, so a chooser flipping between them shows up here as two values alternating and
## nowhere else at all.
##
## THREE Label3Ds RATHER THAN ONE. Label3D has one `font_size` and one `modulate` per node
## and no BBCode, so one label would be one size in one colour. The state colour read across
## a chamber is the fastest answer in the scene -- red is hunting before any text resolves.
##
## TOP-LEVEL, FOLLOWING THE BODY'S POSITION AND NOTHING ELSE. CrawlerBody writes a full
## orientation quaternion into its transform every physics tick, so a normally-parented
## label rides the roll and ends up buried in the rock the creature is crawling on. `Marker`
## in this prefab is top_level for the same reason. Billboarding already handles facing.
##
## `trips` IS PRINTED "(net)" BECAUSE IT LIES BY DESIGN. NavProgressMonitor measures
## straight-line displacement over its window, so a body orbiting at 6 m/s covers 12 m of
## path and trips nothing -- and `set_goal` resets the window anyway, so under goal churn it
## never completes. `wander` on the line above is the honest number and the two are printed
## together so the disagreement is visible rather than confusing.
##
## `mode` IS TAGGED "(advisory)" AND THAT TAG IS LOAD-BEARING. Nothing in the asteroid level
## listens to `motion_planned`: CreatureAgent drives the body through the leash marker
## alone, so the local planner's mode, stalls, aborts, wiggle and leaps are all computed
## each tick and discarded. Printing the mode untagged sends someone tuning a system that is
## not connected to anything.
##
## IT LIVES UNDER prefabs/ RATHER THAN gameplay/creature/behavior/debug/ because
## verify_behavior_static.gd bans the token `global_position` throughout that module, and
## reading the body's position is this node's whole job. It is a composition-layer script,
## like creature_agent.gd beside it.

## Metres above the body: clear of the tentacle reach, under a 6 m tunnel ceiling.
const HEIGHT_M: float = 5.0
## Matched to NavigationConfig.progress_window so `wander` and `trips` describe the same two
## seconds, which is what makes their disagreement mean something.
const WANDER_WINDOW_S: float = 2.0
const RATE_BUCKET_S: float = 1.0
const ATTACK_FLASH_S: float = 0.8
## Below this the creature is not really moving and `wander` is noise over a tiny divisor.
const WANDER_FLOOR_M: float = 0.05

## Alarm thresholds, named so nobody has to remember what normal looks like.
const ALARM_WANDER: float = 3.0
const ALARM_MOVING_MPS: float = 1.0
const ALARM_CLOSING_MPS: float = 0.5
const ALARM_GOAL_CMD_HZ: float = 4.0
const ALARM_REPLAN_HZ: float = 4.0
const ALARM_REROLL_HZ: float = 1.0

const COLOR_UNALERTED := Color(0.60, 0.66, 0.72)
const COLOR_INVESTIGATING := Color(1.00, 0.76, 0.22)
const COLOR_HUNTING := Color(1.00, 0.32, 0.26)
const COLOR_RETREATING := Color(0.45, 0.76, 1.00)
const COLOR_ACTION := Color(0.72, 0.94, 1.00)
const COLOR_ATTACK := Color(1.00, 0.35, 0.90)
const COLOR_NAV := Color(0.82, 0.84, 0.88)
const COLOR_NAV_ALARM := Color(1.00, 0.32, 0.26)

@export var body: CrawlerBody = null
@export var behavior: CreatureBehavior = null
@export var navigation: CreatureNavigation = null
@export var state_label: Label3D = null
@export var action_label: Label3D = null
@export var nav_label: Label3D = null
## Optional, and assigned by the level rather than the prefab: the trail is a level-space
## overlay. Goal commands are forwarded to it so its magenta marks land on the right sample.
@export var trail: CreatureTrailDraw = null
## Text assignment reshapes the string and rebuilds the label's mesh. Ten a second is far
## faster than anyone reads and a fraction of the cost of doing it every frame.
@export var refresh_hz: float = 10.0
## For a scene run without the DebugMode autoload, where there is no key to press.
@export var force_visible: bool = false

var _mode: Node = null
var _elapsed: float = 0.0
var _since_refresh: float = 0.0
var _attack_until: float = -1.0
var _from_state: String = ""
var _counts: Dictionary = {}
var _rates: Dictionary = {}
var _bucket_t: float = 0.0
var _peak_index: int = 0
var _route_hash: int = 0
var _last_node_ids := PackedInt32Array()
var _last_goal: Vector3 = Vector3.ZERO
var _had_goal: bool = false
var _last_commands: int = 0
var _last_flips: int = 0
var _last_position: Vector3 = Vector3.ZERO
var _velocity: Vector3 = Vector3.ZERO
var _path_m: float = 0.0
var _window_origin: Vector3 = Vector3.ZERO
var _window_t: float = 0.0
var _wander: float = 1.0


func _ready() -> void:
	top_level = true
	# CreatureBehavior ticks navigation from its own _physics_process, so a sampler at the
	# default priority reads last frame's route -- and one frame is exactly the resolution
	# the goal ping-pong lives at.
	process_physics_priority = 100
	_bind()
	_connect()
	# Resolved by path and duck-typed, never as the `DebugMode` global identifier: this
	# prefab has to work dropped into a scene that has no such autoload, including a GUT
	# fixture and a headless tool.
	_mode = get_node_or_null(^"/root/DebugMode")
	if _mode != null and _mode.has_signal(&"changed"):
		_mode.connect(&"changed", _on_debug_mode_changed)
	_apply(force_visible or (_mode != null and bool(_mode.get(&"enabled"))))


func _process(delta: float) -> void:
	_elapsed += delta
	if body != null:
		global_position = body.global_position + Vector3.UP * HEIGHT_M
	_since_refresh += delta
	if _since_refresh < 1.0 / maxf(refresh_hz, 1.0):
		return
	_since_refresh = 0.0
	_refresh()


func _physics_process(delta: float) -> void:
	_sample_motion(delta)
	_sample_goal()
	_sample_route()
	_tick_rates(delta)


# ----- wiring -----


func _bind() -> void:
	if body == null:
		body = get_parent() as CrawlerBody
	if behavior == null:
		behavior = get_node_or_null(^"%Behavior") as CreatureBehavior
	if navigation == null:
		navigation = get_node_or_null(^"%Navigation") as CreatureNavigation


func _connect() -> void:
	if behavior != null:
		behavior.state_changed.connect(_on_state_changed)
		behavior.attack_landed.connect(_on_attack_landed)
	if navigation != null:
		navigation.route_changed.connect(_on_route_changed)


## Hidden costs one idle Node3D. The signal handlers stay connected either way, so the
## totals are honest the moment it comes back on.
func _apply(enabled: bool) -> void:
	visible = enabled
	set_process(enabled)
	set_physics_process(enabled)
	if not enabled:
		return
	if body != null:
		_last_position = body.global_position
		_window_origin = _last_position
	_path_m = 0.0
	_window_t = 0.0
	_since_refresh = 0.0
	if trail != null:
		trail.clear_trail()
	_refresh()


func _on_debug_mode_changed(enabled: bool) -> void:
	_apply(enabled)


func _on_state_changed(from: int, _to: int, _reason: StringName) -> void:
	_from_state = CreatureState.state_name(from)
	_bump(&"transition", 1.0)


func _on_attack_landed(_target: Node, _lethality: int) -> void:
	_attack_until = _elapsed + ATTACK_FLASH_S


## Every replan, including one that reproduces the same anchors. A "reroll" is the subset
## that changed the route -- section 35's chooser picking a different way round a loop.
func _on_route_changed(route: NavRoute) -> void:
	_bump(&"replan", 1.0)
	var ids: PackedInt32Array = route.node_ids if route != null else PackedInt32Array()
	if ids != _last_node_ids:
		_bump(&"reroll", 1.0)
	_last_node_ids = ids
	_route_hash = hash(ids)
	_peak_index = 0


# ----- sampling -----


## Velocity is differenced here rather than read from CrawlerBody.debug_state(), which
## allocates a Dictionary -- and this runs every physics tick.
func _sample_motion(delta: float) -> void:
	if body == null:
		return
	var at: Vector3 = body.global_position
	var moved: Vector3 = at - _last_position
	_last_position = at
	_velocity = moved / maxf(delta, 0.0001)
	_path_m += moved.length()
	_window_t += delta
	if _window_t < WANDER_WINDOW_S:
		return
	var net: float = _window_origin.distance_to(at)
	_wander = _path_m / maxf(net, WANDER_FLOOR_M)
	_window_origin = at
	_path_m = 0.0
	_window_t = 0.0


## The two counters no external sampler can reproduce: chase and whatever the selector falls
## through to can both command the goal inside a single frame.
func _sample_goal() -> void:
	if behavior == null or behavior.goal == null:
		return
	var goal: BehaviorGoal = behavior.goal
	var new_commands: int = goal.commands - _last_commands
	_last_commands = goal.commands
	_bump(&"cmd", float(new_commands))
	_bump(&"flip", float(goal.owner_flips - _last_flips))
	_last_flips = goal.owner_flips
	if new_commands > 0 and trail != null:
		trail.note_goal_command()
	if not goal.has_goal():
		_had_goal = false
		return
	var at: Vector3 = goal.committed()
	if _had_goal:
		_bump(&"churn", _last_goal.distance_to(at))
	_last_goal = at
	_had_goal = true


func _sample_route() -> void:
	if navigation == null or navigation.follower == null:
		return
	_peak_index = maxi(_peak_index, navigation.follower.index)


func _bump(key: StringName, amount: float) -> void:
	_counts[key] = float(_counts.get(key, 0.0)) + amount


func _tick_rates(delta: float) -> void:
	_bucket_t += delta
	if _bucket_t < RATE_BUCKET_S:
		return
	for key: StringName in _counts:
		_rates[key] = float(_counts[key]) / _bucket_t
		_counts[key] = 0.0
	_bucket_t = 0.0


func _rate(key: StringName) -> float:
	return float(_rates.get(key, 0.0))


# ----- text -----


func _refresh() -> void:
	if state_label == null or action_label == null or nav_label == null:
		return
	if behavior == null or navigation == null:
		state_label.text = "readout unbound"
		action_label.text = ""
		nav_label.text = ""
		return
	state_label.text = _state_block()
	state_label.modulate = _state_colour()
	action_label.text = _action_block()
	action_label.modulate = COLOR_ATTACK if _elapsed < _attack_until else COLOR_ACTION
	# Built once and handed to both: debug_state() allocates a Dictionary, and the alarm and
	# the block it annotates have to agree about the same tick anyway.
	var state: Dictionary = navigation.debug_state()
	var alarm: String = _alarm(state)
	nav_label.text = _nav_block(state, alarm)
	nav_label.modulate = COLOR_NAV_ALARM if alarm != "" else COLOR_NAV


func _state_block() -> String:
	var head: String = (
		"%s  %.1fs  %.0f/min"
		% [
			CreatureState.state_name(behavior.state()),
			behavior.hfsm.time_in_state,
			_rate(&"transition") * 60.0,
		]
	)
	var fired: BehaviorTransition = behavior.hfsm.last_transition
	if fired == null:
		return head
	return (
		"%s\n<- %s (%s %.2f v %.2f)"
		% [head, _from_state, fired.reason, fired.value, fired.threshold]
	)


## `attack` never appears here -- it SUCCEEDs on the tick it fires, so it is never the
## RUNNING leaf. The label flashes on attack_landed instead.
func _action_block() -> String:
	return (
		"%s\ngoal cmd %.1f/s  owner flip %.1f/s  churn %.1fm/s"
		% [behavior.running_action(), _rate(&"cmd"), _rate(&"flip"), _rate(&"churn")]
	)


func _nav_block(state: Dictionary, alarm: String) -> String:
	# "--" rather than "+0.0" with no anchor to close on: a zero that means "no answer" and a
	# zero that means "going sideways round the anchor" are the two readings this line exists
	# to tell apart.
	var closing: String = "--"
	if bool(state["has_anchor"]):
		closing = "%+.1f" % _closing(state)
	var lines: Array[String] = []
	lines.append(_route_line(state))
	lines.append("wander %.1fx  |v| %.1f  closing %s" % [_wander, _velocity.length(), closing])
	lines.append(
		(
			"replan %.1f/s  reroll %.1f/s  trips %d (net)"
			% [_rate(&"replan"), _rate(&"reroll"), int(state["trips"])]
		)
	)
	lines.append(
		(
			"mode %s (advisory)  short %.1fm"
			% [String(state["mode"]).to_upper(), float(state["shortfall"])]
		)
	)
	if alarm != "":
		lines.append(alarm)
	return "\n".join(lines)


## `distance_remaining` is INF with no usable route, and printing that verbatim reads as a
## bug rather than as "nowhere to be".
func _route_line(state: Dictionary) -> String:
	var status: String = String(state["route_status"]).to_upper()
	var remaining: float = float(state["distance_remaining"])
	var distance: String = "--" if is_inf(remaining) else "%.1fm" % remaining
	return (
		"route %s #%04x  idx %d/%d ^%d  %s"
		% [
			status,
			_route_hash & 0xFFFF,
			int(state["anchor_index"]),
			int(state["anchor_count"]),
			_peak_index,
			distance,
		]
	)


## Velocity projected onto the direction of the anchor. THE number that separates an orbit
## from an approach: an orbit is fast with closing near zero, an approach has the two equal,
## and a wedged body has both at zero.
func _closing(state: Dictionary) -> float:
	if not bool(state["has_anchor"]) or body == null:
		return 0.0
	var to_anchor: Vector3 = state["anchor"] - body.global_position
	if to_anchor.length_squared() < 0.0001:
		return 0.0
	return _velocity.dot(to_anchor.normalized())


## Names the mechanism rather than just going red, because "something is wrong" is what the
## person reading this already knew.
func _alarm(state: Dictionary) -> String:
	var speed: float = _velocity.length()
	if _wander > ALARM_WANDER and speed > ALARM_MOVING_MPS:
		if bool(state["has_anchor"]) and absf(_closing(state)) < ALARM_CLOSING_MPS:
			return "ORBIT  fast but not closing on the anchor"
		return "WANDERING  covering ground without making any"
	if _rate(&"cmd") > ALARM_GOAL_CMD_HZ:
		return "GOAL CHURN  the tree keeps re-commanding the goal"
	if _rate(&"reroll") > ALARM_REROLL_HZ:
		return "ROUTE REROLL  the chooser keeps picking a different way"
	if _rate(&"replan") > ALARM_REPLAN_HZ:
		return "REPLAN STORM  the anchor index never advances"
	return ""


func _state_colour() -> Color:
	match behavior.state():
		CreatureState.State.INVESTIGATING:
			return COLOR_INVESTIGATING
		CreatureState.State.HUNTING:
			return COLOR_HUNTING
		CreatureState.State.RETREATING:
			return COLOR_RETREATING
	return COLOR_UNALERTED
