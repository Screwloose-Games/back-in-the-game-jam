class_name BehaviorSandbox
extends Node3D

## The suspicion sandbox, with a creature that decides bolted on top of it.
##
## It instantiates `suspicion_sandbox.tscn` WHOLE -- which instantiates perception's in turn
## -- and adds the two things the belief layer does not have: somewhere to walk, and
## something that chooses where. The room, the player, the creature and both overlays all
## come from underneath. That is the same bargain suspicion's sandbox struck with
## perception's, taken one layer further: if Behavior ever needs either inner sandbox
## changed to accommodate it, the coupling has grown and this file stops building.
##
## It exists because the two things worth checking here cannot be asserted. Nest wandering
## and the INVESTIGATING re-aim are both TIMING properties, and both failure modes are an
## alien that still moves, still decides, and still passes every test in `tests/`:
##
##   THE ALIEN MUST LEAVE A NEST AFTER ITS DWELL AND PICK A DIFFERENT ONE. If it settles in,
##   `at_nest` has gone back to asking about proximity instead of intent -- the dwell ends,
##   the creature is still standing in the nest, the idle branch wins again and re-arms its
##   own timer. The symptom is an alien you always know the location of.
##
##   THE GOAL MARKER MUST MOVE AS THE CREATURE SEARCHES. The white spike is the best
##   unresolved location; the amber bar is where navigation was actually sent. If the alien
##   arrives, searches, and searches the same point until `timeout` shows up in the
##   transition log, `arrived_at_goal` has lost its first clause and the hotspot will never
##   resolve. It reads as a bug in disconfirmation when it is a bug in the tree.
##
##     WASD / QE   move the stand-in player            (perception sandbox)
##     1 / 2       emit a quiet / loud noise           (perception sandbox)
##     3 / 4       request an activity / geometry scan (perception sandbox)
##     V / G       toggle vision / geometry            (perception sandbox)
##     [ / ]       lower / raise alertness manually    (perception sandbox)
##     Tab         toggle the perception overlay       (perception sandbox)
##     5           search where Suspicion says, by hand  (suspicion sandbox)
##     L           toggle the alertness feedback loop    (suspicion sandbox)
##     R           forget everything                     (suspicion sandbox)
##     Y           toggle the belief overlay             (suspicion sandbox)
##
##     6           force UNALERTED, without a transition reason
##     7           plant a nest where the player is standing
##     8           put the creature and its nests back the way they started
##     B           toggle the behavior panel and the goal marker
##
## KEY 6 REACHES THE HFSM DIRECTLY, and there is no other way it could. There is no public
## `set_state` on the facade -- `test_behavior_invariants.gd` asserts its absence, because a
## second way to change state makes the transition table decorative -- so this calls
## `reset_to`, which is what the GUT fixtures do too. It emits no `state_changed`, on purpose:
## a synthetic reason in the transition log would be a lie.
##
## THIS ROOM HAS NO GAP THE ALIEN CANNOT FIT THROUGH, so an escalation here reads as chase,
## bite and walk-away and never as a tunnel-mouth lurk. Every edge across the 3 m doorway comes
## back NORMAL_VOLUME, which is the point of the doorway. The lurk beat lives in
## `encounter_sandbox.tscn`, which builds its own cave for exactly that reason rather than
## widening this one -- see the bargain three paragraphs up.
##
## KEY L IS WORTH PRESSING ONCE, TO WATCH IT GO WRONG. `feedback_alertness` starts FALSE
## here. Suspicion's sandbox writes `set_alertness_context(get_overall_suspicion())` every
## frame and Behavior publishes a per-state value at step 6 of the tick contract; with both
## on, the last writer of the frame wins and which one that is depends on node order. That is
## the fight `perception/README.md` describes, and the alertness readout is where it shows.

const INNER_SANDBOX: String = "res://gameplay/creature/suspicion/sandbox/suspicion_sandbox.tscn"
## The inner room is 24 x 6 x 24 centred on the origin, with its floor slab topping out at
## y = 0. A metre of slack below and two above so the bake sees the floor and the ceiling
## rather than ending flush with them.
const BAKE_REGION := AABB(Vector3(-12.0, -1.0, -12.0), Vector3(24.0, 8.0, 24.0))
## TWO PER WING, which is the whole point of putting them here. The divider runs down x = 0
## with a 3 m doorway at z = 0, so a cross-wing choice has to route through the doorway and a
## same-wing choice does not -- and the difference is visible from the camera without
## reading a single number.
const NEST_POSITIONS: Array[Vector3] = [
	Vector3(-8.0, 2.0, -8.0),
	Vector3(-8.0, 2.0, 8.0),
	Vector3(8.0, 2.0, -8.0),
	Vector3(8.0, 2.0, 8.0),
]
## Where the perception sandbox puts its creature, and where key 8 puts it back.
const START := Vector3(-8.0, 2.0, 0.0)
## Metres per second the stand-in body walks. Slow enough to read a decision being made,
## fast enough that a cross-wing trip is not a coffee break.
const BODY_SPEED: float = 4.0
const COLOR_NEST := Color(0.30, 0.85, 0.80, 1.0)
const COLOR_GOAL := Color(1.0, 0.55, 0.15, 1.0)

