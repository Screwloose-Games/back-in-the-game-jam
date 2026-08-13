extends Node

## Renders the cave from fixed vantages and writes PNGs, so the section 39 overlay can
## be checked by looking at it.
##
##   godot --path <root> res://gameplay/creature/navigation/tools/capture_sandbox.tscn
##
## NOT headless -- there is no framebuffer to read back in that mode, and the whole
## point is the pixels.
##
## EVERY ASSERTION IN tests/ AND tools/ PASSES AGAINST AN OVERLAY THAT DRAWS NOTHING AT
## ALL. A missing `vertex_color_use_as_albedo` renders it flat white; a `surface_begin`
## with no vertices errors and drops the frame; a cull margin that is too small pops it
## out of view; a camera left at its default rotation faces away from the entire cave
## while the panel cheerfully reports a thousand edges. That last one was a real defect
## in the sandbox, found by looking and by nothing else.
##
## FIXED VANTAGES, NOT A FLY-THROUGH. The three shots that matter are close-ups of three
## openings a few metres across, and hand-flying to them is both fiddly and different
## every time -- which is exactly what you do not want from the artefact you compare
## against last week's.
##
## Output goes to user:// (`~/Library/Application Support/Godot/app_userdata/...` on
## macOS) and the absolute paths are printed on exit.

## Frames to settle before each shot. The route overlay rebuilds in _process, so the
## first frame after a change still shows the previous one.
const SETTLE_FRAMES: int = 6

var _navigation: CreatureNavigation = null
var _camera: Camera3D = null
var _written := PackedStringArray()


func _ready() -> void:
	var world := Node3D.new()
	add_child(world)
	NavigationSandboxGeometry.build(world)

	_navigation = CreatureNavigation.new()
	_navigation.config = NavigationConfig.new()
	world.add_child(_navigation)

	_camera = Camera3D.new()
	_camera.far = 400.0
	_camera.current = true
	world.add_child(_camera)

	await get_tree().physics_frame
	await get_tree().physics_frame
	_navigation.bake_now(NavigationSandboxGeometry.bake_region())

	var overlay := NavigationDebugDraw.new()
	overlay.navigation = _navigation
	world.add_child(overlay)

	_draw_cave(world)

	# THE WHOLE CAVE. Green normal-volume edges everywhere, one amber cluster at the
	# tight tunnel, and chamber C's island of nodes with nothing joining it.
	await _shoot(
		"01_overview", Vector3(-18.0, 26.0, -20.0), NavigationSandboxGeometry.INTERIOR.get_center()
	)

	# Section 13.2's three outcomes, ONE OPENING AT A TIME. Read these as a set: the
	# first must be green through the gap, the second amber through it, the third EMPTY
	# across it.
	#
	# TOP-DOWN AND TIGHTLY CROPPED, which took two attempts to get right. The obvious
	# vantage -- off the end of the divider, looking along it -- puts the tight tunnel
	# directly behind the wide one in screen space, so the amber cluster appears to be
	# crossing the 6 m opening and the shot proves the opposite of what it claims.
	# Looking straight down separates the two openings by their z, and the narrow FOV
	# crops whichever one is not the subject out of frame entirely.
	await _shoot(
		"02_wide_tunnel_normal",
		NavigationSandboxGeometry.WIDE_TUNNEL.get_center() + Vector3(0.0, 26.0, 0.0),
		NavigationSandboxGeometry.WIDE_TUNNEL.get_center(),
		30.0
	)
	await _shoot(
		"03_tight_tunnel_wiggle",
		NavigationSandboxGeometry.TIGHT_TUNNEL.get_center() + Vector3(0.0, 20.0, 0.0),
		NavigationSandboxGeometry.TIGHT_TUNNEL.get_center(),
		30.0
	)
	await _shoot(
		"04_slot_impassable",
		NavigationSandboxGeometry.SLOT.get_center() + Vector3(0.0, 20.0, 0.0),
		NavigationSandboxGeometry.SLOT.get_center(),
		30.0
	)

	# GRAPH OFF FOR THE ROUTE SHOTS. A route is a dozen white segments and the graph is
	# a thousand green ones drawn through the same volume; with both on, the thing the
	# shot exists to show is the thing you cannot find in it.
	overlay.draw_graph = false
	overlay.refresh_graph()

	# Scenario A, and then Scenarios C and G. The second route must stop at the wall.
	_plan_to(NavigationSandboxGeometry.CHAMBER_B_CENTER)
	await _shoot(
		"05_route_a_to_b",
		Vector3(-14.0, 22.0, -16.0),
		NavigationSandboxGeometry.INTERIOR.get_center()
	)
	_plan_to(NavigationSandboxGeometry.CHAMBER_C_CENTER)
	await _shoot(
		"06_partial_a_to_c",
		Vector3(-14.0, 22.0, -16.0),
		NavigationSandboxGeometry.INTERIOR.get_center()
	)

	print("wrote %d captures:" % _written.size())
	for path: String in _written:
		print("  " + ProjectSettings.globalize_path(path))
	get_tree().quit(0)


