class_name CreatureTrailDraw
extends Node3D

## Where the alien has actually been, against where it was told to go.
##
## THE OVERLAY FOR "IT IS GOING IN CIRCLES", which is a claim no still frame and no single
## number can settle. `NavigationDebugDraw` shows the route the planner chose and
## `NavigationDebugPanel` shows what it cost; neither shows the path the body took, and the
## whole class of failure here is a body that does not follow the route it holds.
##
## THE ARRIVAL RING IS THE POINT OF THE WHOLE FILE. `CreatureAgent` puts the leash marker
## exactly `leash_slack` beyond the current anchor along the body-to-anchor line, so the
## leash pulls straight at the anchor and `CrawlerBody` damps only the closing component of
## its velocity. That is a central spring with no tangential damping: a body arriving with
## sideways speed settles into an ORBIT rather than onto the anchor, and if the orbit radius
## is under `waypoint_arrival_distance` the follower reports arrival the whole time it is
## going round. A loop of trail sitting inside the arrival ring says that in one glance, and
## nothing else in the project says it at all.
##
## THE EVENT CROSSES LOCALISE THE DECISION. A replan mark and a goal-command mark are
## dropped on the sample where each happened, so on a circling creature they cluster at one
## bearing on the loop -- which turns "it keeps re-deciding" into "it re-decides HERE",
## and that is usually a specific piece of geometry.
##
## IT LIVES IN THE NAVIGATION MODULE RATHER THAN BESIDE THE CREATURE PREFAB, and that is a
## verifier decision rather than a taxonomic one: `verify_navigation_static.gd` walks this
## directory and fails any `ImmediateMesh` overlay that does not render its vertex colours
## unshaded. An overlay outside its reach can ship lit and flat white -- one undifferentiated
## tangle -- and the check that exists to catch that would keep passing.
##
## It therefore names nothing from the behaviour module. Goal commands arrive through
## `note_goal_command()`, called by whoever can see both sides.

## Eight seconds of history. Long enough to hold two or three revolutions of a tunnel loop,
## short enough that the trail does not become a scribble of the whole level.
const SAMPLES: int = 240
const SAMPLE_HZ: float = 30.0
const REPLAN_CROSS_M: float = 0.3
const GOAL_CROSS_M: float = 0.5
const MARKER_CROSS_M: float = 0.5
const RING_SEGMENTS: int = 32
const EVENT_REPLAN: int = 1
const EVENT_GOAL: int = 2

const COLOR_TRAIL_OLD := Color(0.16, 0.20, 0.30, 1.0)
const COLOR_TRAIL_NEW := Color(0.55, 0.95, 1.00, 1.0)
const COLOR_REPLAN := Color(0.98, 0.98, 0.98, 1.0)
const COLOR_GOAL_COMMAND := Color(0.95, 0.30, 0.90, 1.0)
const COLOR_LEASH := Color(1.00, 0.85, 0.30, 1.0)
const COLOR_ARRIVAL_RING := Color(0.35, 0.90, 0.45, 1.0)
const COLOR_GOAL_RING := Color(0.98, 0.62, 0.15, 1.0)

@export var body: Node3D = null
@export var navigation: CreatureNavigation = null
## The leash target `CrawlerBody` actually chases. Without this the overlay shows the route
## and the body and leaves out the only thing touching either.
@export var marker: Node3D = null
## Radius of the ring drawn at the committed goal. Pushed in rather than read, because it is
## `BehaviorConfig.arrive_distance` and this module does not name the behaviour module.
@export var goal_radius: float = 4.0
@export var draw_trail: bool = true
@export var draw_leash: bool = true
@export var draw_rings: bool = true

var _mesh: ImmediateMesh = null
var _view: MeshInstance3D = null
var _points := PackedVector3Array()
var _events := PackedByteArray()
var _pending: int = 0
var _since_sample: float = 0.0


func _ready() -> void:
	top_level = true
	_mesh = ImmediateMesh.new()
	_view = _make_view(_mesh)
	if navigation != null:
		# Fires once per _replan(), including one that produces the same anchors -- which is
		# exactly the churn a creature going in circles is made of.
		navigation.route_changed.connect(_on_route_changed)


func _process(delta: float) -> void:
	_since_sample += delta
	if _since_sample >= 1.0 / SAMPLE_HZ:
		_since_sample = 0.0
		_sample()
	_redraw()


## A goal was commanded this frame. Called from outside because `BehaviorGoal` is a
## behaviour-module type and this file may not name one.
func note_goal_command() -> void:
	_pending |= EVENT_GOAL


