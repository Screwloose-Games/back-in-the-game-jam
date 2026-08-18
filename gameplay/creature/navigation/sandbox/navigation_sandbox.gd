class_name NavigationSandbox
extends Node3D

## Somewhere to LOOK at the graph (navigation.md section 39).
##
## It exists because every interesting navigation failure passes the unit suite. A
## graph that connects across a crevice, an endpoint attached through a wall, a route
## that never smooths -- each produces a creature that heads plausibly toward roughly
## the right place, and each is obvious in one glance here.
##
## THE THING TO CHECK EVERY TIME IS THE SLOT. Press 2. The route to chamber C must come
## back PARTIAL and must stop at the wall, and no edge may cross the 1 x 1 opening. If
## a line crosses it, Invariant 5 is broken, Scenarios C and G are broken, and nothing
## in tests/ will have told you -- the graph will simply have started working better.
##
## The second thing is the two tunnels, READ AS A COMPARISON. Green edges must cross the
## 6 m tunnel and no green may cross the 2 m one. Amber in BOTH is correct rather than a
## smell: a 6 x 6 opening has corner pockets a metre from two walls at once, a node lands
## in one, and every edge reaching it is a squeeze. Green through the tight tunnel is the
## failure -- the normal body being validated against a passage it does not fit.
##
## `tools/capture_sandbox.tscn` renders both tunnels from fixed top-down vantages, which
## is easier to trust than flying here by hand: looking along the divider stacks the two
## openings on top of each other and the amber cluster appears to cross the wrong one.
##
##     1        route chamber A -> chamber B        (Scenarios A and B)
##     2        route chamber A -> chamber C        (Scenarios C and G: must be PARTIAL)
##     3        route across chamber A              (Scenario D: a ~23 m crawl)
##     4        step the body along the current route by hand
##     R        rebake
##     G        toggle the graph overlay
##     Tab      toggle the whole overlay
##     WASD/QE  fly the camera, hold right mouse to look
##
## The cave is built in code rather than saved into the .tscn, for the reason
## perception's sandbox gives: the editor rewrites relative ext_resource paths on every
## re-save, and generated geometry cannot drift from the numbers its own file documents.

const CAMERA_SPEED: float = 14.0
const CAMERA_LOOK_SENSITIVITY: float = 0.005
## How far each press of 4 walks the stand-in body toward the current anchor. Big
## enough to see the index advance, small enough to watch smoothing collapse anchors.
const BODY_STEP: float = 2.0
## Light enough to read against Godot's default clear colour, which is itself a mid
## grey. At 0.35 the cave wireframe and the background are near enough the same value
## that the cave looks absent.
const COLOR_CAVE := Color(0.62, 0.64, 0.78, 1.0)

var _navigation: CreatureNavigation = null
var _overlay: NavigationDebugDraw = null
var _locomotion_overlay: NavigationLocomotionDraw = null
var _panel: NavigationDebugPanel = null
var _camera: Camera3D = null
var _body: Vector3 = NavigationSandboxGeometry.CHAMBER_A_CENTER
var _looking: bool = false


func _ready() -> void:
	NavigationSandboxGeometry.build(self)
	_draw_cave()
	_build_navigation()
	_build_debug()
	_build_camera()
	_navigation.bake(NavigationSandboxGeometry.bake_region())


func _process(delta: float) -> void:
	_fly_camera(delta)


func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_RIGHT:
		_looking = button.pressed
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _looking:
		_camera.rotate_y(-motion.relative.x * CAMERA_LOOK_SENSITIVITY)
		_camera.rotate_object_local(Vector3.RIGHT, -motion.relative.y * CAMERA_LOOK_SENSITIVITY)
		return

	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_1:
			_route_to(NavigationSandboxGeometry.CHAMBER_B_CENTER)
		KEY_2:
			_route_to(NavigationSandboxGeometry.CHAMBER_C_CENTER)
		KEY_3:
			_route_to(NavigationSandboxGeometry.CHAMBER_A_FAR)
		KEY_4:
			_step_body()
		KEY_R:
			_body = NavigationSandboxGeometry.CHAMBER_A_CENTER
			_navigation.bake(NavigationSandboxGeometry.bake_region())
		KEY_G:
			_overlay.draw_graph = not _overlay.draw_graph
			_overlay.refresh_graph()
		KEY_TAB:
			_overlay.visible = not _overlay.visible
			_locomotion_overlay.visible = _overlay.visible
			_panel.visible = _overlay.visible


# ----- setup -----


func _build_navigation() -> void:
	_navigation = CreatureNavigation.new()
	_navigation.name = "CreatureNavigation"
	# Left at script defaults deliberately. The sandbox is where you find out whether
	# the SHIPPED numbers produce a usable cave; a sandbox with its own tuned config
	# proves only that some config exists that works.
	_navigation.config = NavigationConfig.new()
	add_child(_navigation)
	_navigation.set_body_position(_body)
	_navigation.graph_baked.connect(_on_graph_baked)


