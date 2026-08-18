class_name NavigationDebugDraw
extends Node3D

## The section 39 overlay. NOT OPTIONAL POLISH -- the spec says so outright: "this
## tooling is considered part of the navigation implementation rather than optional
## polish", and asks for it BEFORE advanced behaviour.
##
## It exists because every interesting navigation failure passes the unit suite. A
## graph that connects across a crevice, an endpoint attached through a wall, a route
## that never smooths -- all of them produce a creature that moves plausibly toward
## roughly the right place, and all of them are obvious in one glance at this overlay.
## The perception module's README records three defects found by looking at its
## equivalent and by nothing else.
##
## THE EDGE COLOURS ARE THE MOST USEFUL THING ON SCREEN. Normal-volume against wiggle
## is Invariant 5 made visible: a player-only slot should have NO LINE crossing it, and
## a tight tunnel should be amber all the way through. If the slot has a line, Scenarios
## C and G are broken and no assertion in tests/ will have said so.
##
## Two meshes, not one. The graph is static between bakes and can cost thousands of
## vertices; rebuilding it every frame to redraw a twelve-vertex route is the kind of
## overlay that makes people turn the overlay off.

## Segments per node marker. A three-axis cross, sized by clearance -- cheap enough to
## draw for every node in a cave, and the size differences are what make the medial
## skeleton legible.
const NODE_CROSS_AXES: int = 3
## Fraction of a node's clearance the marker spans. Full size makes adjacent markers
## overlap into a solid mass in open chambers.
const NODE_MARKER_SCALE: float = 0.35
## Marker half-size for the current route anchor, in metres.
const CURRENT_ANCHOR_SIZE: float = 0.6

const COLOR_EDGE_NORMAL := Color(0.30, 0.85, 0.45, 1.0)
const COLOR_EDGE_WIGGLE := Color(0.98, 0.62, 0.15, 1.0)
const COLOR_NODE_TIGHT := Color(0.95, 0.35, 0.30, 1.0)
const COLOR_NODE_OPEN := Color(0.35, 0.65, 0.98, 1.0)
const COLOR_ROUTE := Color(0.95, 0.95, 0.98, 1.0)
const COLOR_ROUTE_CURRENT := Color(0.95, 0.30, 0.90, 1.0)
const COLOR_ROUTE_SKIPPED := Color(0.50, 0.50, 0.55, 1.0)
const COLOR_ATTACH_OK := Color(0.30, 0.95, 0.55, 1.0)
const COLOR_ATTACH_REJECTED := Color(0.95, 0.25, 0.25, 1.0)

@export var navigation: CreatureNavigation = null
@export var draw_graph: bool = true
@export var draw_route: bool = true
## Section 39's "collapsed/skipped anchors" and section 16's rejected candidates. Off
## by default because it only means anything while you are debugging attachment.
@export var draw_attachment: bool = true

var _graph_mesh: ImmediateMesh = null
var _route_mesh: ImmediateMesh = null
var _graph_view: MeshInstance3D = null
var _route_view: MeshInstance3D = null


func _ready() -> void:
	top_level = true
	_graph_mesh = ImmediateMesh.new()
	_route_mesh = ImmediateMesh.new()
	_graph_view = _make_view(_graph_mesh, false)
	_route_view = _make_view(_route_mesh, true)
	if navigation != null:
		navigation.graph_baked.connect(_on_graph_baked)
		# A navigator that already finished baking before this node entered the tree
		# never fires the signal again, and the overlay stays empty while everything
		# else works -- which reads as a navigation bug.
		if navigation.graph != null:
			_on_graph_baked(navigation.graph)


func _process(_delta: float) -> void:
	_redraw_route()


func set_navigation(target: CreatureNavigation) -> void:
	navigation = target
	if navigation != null and not navigation.graph_baked.is_connected(_on_graph_baked):
		navigation.graph_baked.connect(_on_graph_baked)
	refresh_graph()


## Re-uploads the static graph mesh. Call after toggling `draw_graph`, which otherwise
## does nothing at all until the next bake -- a toggle that appears broken.
func refresh_graph() -> void:
	if navigation != null:
		_on_graph_baked(navigation.graph)


