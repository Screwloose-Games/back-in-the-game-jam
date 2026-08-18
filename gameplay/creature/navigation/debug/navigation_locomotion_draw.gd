class_name NavigationLocomotionDraw
extends Node3D

## The section 39 overlay for phases 3-6: what the body is doing, and what the leap
## planner thought about.
##
## SEPARATE FROM NavigationDebugDraw BECAUSE THE TWO REDRAW AT DIFFERENT RATES AND FOR
## DIFFERENT REASONS. That file's graph mesh is static between bakes and can hold
## thousands of vertices; everything here changes every single tick and holds a few dozen.
## Merging them means either rebuilding the graph every frame or teaching one class two
## lifetimes, and it would put a 700-line file where gdlint's cap is 1000.
##
## THE REJECTED LEAPS ARE THE POINT, and they are the reason NavLeapCandidate carries a
## rejection enum instead of just a bool. The leap planner's answer is usually "no", so an
## overlay that draws only the accepted leap shows an alien that mysteriously chose to
## crawl across a chamber it could obviously have jumped. Drawing every candidate,
## colour-coded by WHY it lost, turns that into a glance -- and the four reasons are
## visually distinct on purpose: a wall in the way looks nothing like a leap that was
## simply not worth taking.
##
## THE TWO BODY VOLUMES ANSWER THE OTHER RECURRING QUESTION. Section 39 asks for both, and
## a squeeze that fails is almost always a squeeze whose envelope is not the size someone
## assumed. Two wire spheres at `normal_clearance()` and `min_traversal_clearance()` make
## "does the alien fit" something you look at rather than something you compute.

## Rings per wire sphere. Three great circles reads as a sphere from any angle and costs
## 3 * SPHERE_SEGMENTS lines; more turns the body volumes into solid blobs that hide the
## geometry they are being compared against.
const SPHERE_RINGS: int = 3
const SPHERE_SEGMENTS: int = 24
## How long a desired-movement arrow is, per metre per second of commanded speed.
const VELOCITY_SCALE: float = 0.25
## Length of the preferred-surface-normal stalk, in metres.
const NORMAL_LENGTH: float = 1.5

const COLOR_CRAWL := Color(0.35, 0.90, 0.45, 1.0)
const COLOR_SWIM := Color(0.35, 0.65, 0.98, 1.0)
const COLOR_WIGGLE := Color(0.98, 0.62, 0.15, 1.0)
const COLOR_LEAP := Color(0.95, 0.35, 0.95, 1.0)
const COLOR_STALLED := Color(0.98, 0.20, 0.20, 1.0)
const COLOR_NORMAL_BODY := Color(0.55, 0.80, 0.95, 0.9)
const COLOR_SQUEEZED_BODY := Color(0.95, 0.75, 0.35, 0.9)
const COLOR_SURFACE_NORMAL := Color(0.95, 0.95, 0.55, 1.0)
const COLOR_LEAP_ACCEPTED := Color(0.40, 1.00, 0.60, 1.0)
## One per NavLeapCandidate.Rejection, in enum order, so a glance names the reason.
const COLOR_REJECT_LAUNCH := Color(0.85, 0.35, 0.85, 1.0)
const COLOR_REJECT_COST := Color(0.45, 0.45, 0.55, 1.0)
const COLOR_REJECT_BLOCKED := Color(0.95, 0.30, 0.25, 1.0)
const COLOR_REJECT_NO_GRAB := Color(0.95, 0.75, 0.20, 1.0)

@export var navigation: CreatureNavigation = null
## Mode marker, desired movement, surface normal and clearance.
@export var draw_motion: bool = true
## Section 39's "normal body volume" and "squeezed body volume".
@export var draw_body_volumes: bool = true
## Every leap candidate considered last tick, accepted and rejected.
@export var draw_leaps: bool = true
## The crawl fan from section 21, scored. Off by default: nine arrows every frame is a lot
## of screen for a question you only ask while tuning the weights.
@export var draw_crawl_fan: bool = false

var _mesh: ImmediateMesh = null
var _view: MeshInstance3D = null


