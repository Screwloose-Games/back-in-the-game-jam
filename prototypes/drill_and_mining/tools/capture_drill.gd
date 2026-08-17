extends Node

## Screenshots an ore node under several lighting conditions. NOT headless - it
## renders:
##
##     godot --path <root> res://prototypes/drill_and_mining/tools/capture_drill.tscn
##
## verify_drill.tscn can prove the field generates, the mesher closes, the
## release rule fires and the pool caps itself, all against rock that renders as
## flat black or inside out. It cannot tell you the rock looks like rock.
##
## The passes are a bisection, not a gallery. "Too dark" has several candidate
## causes that look identical in one screenshot - the fog, the lamp's reach, the
## shadows, and the material - so each pass removes exactly one of them and the
## first shot that brightens names the cause. That is not hypothetical: it is how
## a mirrored instance basis and an un-gamma-corrected instance colour were both
## found, each of which presented as the lamp being too dim.
##
## The CARVED passes matter most. An uncarved node is a ball, and a ball says
## nothing about whether a crater wall reads as cut rock - which is the whole
## question surface nets was chosen to answer.
##
## Writes PNGs to tools/_shots/.

const SCENE_PATH := "res://prototypes/drill_and_mining/drill_and_mining_prototype.tscn"

## Node 0 sits at (0, 0, -3). Every viewpoint is on it: this is about the rock,
## not about the room.
const NODE_CENTRE := Vector3(0.0, 0.0, -3.0)

## Where a player actually drills from - just outside the shell, well inside
## DRILL_RANGE.
const DRILL_FROM := Vector3(0.0, 0.2, -0.6)

## Far enough back to see a whole node against the room.
const STANDOFF_FROM := Vector3(0.0, 1.0, 3.0)

## The suit's own spawn, looking across the chamber. Answers the other half of
## "too dark": whether you can tell there are three more nodes out there without
## flying the room in a grid.
const ROOM_FROM := Vector3(0.0, 0.0, 8.0)
const ROOM_AT := Vector3(1.0, 0.5, -8.0)

var _camera: Camera3D
var _lamp: SpotLight3D
var _scene: Node
var _environment: Environment


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
	var hud := _scene.get_node_or_null("HUD") as CanvasLayer
	if hud != null:
		hud.visible = false
	_environment = (_scene.get_node("WorldEnvironment") as WorldEnvironment).environment

	_build_camera()
	var directory := _res("_shots")
	DirAccess.make_dir_recursive_absolute(directory)

	# 1. Untouched rock, and the room it sits in.
	await _capture(directory, "01_as_shipped", DRILL_FROM, NODE_CENTRE)
	await _capture(directory, "02_as_shipped_standoff", STANDOFF_FROM, NODE_CENTRE)
	await _capture(directory, "07_room", ROOM_FROM, ROOM_AT)

	# 2. CARVED, which is the only state that matters. An uncarved node is a ball
	#    and tells you nothing about whether a crater wall reads as cut rock -
	#    which is the whole question the mesher was chosen to answer.
	_drill_into(_scene.get_node_or_null("OreNode0") as OreNode)
	await _capture(directory, "08_bored", DRILL_FROM, NODE_CENTRE)
	await _capture(directory, "09_bored_standoff", STANDOFF_FROM, NODE_CENTRE)

	# 3. Fog off, to see how much of the murk is the fog rather than the lamp.
	_environment.fog_enabled = false
	await _capture(directory, "03_no_fog", DRILL_FROM, NODE_CENTRE)

	# 4. Lamp shadows off. A crater is a pit full of faces turned away from the
	#    lamp, which is the worst case for Compatibility's narrow shadow filter.
	_lamp.shadow_enabled = false
	await _capture(directory, "04_no_fog_no_shadows", DRILL_FROM, NODE_CENTRE)

	# 5. Flat white ambient and no lamp at all. This is the rock's albedo with
	#    nothing else in the way - if it is still wrong HERE, the material or the
	#    mesher's normals are the problem and no lighting will fix it.
	_lamp.visible = false
	_environment.ambient_light_color = Color.WHITE
	_environment.ambient_light_energy = 1.0
	await _capture(directory, "05_albedo_only", DRILL_FROM, NODE_CENTRE)
	await _capture(directory, "06_albedo_only_standoff", STANDOFF_FROM, NODE_CENTRE)

	print("wrote 8 shots to %s" % directory)
	get_tree().quit(0)


## A copy of the helmet lamp, not a stand-in for it. An omni of the same energy
## spreads over the whole sphere and comes back several stops darker than the
## 35-degree spot the player actually carries, which would report a lighting
## problem the prototype does not have.
func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.fov = 75.0
	_camera.near = 0.05
	_camera.far = DrillKnobs.CAMERA_FAR
	add_child(_camera)
	_camera.make_current()

	_lamp = SpotLight3D.new()
	_lamp.light_color = Color(1, 0.96, 0.89)
	_lamp.light_energy = DrillKnobs.HELMET_LAMP_ENERGY
	_lamp.spot_range = DrillKnobs.HELMET_LAMP_RANGE
	_lamp.spot_attenuation = 1.2
	_lamp.spot_angle = DrillKnobs.HELMET_LAMP_ANGLE
	_lamp.spot_angle_attenuation = 0.6
	_lamp.shadow_enabled = true
	_lamp.shadow_reverse_cull_face = DrillKnobs.SHADOW_REVERSE_CULL
	_lamp.shadow_normal_bias = DrillKnobs.SHADOW_NORMAL_BIAS
	_lamp.position = Vector3(0.14, -0.12, 0)
	_camera.add_child(_lamp)


## Cuts a bore straight into the node from where the camera stands, the way a
## player holding the trigger would - a sequence of carves marching inward, each
## repeated enough times that the field there has bottomed out.
func _drill_into(ore_node: OreNode) -> void:
	if ore_node == null:
		printerr("no OreNode0 to drill; the carved shots will be of untouched rock")
		return
	var aim := (NODE_CENTRE - DRILL_FROM).normalized()
	var travelled := DrillKnobs.NODE_RADIUS
	while travelled > DrillKnobs.CRYSTAL_RADIUS:
		for _pass in 30:
			ore_node.carve(
				NODE_CENTRE - aim * travelled, DrillKnobs.CARVE_RADIUS, DrillKnobs.CARVE_RATE / 60.0
			)
		travelled -= DrillKnobs.CARVE_RADIUS * 0.4
	ore_node.run_pending_work()


func _capture(directory: String, shot_name: String, from: Vector3, at: Vector3) -> void:
	_camera.global_transform = Transform3D(
		Basis.looking_at((at - from).normalized(), Vector3.UP), from
	)
	# Two frames, not one: the first is drawn with the previous transform still
	# in the render server, so every shot would come back one viewpoint stale.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(directory.path_join("%s.png" % shot_name))


func _res(relative_path: String) -> String:
	var dir: String = (get_script() as Script).resource_path.get_base_dir()
	return dir.path_join(relative_path).simplify_path()
