extends Node3D

## Renders the three props in the engine that ships them, and quits.
##
##   set PROPS_SHOT=C:\somewhere\props.png
##   D:\Godot_v4.7.1-stable_win64.exe --path <root> --resolution 1600x900 \
##     --rendering-driver opengl3 res://tools/voxel-props/preview_props.tscn
##
## Name the scene explicitly or the main menu boots instead. Not --headless:
## headless has no rendering device, so there is nothing to capture.
##
## Two things are only decided here. First, whether the indexed palette reaches
## the screen -- the rubble set passed every headless check while rendering flat
## white, and a swatch lookup that lands one texel out is the same class of
## failure. Magenta anywhere in this frame means a UV is wrong. Second, whether
## these read at the same scale and in the same idiom as the character, which is
## why the character is standing in the car rather than being described in a
## comment.

const CAR := "res://assets/art/environment/elevator_car/sm_elevator_car.gltf"
const SWITCH := "res://assets/art/environment/wall_switch/sm_wall_switch.gltf"
const LASER := "res://assets/art/gameplay/mining_laser/sm_mining_laser.gltf"
const CHARACTER := "res://assets/art/character/sk_player_character.gltf"

## How far each leaf slides. The container scene will animate position.x over
## this; showing the doors part-open here is what proves the leaves are separate
## nodes and that the shell behind them is finished rather than a hole.
const DOOR_TRAVEL := 0.66

## Ambient is generous on purpose, and for the opposite reason to the rubble
## preview: these props bake NO occlusion, so a hard key against a dark ambient
## renders the rig rather than the asset. If they read flat here they will read
## flat in the mine, which is a finding, not a lighting bug.
const AMBIENT_ENERGY := 0.85
const KEY_ENERGY := 1.5

## Two shots, because one cannot do both jobs. The wide frame is the scale
## check -- 1.56 m of character against a 1.92 m doorway -- and at that distance
## a 1.14 m hand tool is sixty pixels of frame, which is enough to see that it
## exists and not enough to see whether it reads. The detail frame is where the
## laser and the switch are actually judged.
const WIDE_FROM := Vector3(0.4, 3.1, 9.6)
const WIDE_AIM := Vector3(-0.16, 0.03, 0.0)
const DETAIL_FROM := Vector3(1.9, 1.55, 4.7)
const DETAIL_AIM := Vector3(-0.08, 0.12, 0.0)

var _camera: Camera3D


func _ready() -> void:
	# Every prop faces -Z, and a Godot camera looks down its OWN -Z -- so a
	# camera parked on +Z sees the back of anything left at yaw zero. Each prop
	# is turned about half a turn to present its front. Getting this wrong is
	# how the first render of this scene came back showing three blank panels.
	var car := _instance(CAR)
	car.position = Vector3(-2.9, 0.0, -1.4)
	car.rotation.y = PI - 0.36
	_slide_doors(car)

	# Standing in the doorway, facing out of it -- the scale check the whole
	# preview exists for. No rotation correction: the -90 degree X on the
	# character's node chain IS its Z-up conversion, so it arrives upright.
	var miner := _instance(CHARACTER)
	miner.rotation.y = PI - 0.36
	miner.position = car.position + Vector3(-0.55, 0.12, 1.62)

	# Near broadside. A 1.14 m tool seen down its own barrel is 0.30 m of
	# frame, so the profile is the view that says whether the silhouette works.
	var laser := _instance(LASER)
	laser.position = Vector3(1.7, 1.12, 2.5)
	laser.rotation = Vector3(0.0, PI / 2.0 + 0.16, 0.0)
	_add_plinth(Vector3(1.7, 0.0, 2.5), 1.0)

	var switch := _instance(SWITCH)
	switch.position = Vector3(3.6, 1.15, -1.4)
	switch.rotation.y = PI + 0.5
	_add_wall_stub(switch.position, switch.rotation.y)

	_add_ground()

	_camera = Camera3D.new()
	_camera.position = WIDE_FROM
	_camera.rotation = WIDE_AIM
	_camera.fov = 50.0
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

	var destination := OS.get_environment("PROPS_SHOT")
	if destination.is_empty():
		printerr("set PROPS_SHOT to the .png to write")
		get_tree().quit(1)
		return

	if not await _capture(destination):
		get_tree().quit(1)
		return

	_camera.position = DETAIL_FROM
	_camera.rotation = DETAIL_AIM
	var detail := "%s_detail.%s" % [destination.get_basename(), destination.get_extension()]
	if not await _capture(detail):
		get_tree().quit(1)
		return
	get_tree().quit()


func _capture(destination: String) -> bool:
	# Three frames, not one: the first presents before the meshes have been
	# through a draw and the capture comes back empty. The same holds after
	# moving the camera, so both shots pay it.
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


func _slide_doors(car: Node3D) -> void:
	for child in car.get_children():
		if child.name == "door_left":
			(child as Node3D).position.x = -DOOR_TRAVEL
		elif child.name == "door_right":
			(child as Node3D).position.x = DOOR_TRAVEL


## A bench for the laser and a wall for the switch. Neither is art -- they are
## here so the two props that do not stand on the floor are shown doing what
## their origin says they do, which is the only check on either.
func _add_plinth(at: Vector3, height: float) -> void:
	var box := BoxMesh.new()
	box.size = Vector3(1.4, height, 0.9)
	_add_box(box, at + Vector3(0.0, height / 2.0, 0.0), 0.0, Color(0.3, 0.31, 0.34))


func _add_wall_stub(at: Vector3, yaw: float) -> void:
	var box := BoxMesh.new()
	box.size = Vector3(2.6, 3.0, 0.24)
	var behind := Vector3(sin(yaw), 0.0, cos(yaw)) * 0.13
	_add_box(box, Vector3(at.x, 1.5, at.z) + behind, yaw, Color(0.28, 0.29, 0.32))


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
	mesh.size = Vector2(24.0, 24.0)
	plane.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.22, 0.23, 0.26)
	material.roughness = 1.0
	plane.material_override = material
	add_child(plane)