func _ready() -> void:
	# The overlay draws in world space; inheriting a parent's transform would move every
	# line with whatever this happens to be parented to.
	top_level = true
	_mesh = ImmediateMesh.new()
	_view = _make_view(_mesh)


func _process(_delta: float) -> void:
	_redraw()


func set_navigation(target: CreatureNavigation) -> void:
	navigation = target


# ----- drawing -----


func _redraw() -> void:
	_mesh.clear_surfaces()
	if navigation == null or navigation.config == null:
		return
	var state: NavBodyState = navigation.body_state
	if state == null:
		return

	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	if draw_body_volumes:
		_draw_body_volumes(state.position, navigation.config.clearance_profile)
	if draw_motion:
		_draw_motion(state, navigation.command)
	if draw_crawl_fan:
		_draw_crawl_fan()
	if draw_leaps:
		_draw_leaps()
	_mesh.surface_end()


## Section 39: "normal body volume" and "squeezed body volume". Both always, not whichever
## is current -- the useful comparison is between them and the hole.
func _draw_body_volumes(at: Vector3, envelope: ClearanceProfile) -> void:
	_wire_sphere(at, envelope.normal_clearance(), COLOR_NORMAL_BODY)
	_wire_sphere(at, envelope.min_traversal_clearance(), COLOR_SQUEEZED_BODY)


## Section 39: "current mode, desired movement, preferred surface normal, clearance".
func _draw_motion(state: NavBodyState, motion: NavMotionCommand) -> void:
	var colour: Color = _mode_colour(state.mode)
	if motion != null and motion.is_stalled():
		colour = COLOR_STALLED
	# A cross at the body, in the mode's colour. This is the one thing on screen that
	# answers "what is it doing" without reading the panel.
	_cross(state.position, 0.5, colour)

	if motion == null:
		return
	if motion.desired_speed > 0.0:
		_arrow(
			state.position,
			state.position + motion.desired_direction * motion.desired_speed * VELOCITY_SCALE,
			colour
		)
	if state.attached:
		_line(
			state.position,
			state.position + motion.preferred_surface_normal * NORMAL_LENGTH,
			COLOR_SURFACE_NORMAL
		)
	# Clearance as a ring in the plane the surface normal defines: a circle that shrinks as
	# the alien enters a crevice, which is the shape of the number that matters.
	if state.clearance > 0.0 and not is_inf(state.clearance):
		_ring(state.position, motion.preferred_surface_normal, state.clearance, colour)


## Section 21's scored fan. Length carries the score, so the winner is simply the longest.
func _draw_crawl_fan() -> void:
	var crawler: SurfaceCrawlController = navigation.local_planner.crawler
	for candidate: NavCrawlCandidate in crawler.last_candidates:
		var weight: float = clampf(candidate.score, 0.0, 3.0) / 3.0
		var colour: Color = COLOR_STALLED.lerp(COLOR_CRAWL, weight)
		_line(candidate.step_point, candidate.step_point + candidate.direction * weight, colour)
		_cross(candidate.step_point, 0.12, colour)


## Section 39's leap block: candidate trajectory, shape-cast volume, landing candidate and
## rejection reason.
func _draw_leaps() -> void:
	var planner: NavLeapPlanner = navigation.local_planner.leaper
	var envelope: ClearanceProfile = navigation.config.clearance_profile
	for candidate: NavLeapCandidate in planner.last_candidates:
		var colour: Color = _leap_colour(candidate)
		_line(candidate.origin, candidate.landing_point, colour)
		_cross(candidate.landing_point, 0.4, colour)
		if not candidate.accepted:
			continue
		# The swept volume, for the accepted one only: two spheres and four rails is a
		# readable capsule silhouette, and drawing it for every rejected candidate as well
		# would bury the geometry the leap is being judged against.
		_wire_sphere(candidate.origin, envelope.normal_clearance(), colour)
		_wire_sphere(candidate.landing_point, envelope.normal_clearance(), colour)
		_line(
			candidate.landing_point,
			candidate.landing_point + candidate.landing_normal * NORMAL_LENGTH,
			COLOR_SURFACE_NORMAL
		)