func _plan_to(target: Vector3) -> void:
	var from: Vector3 = NavigationSandboxGeometry.CHAMBER_A_CENTER
	_navigation.set_body_position(from)
	_navigation.set_goal(target)
	_navigation.advance(0.0, from)
	print(
		(
			"[capture] route to %s: %s, %d anchors, %.1fs"
			% [
				target,
				_navigation.route.status_name(),
				_navigation.route.anchors.size(),
				_navigation.route.cost
			]
		)
	)


## look_at AFTER the camera is in the tree and positioned -- it needs a global
## transform, and a Camera3D left at its default rotation faces its own -Z, which from
## any of the vantages above is a view of nothing at all.
##
## A straight-down look_at needs a non-parallel up vector, or the basis is degenerate
## and Godot refuses the call.
func _shoot(label: String, from: Vector3, at: Vector3, fov: float = 70.0) -> void:
	_camera.fov = fov
	_camera.global_position = from
	var up: Vector3 = Vector3.UP
	if absf((at - from).normalized().dot(Vector3.UP)) > 0.999:
		up = Vector3.FORWARD
	_camera.look_at(at, up)

	for _frame: int in SETTLE_FRAMES:
		await get_tree().process_frame
	# The texture is only valid after the frame has been drawn.
	await RenderingServer.frame_post_draw

	var image: Image = get_viewport().get_texture().get_image()
	if image == null:
		printerr("[%s] no framebuffer -- are you running with --headless?" % label)
		return
	var path: String = "user://navigation_%s.png" % label
	if image.save_png(path) != OK:
		printerr("[%s] could not write %s" % [label, path])
		return
	_written.append(path)
	print("[capture] %s  %dx%d" % [label, image.get_width(), image.get_height()])


## The cave as wireframe. Solid boxes hide the interior, and translucent ones sort per
## object on GL Compatibility, so seventeen overlapping slabs pop as the camera moves.
func _draw_cave(parent: Node3D) -> void:
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.disable_fog = true

	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for box: AABB in NavigationSandboxGeometry.solids():
		for corner: int in 8:
			for axis: int in 3:
				var neighbor: int = corner | (1 << axis)
				if neighbor == corner:
					continue
				mesh.surface_set_color(NavigationSandbox.COLOR_CAVE)
				mesh.surface_add_vertex(box.get_endpoint(corner))
				mesh.surface_set_color(NavigationSandbox.COLOR_CAVE)
				mesh.surface_add_vertex(box.get_endpoint(neighbor))
	mesh.surface_end()

	var view := MeshInstance3D.new()
	view.mesh = mesh
	view.material_override = material
	view.extra_cull_margin = 4096.0
	parent.add_child(view)
