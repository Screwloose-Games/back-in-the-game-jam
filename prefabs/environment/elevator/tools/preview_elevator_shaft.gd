extends Node3D

## Renders the assembled shaft around the car, and quits.
##
##   set SHAFT_SHOT=C:\somewhere\shaft.png
##   D:\Godot_v4.7.1-stable_win64.exe --path <root> --resolution 1600x900 \
##     --rendering-driver opengl3 \
##     res://prefabs/environment/elevator/tools/preview_elevator_shaft.tscn
##
## Name the scene explicitly or the main menu boots instead. NOT --headless:
## headless has no rendering device, so there is nothing to capture, and this is
## the only check of the four that can see a frame at all.
##
## verify_elevator_shaft.gd already proves the car fits by measurement. What this
## adds is everything measurement cannot reach: whether the indexed palette gets
## to the screen (anything magenta is a UV outside its swatch), whether the frame
## reads as a hoist frame rather than as scaffolding, and whether the collar looks
## like a fitting the shaft passes through. The rubble set once passed every
## headless check and rendered flat white, which is why this file exists.
##
## Two shots. The wide one is the assembly with the character for scale; the tight
## one is the collar, which is the part with a job you cannot judge from far away.

const SHAFT := "res://prefabs/environment/elevator/prefab_elevator_shaft.tscn"
const CAR := "res://prefabs/environment/elevator/prefab_elevator_car.tscn"
const CHARACTER := "res://assets/art/character/sk_player_character.gltf"

## The car's doorway faces -Z and a Godot camera looks down its own -Z, so a
## camera parked on +Z sees the back of anything left at yaw zero. Turned most of
## a half turn so the doorway and one corner column are both in frame - a shaft
## shot square on has no depth and every column hides behind another.
const PRESENTED_YAW := PI - 0.42

## No occlusion is baked into any of this, so a hard key against a dark ambient
## renders the lighting rig instead of the asset. Same reasoning as
## tools/voxel-props/preview_props.gd.
const AMBIENT_ENERGY := 0.85
const KEY_ENERGY := 1.5

## How far up the collar the stand-in rock sits. The bottom step is 0.36 m tall
## and is the part meant to hang below the ceiling, so the rock starts above it.
## Deliberately not 0.36: that put the slab's underside exactly on the beam ring
## at 5.76 m and the two dithered against each other all along the far edge.
const CEILING_SEAT := 0.42

const WIDE_FROM := Vector3(5.6, 4.4, 11.0)
const WIDE_AIM := Vector3(-0.2, 0.42, 0.0)
const COLLAR_FROM := Vector3(3.4, 3.6, 7.2)
const COLLAR_AIM := Vector3(0.16, 0.4, 0.0)

var _camera: Camera3D


func _ready() -> void:
	var shaft := _instance(SHAFT)
	shaft.rotation.y = PRESENTED_YAW

	var car := _instance(CAR)
	car.rotation.y = PRESENTED_YAW

	# In the doorway, facing out of it: 1.56 m of character against a 3.96 m bore
	# is the scale check the whole preview exists for. No rotation correction -
	# the -90 degree X on the character's node chain IS its Z-up conversion.
	# The doorway is the car's local -Z, so it points OUT along the negated yaw
	# vector. Getting that sign wrong parks the character behind the shell, which
	# is exactly where the first render of this scene put it.
	var miner := _instance(CHARACTER)
	miner.rotation.y = PRESENTED_YAW
	miner.position = (
		Vector3(sin(PRESENTED_YAW), 0.0, cos(PRESENTED_YAW)) * -1.5 + Vector3(0.0, 0.12, 0.0)
	)

	_add_ground()
	_add_ceiling(shaft)

	_camera = Camera3D.new()
	_camera.position = WIDE_FROM
	_camera.rotation = WIDE_AIM
	_camera.fov = 55.0
	add_child(_camera)

	var key := DirectionalLight3D.new()
	key.rotation = Vector3(-0.75, -0.55, 0.0)
	key.light_energy = KEY_ENERGY
	add_child(key)

	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(0.4, 2.3, 0.0)
	fill.light_energy = 0.55
	fill.light_color = Color(0.72, 0.8, 1.0)
	add_child(fill)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.13, 0.15, 0.19)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.6, 0.65, 0.74)
	environment.ambient_light_energy = AMBIENT_ENERGY
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	var destination := OS.get_environment("SHAFT_SHOT")
	if destination.is_empty():
		printerr("set SHAFT_SHOT to the .png to write")
		get_tree().quit(1)
		return

	if not await _capture(destination):
		get_tree().quit(1)
		return

	_camera.position = COLLAR_FROM
	_camera.rotation = COLLAR_AIM
	var collar := "%s_collar.%s" % [destination.get_basename(), destination.get_extension()]
	if not await _capture(collar):
		get_tree().quit(1)
		return
	get_tree().quit()


func _capture(destination: String) -> bool:
	# Three frames, not one: the first presents before the meshes have been
	# through a draw and the capture comes back empty. The same holds after moving
	# the camera, so both shots pay it.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var error := get_viewport().get_texture().get_image().save_png(destination)
	if error != OK:
		printerr("could not write %s: %d" % [destination, error])
		return false
	print("wrote %s" % destination)
	return true


func _instance(path: String) -> Node3D:
	var scene := load(path) as PackedScene
	if scene == null:
		printerr("%s did not load" % path)
		get_tree().quit(1)
		return Node3D.new()
	var node := scene.instantiate() as Node3D
	add_child(node)
	return node


## A slab of stand-in rock the collar pierces, so the one thing the hood is for -
## hiding a hole in a ceiling - is the thing this shot actually shows. Not art:
## the real ceiling is carved out of level_mine_blockout.tscn.
##
## SEATED PART WAY UP THE COLLAR, not flush with its underside. Coplanar faces
## z-fight, and the first render of this came back with the flange dissolving into
## a dither. The rock in the level intersects the flange rather than meeting it,
## which is the case being reproduced here.
func _add_ceiling(shaft: ElevatorShaft) -> void:
	var opening := shaft.clear_bore() + 1.0
	var seat := shaft.hood_height + CEILING_SEAT
	for side: int in 4:
		var turn := side * PI * 0.5
		var basis := Basis(Vector3.UP, turn)
		var box := BoxMesh.new()
		box.size = Vector3(16.0, 1.4, (16.0 - opening) * 0.5)
		var out := basis * Vector3(0.0, 0.0, -(opening + box.size.z) * 0.5)
		_add_box(box, out + Vector3.UP * (seat + box.size.y * 0.5), turn, Color(0.26, 0.26, 0.28))


func _add_box(mesh: BoxMesh, at: Vector3, yaw: float, colour: Color) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.rotation.y = yaw
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 1.0
	instance.material_override = material
	add_child(instance)


func _add_ground() -> void:
	var plane := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(32.0, 32.0)
	plane.mesh = mesh
	plane.position.y = -0.24
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.22, 0.23, 0.26)
	material.roughness = 1.0
	plane.material_override = material
	add_child(plane)