# ----- primitives -----


static func _mode_colour(mode: NavLocomotion.Mode) -> Color:
	match mode:
		NavLocomotion.Mode.SURFACE_CRAWL:
			return COLOR_CRAWL
		NavLocomotion.Mode.TUNNEL_SWIM:
			return COLOR_SWIM
		NavLocomotion.Mode.WIGGLE:
			return COLOR_WIGGLE
		NavLocomotion.Mode.LEAP:
			return COLOR_LEAP
	return COLOR_STALLED


static func _leap_colour(candidate: NavLeapCandidate) -> Color:
	if candidate.accepted:
		return COLOR_LEAP_ACCEPTED
	match candidate.rejection:
		NavLeapCandidate.Rejection.NO_LAUNCH_POSE:
			return COLOR_REJECT_LAUNCH
		NavLeapCandidate.Rejection.TOO_EXPENSIVE:
			return COLOR_REJECT_COST
		NavLeapCandidate.Rejection.BLOCKED_FLIGHT:
			return COLOR_REJECT_BLOCKED
		NavLeapCandidate.Rejection.NO_GRAB:
			return COLOR_REJECT_NO_GRAB
	return COLOR_REJECT_COST


func _make_view(mesh: ImmediateMesh) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# NOT INFERRED BY GODOT, and the failure is silent: without it every colour above
	# renders flat white, and an overlay whose whole job is distinguishing four modes and
	# four rejection reasons distinguishes nothing. verify_navigation_static.gd asserts it
	# for every debug file that names an ImmediateMesh, this one included.
	material.vertex_color_use_as_albedo = true
	material.disable_fog = true
	# Drawn through geometry on purpose. The body volumes are most useful exactly when the
	# alien is inside a crevice, which is when a depth test would hide them.
	material.no_depth_test = true
	material.render_priority = 2

	var view := MeshInstance3D.new()
	view.mesh = mesh
	view.material_override = material
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	view.extra_cull_margin = 4096.0
	add_child(view)
	return view


func _line(from: Vector3, to: Vector3, colour: Color) -> void:
	_mesh.surface_set_color(colour)
	_mesh.surface_add_vertex(from)
	_mesh.surface_set_color(colour)
	_mesh.surface_add_vertex(to)


func _cross(at: Vector3, size: float, colour: Color) -> void:
	for axis: int in 3:
		var offset := Vector3.ZERO
		offset[axis] = maxf(size, 0.02)
		_line(at - offset, at + offset, colour)


## A line with a two-barb head, so direction is readable without watching it move.
func _arrow(from: Vector3, to: Vector3, colour: Color) -> void:
	_line(from, to, colour)
	var shaft: Vector3 = to - from
	if shaft.is_zero_approx():
		return
	var heading: Vector3 = shaft.normalized()
	var side: Vector3 = heading.cross(Vector3.UP)
	if side.is_zero_approx():
		side = heading.cross(Vector3.RIGHT)
	side = side.normalized() * shaft.length() * 0.15
	var back: Vector3 = to - heading * shaft.length() * 0.25
	_line(to, back + side, colour)
	_line(to, back - side, colour)


func _ring(at: Vector3, normal: Vector3, radius: float, colour: Color) -> void:
	var axis: Vector3 = normal.normalized()
	if axis.is_zero_approx():
		axis = Vector3.UP
	var first: Vector3 = axis.cross(Vector3.RIGHT)
	if first.is_zero_approx():
		first = axis.cross(Vector3.UP)
	first = first.normalized() * radius
	var previous: Vector3 = at + first
	for step: int in SPHERE_SEGMENTS:
		var angle: float = TAU * float(step + 1) / float(SPHERE_SEGMENTS)
		var next: Vector3 = at + first.rotated(axis, angle)
		_line(previous, next, colour)
		previous = next


func _wire_sphere(at: Vector3, radius: float, colour: Color) -> void:
	if radius <= 0.0:
		return
	for ring: int in SPHERE_RINGS:
		var axis := Vector3.ZERO
		axis[ring] = 1.0
		_ring(at, axis, radius, colour)
