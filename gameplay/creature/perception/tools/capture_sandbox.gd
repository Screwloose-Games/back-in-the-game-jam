extends Node

## Renders the sandbox and writes PNGs, so the section 30 overlay can be checked by
## looking at it.
##
##   godot --path <root> res://gameplay/creature/perception/tools/capture_sandbox.tscn
##
## NOT headless -- there is no framebuffer to read back in that mode, and the whole
## point is the pixels.
##
## EVERY PHYSICS ASSERTION IN tools/ AND tests/ PASSES AGAINST AN OVERLAY THAT DRAWS
## NOTHING AT ALL. A missing vertex_color_use_as_albedo renders it flat white; a
## surface_begin with no vertices errors and drops the frame; a cull margin that is
## too small pops it out of view. None of those is visible to an assertion about
## uncertainty radii, which is why this exists.
##
## Output goes to user:// (`~/Library/Application Support/Godot/app_userdata/...` on
## macOS) and the absolute paths are printed on exit.

const SANDBOX: String = "res://gameplay/creature/perception/sandbox/perception_sandbox.tscn"
## Frames to settle before each shot. The overlay rebuilds in _process and the first
## frame after a change still shows the previous one.
const SETTLE_FRAMES: int = 6

var _sandbox: Node = null
var _perception: CreaturePerception = null
var _player: Node3D = null
var _written: PackedStringArray = PackedStringArray()


func _ready() -> void:
	var packed: PackedScene = load(SANDBOX)
	_sandbox = packed.instantiate()
	add_child(_sandbox)
	await get_tree().process_frame

	_perception = _sandbox.get_node("CreaturePerception") as CreaturePerception
	_player = _sandbox.get_node("StandIn") as Node3D
	if _perception == null or _player == null:
		printerr("the sandbox did not build; nothing to capture")
		get_tree().quit(1)
		return

	# In the open, in front of the creature: the cone should read as SEEING.
	_player.global_position = Vector3(6, 2, 0)
	await _shoot("01_vision_clear")

	# Behind the divider: still a candidate, still in the cone, no line of sight.
	_player.global_position = Vector3(6, 2, -9)
	await _shoot("02_vision_blocked")

	# SECTION 11'S WHOLE THESIS, AS TWO PICTURES. Nearby drilling has to draw a
	# visibly TIGHTER uncertainty sphere than distant footsteps. If these two shots
	# look the same, hearing is reporting magically precise coordinates and the rest
	# of the AI has nothing to search for.
	_player.global_position = Vector3(-4, 2, 0)
	_perception.receive_noise(NoiseEvent.make(_player.global_position, 1.0, &"drill"))
	await _shoot("03_noise_near_drill")

	_player.global_position = Vector3(10, 2, 8)
	_perception.receive_noise(NoiseEvent.make(_player.global_position, 0.3, &"footstep"))
	await _shoot("04_noise_far_footstep")

	# A search region, mid-scan.
	_perception.request_activity_scan(
		AABB(_player.global_position - Vector3.ONE * 5.0, Vector3.ONE * 10.0), 1.0
	)
	await _shoot("05_activity_scan")

	# Geometry cells, colour-coded FREE / SOLID / CLEARANCE.
	_perception.request_geometry_scan(
		AABB(Vector3(-4, 0, -4), Vector3(8, 4, 8)),
		CreatureGeometryPerception.GeometryScanReason.PATH_BLOCKED
	)
	for _i: int in 40:
		await get_tree().process_frame
	await _shoot("06_geometry_scan")

	print("wrote %d captures:" % _written.size())
	for path: String in _written:
		print("  " + ProjectSettings.globalize_path(path))
	get_tree().quit(0)


func _shoot(label: String) -> void:
	for _i: int in SETTLE_FRAMES:
		await get_tree().process_frame
	# The texture is only valid after the frame has been drawn.
	await RenderingServer.frame_post_draw

	var image: Image = get_viewport().get_texture().get_image()
	if image == null:
		printerr("[%s] no framebuffer -- are you running with --headless?" % label)
		return
	var path: String = "user://perception_%s.png" % label
	if image.save_png(path) != OK:
		printerr("[%s] could not write %s" % [label, path])
		return
	_written.append(path)
	print("[capture] %s  %dx%d" % [label, image.get_width(), image.get_height()])