func _build_debug() -> void:
	_overlay = NavigationDebugDraw.new()
	_overlay.name = "NavigationDebugDraw"
	_overlay.navigation = _navigation
	add_child(_overlay)

	# The phases 3-6 half of section 39. Separate node, same navigator: the graph overlay
	# redraws on bake and this one redraws every tick, and Tab toggles both together.
	_locomotion_overlay = NavigationLocomotionDraw.new()
	_locomotion_overlay.name = "NavigationLocomotionDraw"
	_locomotion_overlay.navigation = _navigation
	add_child(_locomotion_overlay)

	var layer := CanvasLayer.new()
	add_child(layer)
	_panel = NavigationDebugPanel.new()
	_panel.name = "NavigationDebugPanel"
	_panel.navigation = _navigation
	_panel.position = Vector2(16.0, 16.0)
	layer.add_child(_panel)


## Places the camera OUTSIDE the cave, looking down into it from a corner.
##
## AIMED WITH look_at RATHER THAN LEFT AT ITS DEFAULT ROTATION. A Camera3D faces its
## own -Z, so one dropped at a negative-Z vantage with no rotation stares away from
## everything -- the panel reports 161 nodes and 1075 edges over a completely empty
## viewport, which reads as an overlay that failed to draw rather than a camera facing
## a wall. look_at has to come AFTER add_child, because it needs a global transform.
func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "SandboxCamera"
	_camera.position = Vector3(-18.0, 26.0, -20.0)
	_camera.far = 400.0
	_camera.current = true
	add_child(_camera)
	_camera.look_at(NavigationSandboxGeometry.INTERIOR.get_center(), Vector3.UP)

	# One light, purely so the wireframe is not the only thing on screen. The cave
	# boxes have no meshes at all -- see _draw_cave.
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	add_child(light)


## The cave as wireframe, not as solid meshes.
##
## Solid boxes hide the interior, and translucent ones sort PER OBJECT on the GL
## Compatibility renderer this project targets -- seventeen overlapping transparent
## slabs pop and reorder as the camera moves, which reads as a bug in the graph.
func _draw_cave() -> void:
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.disable_fog = true

	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for box: AABB in NavigationSandboxGeometry.solids():
		_wire_box(mesh, box)
	mesh.surface_end()

	var view := MeshInstance3D.new()
	view.name = "CaveWireframe"
	view.mesh = mesh
	view.material_override = material
	view.extra_cull_margin = 4096.0
	add_child(view)


# ----- interaction -----


func _route_to(target: Vector3) -> void:
	_navigation.set_body_position(_body)
	_navigation.set_goal(target)
	_navigation.advance(0.0, _body)


func _step_body() -> void:
	if _navigation.route == null or not _navigation.follower.has_route():
		return
	var anchor: Vector3 = _navigation.follower.current_anchor()
	var offset: Vector3 = anchor - _body
	_body += offset.limit_length(BODY_STEP)
	_navigation.set_body_position(_body)
	_navigation.follower.advance(_body)


func _fly_camera(delta: float) -> void:
	var move := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		move += Vector3.FORWARD
	if Input.is_physical_key_pressed(KEY_S):
		move += Vector3.BACK
	if Input.is_physical_key_pressed(KEY_A):
		move += Vector3.LEFT
	if Input.is_physical_key_pressed(KEY_D):
		move += Vector3.RIGHT
	if Input.is_physical_key_pressed(KEY_E):
		move += Vector3.UP
	if Input.is_physical_key_pressed(KEY_Q):
		move += Vector3.DOWN
	if move != Vector3.ZERO:
		_camera.translate(move.normalized() * CAMERA_SPEED * delta)


func _on_graph_baked(graph: NavGraph) -> void:
	if graph == null:
		return
	var stats: Dictionary = _navigation.bake_stats()
	print(
		(
			"[sandbox] baked %d nodes, %d edges (%d normal, %d wiggle)"
			% [graph.node_count(), graph.edge_count(), stats["edges_normal"], stats["edges_wiggle"]]
		)
	)


func _wire_box(mesh: ImmediateMesh, box: AABB) -> void:
	# Godot's AABB endpoint order: bit 0 is +x, bit 1 is +y, bit 2 is +z. Two corners
	# are joined by an edge exactly when their indices differ in one bit.
	for corner: int in 8:
		for axis: int in 3:
			var neighbor: int = corner | (1 << axis)
			if neighbor == corner:
				continue
			mesh.surface_set_color(COLOR_CAVE)
			mesh.surface_add_vertex(box.get_endpoint(corner))
			mesh.surface_set_color(COLOR_CAVE)
			mesh.surface_add_vertex(box.get_endpoint(neighbor))
