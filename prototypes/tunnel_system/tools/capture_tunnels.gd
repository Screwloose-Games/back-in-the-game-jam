extends Node

## Screenshots the baked cave from inside and out. NOT headless - it renders:
##
##     godot --path <root> res://prototypes/tunnel_system/tools/capture_tunnels.tscn
##
## This tool is not optional polish. Every assertion in verify_tunnel_system
## passes against a shell whose winding is right for physics and wrong for the
## eye, against a material that resolves to flat white, and against a cave lit by
## nothing at all. The suite cannot tell you the tunnels look like tunnels.
##
## Writes PNGs to tools/_shots/.

const SCENE_PATH := "res://prototypes/tunnel_system/tunnel_system_prototype.tscn"

## Interior viewpoints: where the camera sits, what it looks at, what to call the
## file. Chosen to cover every bore in the level - an 8 m trunk, a junction, the
## 2.5 m squeeze, and the deepest chamber.
const SHOTS := [
	{
		"name": "entrance_shaft",
		"from": Vector3(1, -9, -1),
		"at": Vector3(-3, -20, 2),
	},
	{
		# ON the entrance shaft's centreline, not merely near it. The first version
		# of this viewpoint was picked by eye and sat two metres inside solid rock,
		# which photographs as pure black - identical to a broken material, an
		# unlit cave, and an outward-wound shell. Take interior viewpoints from a
		# centreline coordinate the layout actually contains.
		"name": "antechamber_junction",
		"from": Vector3(-1.2, -26, 0.8),
		"at": Vector3(0, -30, 0),
	},
	{
		"name": "the_squeeze",
		"from": Vector3(-30, -62, 30),
		"at": Vector3(0, -85, 18),
	},
	{
		"name": "deep_hub",
		"from": Vector3(71.2, -113.4, -38.8),
		"at": Vector3(70, -120, -40),
	},
	{
		"name": "core_chamber",
		"from": Vector3(42, -160, 2),
		"at": Vector3(30, -170, 20),
	},
]

## Where the exterior shot is taken from. The shell is closed, so from outside
## the network reads as a knot of pipes - which is exactly what is wanted for
## checking the layout, and nothing the player will ever see.
const OVERVIEW_FROM := Vector3(125, 15, 125)
const OVERVIEW_AT := Vector3(0, -93, -11)

var _camera: Camera3D
var _lamp: SpotLight3D
var _scene: Node


func _ready() -> void:
	_run()


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		printerr("could not load %s" % SCENE_PATH)
		get_tree().quit(1)
		return
	_scene = packed.instantiate()
	add_child(_scene)
	await get_tree().physics_frame

	# The prototype captures the mouse and hands the player a live camera. Both
	# get in the way of a scripted capture.
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var hud := _scene.get_node_or_null("Hud") as CanvasLayer
	if hud != null:
		hud.visible = false

	_camera = Camera3D.new()
	_camera.fov = 75.0
	_camera.near = 0.05
	_camera.far = TunnelKnobs.CAMERA_FAR
	add_child(_camera)
	_camera.make_current()

	# A COPY OF THE HELMET LAMP, not a stand-in for it. An omni light of the same
	# energy spreads over the whole sphere and comes back several stops darker
	# than the player's 35-degree spot, so the shots would understate every wide
	# chamber and this tool would report a lighting problem the game does not have.
	# Values mirror prototypes/navigation/zero_g_player.tscn.
	#
	# Shadows stay ON: the trap about a sealed tube rendering at ambient only
	# applies to a light OUTSIDE the shell. This one is inside it, which is what
	# gives the bore its form.
	_lamp = SpotLight3D.new()
	_lamp.light_color = Color(1, 0.96, 0.89)
	_lamp.light_energy = 3.5
	_lamp.spot_range = TunnelKnobs.HELMET_LAMP_RANGE
	_lamp.spot_angle = TunnelKnobs.HELMET_LAMP_ANGLE
	_lamp.spot_attenuation = 1.2
	_lamp.spot_angle_attenuation = 0.6
	_lamp.shadow_enabled = TunnelKnobs.HELMET_LAMP_SHADOWS
	_lamp.position = Vector3(0.14, -0.12, 0)
	_camera.add_child(_lamp)

	var directory := _res("_shots")
	DirAccess.make_dir_recursive_absolute(directory)

	for shot: Dictionary in SHOTS:
		await _capture(directory, shot["name"], shot["from"], shot["at"])

	# One shot WITH the HUD, so the readouts, the map and the tuning panel are
	# covered by the same "look at it" rule as the geometry. A panel that lays out
	# wrong, runs off the bottom of the screen, or renders as an empty box passes
	# every check in the verifier.
	if hud != null:
		hud.visible = true
		await _capture(directory, "hud", SHOTS[0]["from"], SHOTS[0]["at"])
		hud.visible = false

	# Second pass with the murk pulled back. A chamber wider than FOG_DEPTH_END is
	# a black void in the first pass - which is the draw distance doing its job,
	# and useless for judging whether the geometry is right. The "_lit" shots are
	# for reading the cave; the plain ones are for judging how it feels.
	_open_up()
	for shot: Dictionary in SHOTS:
		await _capture(directory, "%s_lit" % shot["name"], shot["from"], shot["at"])

	await _capture_overview(directory)

	print("wrote %d shots to %s" % [SHOTS.size() * 2 + 1, directory])
	get_tree().quit(0)


## Pushes fog and ambient out so the geometry is inspectable.
func _open_up() -> void:
	var world := _scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world != null:
		world.environment.fog_depth_end = 60.0
		world.environment.ambient_light_energy = 0.30
	_camera.far = 90.0
	_lamp.spot_range = 60.0
	# A shadow map stretched over 60 m instead of 16 bands the walls with
	# concentric rings of acne. That is a property of this pass, not of the level,
	# and it obscures the very geometry the pass exists to show.
	_lamp.shadow_enabled = false
	_lamp.light_energy = 6.0


func _capture(directory: String, shot_name: String, from: Vector3, at: Vector3) -> void:
	_camera.global_transform = Transform3D(
		Basis.looking_at((at - from).normalized(), _reference_up(at - from)), from
	)
	# Two frames, not one: the first is drawn with the previous transform still
	# in the render server, so every shot would come back one viewpoint stale.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(directory.path_join("%s.png" % shot_name))


## The wide shot, with fog and the near clip opened up so the whole 200 m network
## is visible at once.
func _capture_overview(directory: String) -> void:
	var world := _scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world != null:
		world.environment.fog_enabled = false
		world.environment.ambient_light_energy = 0.6
	_camera.far = 800.0
	_lamp.visible = false

	var sun := DirectionalLight3D.new()
	sun.basis = Basis.looking_at(Vector3(-0.6, -0.65, -0.46), Vector3.UP)
	sun.light_energy = 1.4
	sun.shadow_enabled = false
	add_child(sun)

	await _capture(directory, "overview", OVERVIEW_FROM, OVERVIEW_AT)


## Basis.looking_at fails when its up vector is parallel to the direction, and
## the entrance shaft and the deep shaft are both close to vertical.
func _reference_up(direction: Vector3) -> Vector3:
	if absf(direction.normalized().dot(Vector3.UP)) > 0.99:
		return Vector3.BACK
	return Vector3.UP


func _res(relative_path: String) -> String:
	var dir: String = (get_script() as Script).resource_path.get_base_dir()
	return dir.path_join(relative_path).simplify_path()