## Forget the history. Call when the overlay is re-shown or the level is reset, or the first
## frame draws an eight-second straight line from wherever the creature used to be.
func clear_trail() -> void:
	_points = PackedVector3Array()
	_events = PackedByteArray()
	_pending = 0
	_since_sample = 0.0


# ----- sampling -----


func _on_route_changed(_route: NavRoute) -> void:
	_pending |= EVENT_REPLAN


## Events are latched onto the NEXT sample rather than dropped. Replans arrive at up to twice
## the sample rate, and a mark that only survives if it lands on a sample tick is a mark that
## goes missing precisely when there are most of them.
func _sample() -> void:
	if body == null:
		return
	_points.append(body.global_position)
	_events.append(_pending)
	_pending = 0
	while _points.size() > SAMPLES:
		_points.remove_at(0)
		_events.remove_at(0)


# ----- drawing -----


func _redraw() -> void:
	_mesh.clear_surfaces()
	if body == null:
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	# Unconditional, and not only as a "you are here" marker: surface_end() errors on a
	# surface with no vertices, and every other block below can legitimately draw nothing.
	_cross(body.global_position, MARKER_CROSS_M, COLOR_TRAIL_NEW)
	if draw_trail:
		_draw_trail()
	if draw_leash and marker != null:
		_draw_leash()
	if draw_rings and navigation != null:
		_draw_rings()
	_mesh.surface_end()


## Oldest to newest, dim to bright. The gradient is what makes the direction of travel and
## the period of a loop readable without watching it move.
func _draw_trail() -> void:
	var count: int = _points.size()
	for step: int in range(1, count):
		var age: float = float(step) / float(maxi(count - 1, 1))
		_line(_points[step - 1], _points[step], COLOR_TRAIL_OLD.lerp(COLOR_TRAIL_NEW, age))
	for step: int in count:
		var flags: int = _events[step]
		if flags & EVENT_REPLAN:
			_cross(_points[step], REPLAN_CROSS_M, COLOR_REPLAN)
		if flags & EVENT_GOAL:
			_cross(_points[step], GOAL_CROSS_M, COLOR_GOAL_COMMAND)


## The leash is the ONLY thing that moves the body toward the route -- nothing in this level
## consumes `motion_planned` -- and nothing else draws it.
func _draw_leash() -> void:
	_line(body.global_position, marker.global_position, COLOR_LEASH)
	_cross(marker.global_position, MARKER_CROSS_M, COLOR_LEASH)


## Horizontal rings, because the question they answer is asked from above: is the loop the
## body is making smaller than the radius that counts as having arrived?
func _draw_rings() -> void:
	var state: Dictionary = navigation.debug_state()
	if bool(state["has_anchor"]) and navigation.config != null:
		_ring(state["anchor"], navigation.config.waypoint_arrival_distance, COLOR_ARRIVAL_RING)
	if bool(state["has_goal"]):
		_ring(state["goal"], goal_radius, COLOR_GOAL_RING)


# ----- primitives -----


## Copied from NavigationDebugDraw rather than shared, and the copy is what
## verify_navigation_static.gd's overlay check exists to police -- see the class docstring.
func _make_view(mesh: ImmediateMesh) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Without this every colour below renders flat white and the whole overlay becomes one
	# tangle. Not inferred by Godot, and the failure is silent.
	material.vertex_color_use_as_albedo = true
	material.disable_fog = true
	material.no_depth_test = true
	material.render_priority = 2

	var view := MeshInstance3D.new()
	view.mesh = mesh
	view.material_override = material
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The AABB comes from whatever was drawn last frame, so without this the overlay pops in
	# and out of the frustum as the trail grows.
	view.extra_cull_margin = 4096.0
	add_child(view)
	return view


func _line(from: Vector3, to: Vector3, colour: Color) -> void:
	_mesh.surface_set_color(colour)
	_mesh.surface_add_vertex(from)
	_mesh.surface_set_color(colour)
	_mesh.surface_add_vertex(to)


func _cross(at: Vector3, size: float, colour: Color) -> void:
	var span: float = maxf(size, 0.05)
	for axis: int in 3:
		var offset := Vector3.ZERO
		offset[axis] = span
		_line(at - offset, at + offset, colour)


func _ring(at: Vector3, radius: float, colour: Color) -> void:
	var previous: Vector3 = at + Vector3.RIGHT * radius
	for step: int in range(1, RING_SEGMENTS + 1):
		var angle: float = TAU * float(step) / float(RING_SEGMENTS)
		var point: Vector3 = at + Vector3(cos(angle), 0.0, sin(angle)) * radius
		_line(previous, point, colour)
		previous = point