var behavior: CreatureBehavior = null

var _inner: SuspicionSandbox = null
var _perception: CreaturePerception = null
var _suspicion: CreatureSuspicion = null
var _navigation: CreatureNavigation = null
var _nests: Array[CreatureNest] = []
var _goal_marker: MeshInstance3D = null
var _panel: BehaviorDebugPanel = null
var _debug_visible: bool = true


func _ready() -> void:
	var packed: PackedScene = load(INNER_SANDBOX)
	if packed == null:
		push_error("BehaviorSandbox could not load %s" % INNER_SANDBOX)
		return
	_inner = packed.instantiate() as SuspicionSandbox
	if _inner == null:
		push_error("BehaviorSandbox loaded %s but it is not a SuspicionSandbox" % INNER_SANDBOX)
		return
	_inner.name = "SuspicionSandbox"
	add_child(_inner)

	_suspicion = _inner.suspicion
	_perception = (
		_inner.get_node_or_null("PerceptionSandbox/CreaturePerception") as CreaturePerception
	)
	if _perception == null or _suspicion == null:
		push_error("BehaviorSandbox found no creature inside the suspicion sandbox")
		return

	# BEHAVIOR OWNS ALERTNESS NOW, so the inner sandbox stops publishing it. See the class
	# docstring, and key L for what it looks like when both do.
	_inner.feedback_alertness = false

	_plant_nests()
	_build_navigation()
	_build_behavior()
	_build_debug()


## Step 9 of the tick contract, which is the motor's and belongs to nobody yet.
##
## Behavior does steps 1-8 in its own `_physics_process` and mutes the other three facades
## while it is at it; all that is left is moving the body it was handed. This walks the route
## anchors, which navigation.md is right to call a direction rather than a waypoint.
##
## IT STEERS RATHER THAN SNAPPING, and that is not decoration. The body's facing IS the eye
## transform, so a creature that pivots instantly has a vision cone that teleports -- it sees
## round a corner a frame before it could have looked round it, and the overlay shows a cone
## that was never anywhere in between. `LocomotionProfile` already owns both numbers this
## needs, so neither is invented here: `orientation_slew_rate` bounds how fast it turns, and
## `crawl_cornering_floor` is how much speed it keeps while turning, which is what stops a
## hard turn being a full-speed slide sideways.
##
## WHY THIS DOES NOT JUST CONSUME `navigation.command`, WHICH IS THE OBVIOUS QUESTION.
## Navigation plans all of this already: `SurfaceCrawlController` limits the direction by
## `crawl_turn_radius`, scales speed by `crawl_cornering_floor` and slews orientation at
## `orientation_slew_rate`, then publishes the result as `preferred_forward`. It was measured
## running here every frame -- 900 samples, none stalled, `attached` throughout. Consuming it
## was tried and is NOT a small change, for three reasons found in that order:
##
##   The loop has an input half. `NavBodyState.forward` is what the crawl controller slews
##   FROM, and only `set_body_state` updates it -- Behavior's step 8 sends position alone. A
##   motor that never reports orientation back leaves it pinned on `Vector3.FORWARD`, so the
##   controller recomputes one tick of turn from the same stale heading for ever.
##
##   Only the surface crawler slews. The wiggle, leap and tunnel controllers assign
##   `preferred_forward` straight from their heading, and every `NavMotionCommand.make` path
##   -- including hold-still -- leaves it on the class default, which is a real-looking
##   heading pointing at -Z. A motor has to bound the turn itself anyway.
##
##   And then the locomotion layer has to actually deliver the body. Wired up fully, the
##   alien crossed wings and worked its nests for about 45 seconds before dropping into
##   `wiggle` in the doorway at zero speed and wedging there permanently -- on a graph whose
##   287 edges are all NORMAL_VOLUME, so nothing about that opening needs squeezing.
##
## All three are Movement's problems, and Movement is the subsystem that does not exist yet.
## This scene is for judging DECISIONS, and an alien wedged in a doorway cannot demonstrate a
## single one of them. So the motor stays a stand-in: honest about the creature's own turn
## rate, deliberately not a locomotion layer. Whoever builds Movement should start from
## `navigation.command` and the three notes above.
func _physics_process(delta: float) -> void:
	if _navigation == null or _perception == null or not _navigation.follower.has_route():
		return
	var anchor: Vector3 = _navigation.follower.current_anchor()
	var at: Vector3 = _perception.global_position
	# Yaw only. The anchors sit on two lattice layers and there is no climb model here, so
	# height is tracked directly rather than steered toward.
	var to_anchor := Vector3(anchor.x - at.x, 0.0, anchor.z - at.z)
	if to_anchor.length() < 0.01:
		return

	var profile: LocomotionProfile = _navigation.config.locomotion_profile
	var desired: Vector3 = to_anchor.normalized()
	var forward: Vector3 = _rotate_toward(_facing(), desired, profile.orientation_slew_rate * delta)
	# A Node3D faces its own -Z, which is also where CreaturePerception looks from.
	_perception.global_rotation = Vector3(0.0, atan2(-forward.x, -forward.z), 0.0)

	# Travel along the FACING, not at the anchor, so the path arcs with the turn instead of
	# cornering. Full speed only once it is pointed the right way; `crawl_cornering_floor`
	# is the section 22 floor under that, and near zero it would stop dead to turn.
	var alignment: float = maxf(forward.dot(desired), profile.crawl_cornering_floor)
	var travel: float = BODY_SPEED * alignment * delta
	var next: Vector3 = at + forward * travel
	next.y = at.y + clampf(anchor.y - at.y, -travel, travel)
	_perception.global_position = next