# ----- graph -----


func _on_graph_baked(graph: NavGraph) -> void:
	_graph_mesh.clear_surfaces()
	if graph == null or not draw_graph or graph.node_count() == 0:
		return
	var comfortable: float = 2.5
	if navigation != null and navigation.config != null:
		comfortable = navigation.config.comfortable_clearance

	_graph_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for edge: NavEdge in graph.all_edges():
		var colour: Color = (
			COLOR_EDGE_WIGGLE if edge.type == NavEdge.Type.WIGGLE else COLOR_EDGE_NORMAL
		)
		_line(
			_graph_mesh,
			graph.node_at(edge.from_id).position,
			graph.node_at(edge.to_id).position,
			colour
		)
	for id: Variant in graph.node_ids():
		var node: NavNode = graph.node_at(id)
		var openness: float = clampf(node.clearance / maxf(comfortable, 0.01), 0.0, 1.0)
		_cross(
			_graph_mesh,
			node.position,
			node.clearance * NODE_MARKER_SCALE,
			COLOR_NODE_TIGHT.lerp(COLOR_NODE_OPEN, openness)
		)
	_graph_mesh.surface_end()


# ----- route -----


func _redraw_route() -> void:
	_route_mesh.clear_surfaces()
	if navigation == null:
		return
	var route: NavRoute = navigation.route
	var has_route: bool = draw_route and route != null and route.anchors.size() >= 2
	var attempts: Array = []
	if draw_attachment and navigation.planner != null:
		attempts = navigation.planner.last_attachment_attempts
	if not has_route and attempts.is_empty():
		return

	_route_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	if has_route:
		var follower: RouteFollower = navigation.follower
		var current: int = follower.index if follower != null else 1
		var skipped: PackedInt32Array = (
			follower.skipped_anchors if follower != null else PackedInt32Array()
		)
		for step: int in range(route.anchors.size() - 1):
			var colour: Color = COLOR_ROUTE
			if skipped.has(step):
				colour = COLOR_ROUTE_SKIPPED
			_line(_route_mesh, route.anchors[step], route.anchors[step + 1], colour)
		if current < route.anchors.size():
			_cross(_route_mesh, route.anchors[current], CURRENT_ANCHOR_SIZE, COLOR_ROUTE_CURRENT)

	# Section 16 made visible. A route attaching to a distant node looks like a bug
	# until the three nearer nodes it tried are on screen in red.
	for attempt: Array in attempts:
		var target: Vector3 = attempt[0]
		var accepted: bool = attempt[1]
		_cross(
			_route_mesh,
			target,
			CURRENT_ANCHOR_SIZE * 0.5,
			COLOR_ATTACH_OK if accepted else COLOR_ATTACH_REJECTED
		)
	_route_mesh.surface_end()


# ----- primitives -----


func _make_view(mesh: ImmediateMesh, on_top: bool) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# NOT INFERRED BY GODOT, and the failure is silent: without it every colour below
	# renders flat white, the wiggle/normal distinction disappears, and the overlay
	# looks like one undifferentiated tangle. verify_navigation_static.gd asserts it.
	material.vertex_color_use_as_albedo = true
	material.disable_fog = true
	material.no_depth_test = on_top
	material.render_priority = 1 if on_top else 0

	var view := MeshInstance3D.new()
	view.mesh = mesh
	view.material_override = material
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The overlay's AABB comes from whatever it drew last frame, so an overlay that is
	# briefly tiny and then cave-sized pops in and out of the frustum.
	view.extra_cull_margin = 4096.0
	add_child(view)
	return view


func _line(mesh: ImmediateMesh, from: Vector3, to: Vector3, colour: Color) -> void:
	mesh.surface_set_color(colour)
	mesh.surface_add_vertex(from)
	mesh.surface_set_color(colour)
	mesh.surface_add_vertex(to)


func _cross(mesh: ImmediateMesh, at: Vector3, size: float, colour: Color) -> void:
	var span: float = maxf(size, 0.05)
	for axis: int in NODE_CROSS_AXES:
		var offset := Vector3.ZERO
		offset[axis] = span
		_line(mesh, at - offset, at + offset, colour)