## The body's current heading, flattened. Falls back to +X, which is where the perception
## sandbox points its creature, for the degenerate case of a body somehow facing straight up.
func _facing() -> Vector3:
	var forward: Vector3 = -_perception.global_transform.basis.z
	forward = Vector3(forward.x, 0.0, forward.z)
	return Vector3.RIGHT if forward.is_zero_approx() else forward.normalized()


## `from` rotated toward `to` by at most `max_radians`, both unit and horizontal.
static func _rotate_toward(from: Vector3, to: Vector3, max_radians: float) -> Vector3:
	if from.angle_to(to) <= max_radians:
		return to
	# Signed, about UP, so it turns the short way round. The unsigned angle would leave the
	# direction to be recovered from a cross product that changes sign either side of
	# straight ahead, and the alien would spin the long way home half the time.
	var direction: float = signf(from.signed_angle_to(to, Vector3.UP))
	return from.rotated(Vector3.UP, max_radians * (direction if direction != 0.0 else 1.0))


func _process(_delta: float) -> void:
	if behavior == null or _goal_marker == null:
		return
	var showing: bool = _debug_visible and behavior.goal.has_goal()
	_goal_marker.visible = showing
	if showing:
		_goal_marker.global_position = behavior.goal.committed() + Vector3.UP * 1.25


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or behavior == null:
		return
	match key.keycode:
		KEY_6:
			_force_unalerted()
		KEY_7:
			_plant_nest_at_player()
		KEY_8:
			_reset()
		KEY_B:
			_debug_visible = not _debug_visible
			_panel.visible = _debug_visible
			for nest: CreatureNest in _nests:
				nest.visible = _debug_visible


# ----- interaction -----


## The way out of a state whose tree holds still. `reset_to` exits the old state -- which
## aborts its tree and hands the navigation goal back -- and enters UNALERTED, which forgets
## whatever nest it had been walking to and chooses again. It emits no `state_changed`, on
## purpose: a synthetic reason in the transition log would be a lie.
func _force_unalerted() -> void:
	behavior.hfsm.reset_to(CreatureState.State.UNALERTED, behavior.context)
	print("[sandbox] forced unalerted")


func _plant_nest_at_player() -> void:
	var player: Node3D = _inner.get_node_or_null("PerceptionSandbox/StandIn") as Node3D
	if player == null:
		return
	_add_nest(player.global_position)
	_push_nests()
	print("[sandbox] planted nest %d at %v" % [_nests.size() - 1, player.global_position])


func _reset() -> void:
	for extra: CreatureNest in _nests.slice(NEST_POSITIONS.size()):
		extra.queue_free()
	_nests.resize(NEST_POSITIONS.size())
	_push_nests()
	_perception.global_position = START
	behavior.hfsm.reset_to(CreatureState.State.UNALERTED, behavior.context)
	print("[sandbox] reset")


## Hands the whole list over again, and drops the intent while doing it.
##
## `travel_target` is an INDEX into this list, so a list that changes underneath it leaves
## the alien walking confidently to a nest that is now somebody else. The facade's
## `set_nest_positions` is a setup call and does not have to care; a sandbox that re-plants
## nests at runtime does.
func _push_nests() -> void:
	var positions := PackedVector3Array()
	for nest: CreatureNest in _nests:
		positions.append(nest.global_position)
	behavior.set_nest_positions(positions)
	var unalerted := behavior.hfsm.state_of(CreatureState.State.UNALERTED) as UnalertedState
	if unalerted != null:
		unalerted.memory.forget_intent()


# ----- construction -----


func _plant_nests() -> void:
	for at: Vector3 in NEST_POSITIONS:
		_add_nest(at)


## Nests as markers in the level, left to be found through `CreatureNest.GROUP` rather than
## handed over in the `nests` array -- that is the path a real level takes, and the only one
## with a group scan in it worth exercising. They have to exist before the first tick:
## `_load_nests` latches after one run and never scans again.
func _add_nest(at: Vector3) -> void:
	var nest := CreatureNest.new()
	nest.name = "Nest%d" % _nests.size()
	nest.position = at

	var view := MeshInstance3D.new()
	var pad := BoxMesh.new()
	pad.size = Vector3(2.0, 0.15, 2.0)
	view.mesh = pad
	var material := StandardMaterial3D.new()
	material.albedo_color = COLOR_NEST
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	view.material_override = material
	nest.add_child(view)

	add_child(nest)
	_nests.append(nest)


func _build_navigation() -> void:
	_navigation = CreatureNavigation.new()
	_navigation.name = "CreatureNavigation"
	# Shipped defaults, for the reason navigation's own sandbox gives: a sandbox with a tuned
	# config proves only that SOME config works. The 3 m doorway clears the normal body's
	# 1.25 m at these numbers, and every edge in the room comes back NORMAL.
	_navigation.config = NavigationConfig.new()
	add_child(_navigation)

	# add_child FIRST. The probe binds the world in `_ready()`, and a bake before that samples
	# a space with nothing in it -- producing a graph that fills the room, walls included.
	var graph: NavGraph = _navigation.bake_now(BAKE_REGION)
	if graph == null:
		push_error("BehaviorSandbox could not bake a navigation graph over the room")
		return
	var stats: Dictionary = _navigation.bake_stats()
	print(
		(
			"[sandbox] baked %d nodes, %d edges (%d normal, %d wiggle)"
			% [graph.node_count(), graph.edge_count(), stats["edges_normal"], stats["edges_wiggle"]]
		)
	)


func _build_behavior() -> void:
	behavior = CreatureBehavior.new()
	behavior.name = "CreatureBehavior"
	behavior.config = BehaviorConfig.new()
	behavior.suspicion = _suspicion
	behavior.perception = _perception
	behavior.navigation = _navigation
	# THE PERCEPTION NODE IS THE BODY. It is a Node3D and measures hearing and touch from its
	# own position, so moving it moves the creature and there is no second transform to keep
	# in step. Added last: on its first tick this mutes the other three facades' own
	# `_physics_process`, and drives all nine steps itself.
	behavior.body = _perception
	add_child(behavior)

	# AND PUBLISH THE RESTING ALERTNESS NOW, not at the first tick. Perception runs its own
	# _physics_process until Behavior's first `advance()` mutes it, and the perception sandbox
	# left it on 1.0 -- one frame of that is one vision scan at full sharpness, and the player
	# starts standing in the doorway sightline. The alien opened the scene already hunting,
	# which is a legitimate thing for it to do and a useless thing for it to start doing.
	_perception.set_alertness_context(behavior.config.alertness_for(behavior.state()))


func _build_debug() -> void:
	_goal_marker = MeshInstance3D.new()
	_goal_marker.name = "GoalMarker"
	var bar := BoxMesh.new()
	bar.size = Vector3(0.3, 2.5, 0.3)
	_goal_marker.mesh = bar
	var material := StandardMaterial3D.new()
	material.albedo_color = COLOR_GOAL
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_goal_marker.material_override = material
	add_child(_goal_marker)

	var layer := CanvasLayer.new()
	add_child(layer)
	_panel = BehaviorDebugPanel.new()
	# Assigned BEFORE add_child: the panel connects `state_changed` in its own `_ready()`, and
	# a panel wired up afterwards renders every line except the transition log.
	_panel.behavior = behavior
	# Bottom left. Perception's panel owns the top left and suspicion's the top right, and a
	# third readout over either is worse than any of the three alone.
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.position = Vector2(12, -12)
	layer.add_child(_panel)
