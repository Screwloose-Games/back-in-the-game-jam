class_name TunnelSystemPrototype
extends Node3D

## Root of the tunnel system prototype.
##
## Assembles the three generated halves - the editable Path3D layout, the baked
## cave shell, and the player - and pushes every value from tunnel_knobs.gd onto
## the scene at startup, so the .tscn never holds a second copy of a number that
## could drift.
##
##   godot --path <root> res://prototypes/tunnel_system/tunnel_system_prototype.tscn
##
## Name the scene. The project's main scene is the main menu, so anything that
## does not name a scene boots that instead.

const PLAYER_SCENE := "res://prototypes/navigation/zero_g_player.tscn"

## The optics you can move from the tuning panel, and what SAVE writes back to.
## Assigned in the .tscn; see _ready for what happens when it is missing.
@export var settings: TunnelSettings

var network: TunnelNetwork

var _player: ZeroGPlayer

@onready var _paths_root: Node3D = $Paths/Paths
@onready var _chambers_root: Node3D = $Paths/Chambers
@onready var _world_environment: WorldEnvironment = $WorldEnvironment
@onready var _hud: TunnelHud = $Hud


func _ready() -> void:
	# A fresh clone has no tunnel_settings.tres yet, and anyone may delete it. A
	# bare instance holds exactly the knobs consts, so the fallback is the old
	# behaviour rather than a crash.
	if settings == null:
		settings = TunnelSettings.new()
		push_warning("No tunnel_settings.tres wired; running on tunnel_knobs.gd defaults.")
	settings.changed.connect(_apply_settings)

	network = TunnelNetwork.from_scene(_paths_root, _chambers_root)
	# Before the settings, because _apply_settings reaches into the player's
	# camera and lamp and there has to be a player for it to reach into.
	_spawn_player()
	_apply_settings()
	if TunnelKnobs.JUNCTION_BEACONS:
		_build_beacons()
	_hud.bind(self, _player, settings)
	_report()


## Sets how far you can see, in metres, and moves everything that governs it.
##
## ONE NUMBER, THREE PROPERTIES. Moving the fog alone changes nothing you can
## perceive - past the lamp's throw the rock is lit by ambient alone and reads as
## black however clear the air is - and a clip plane inside the fog pops geometry
## out before the fog has hidden it. So the fog end, the lamp throw and the far
## plane are one value with two fixed offsets, and the slider is labelled in the
## only unit that means anything to a player.
func set_view_distance(metres: float) -> void:
	var distance := clampf(metres, TunnelKnobs.VIEW_DISTANCE_MIN, TunnelKnobs.VIEW_DISTANCE_MAX)
	_world_environment.environment.fog_depth_end = distance
	if _player == null:
		return
	var lamp := _player.get_node("HeadCamera/HelmetLamp") as SpotLight3D
	lamp.spot_range = distance + TunnelKnobs.VIEW_LAMP_MARGIN
	var camera := _player.get_node("HeadCamera") as Camera3D
	camera.far = distance + TunnelKnobs.VIEW_CLIP_MARGIN


## Half-angle of the helmet lamp cone in degrees, so 45 is a 90 degree spread.
func set_lamp_angle(degrees: float) -> void:
	if _player == null:
		return
	var lamp := _player.get_node("HeadCamera/HelmetLamp") as SpotLight3D
	lamp.spot_angle = clampf(degrees, TunnelKnobs.LAMP_ANGLE_MIN, TunnelKnobs.LAMP_ANGLE_MAX)


## Drops the player at a teleport stop, at rest and facing the tunnel.
##
## Velocity and tumble are both cleared. Arriving at a 2 m bore still carrying
## the speed you built up in an 8 m trunk means the first thing the new size does
## is bounce you off a wall, which is a fact about the transition rather than
## about the size you came to look at.
func jump_to_stop(index: int) -> void:
	if _player == null or index < 0 or index >= TunnelKnobs.TELEPORT_STOPS.size():
		return
	var stop: Dictionary = TunnelKnobs.TELEPORT_STOPS[index]
	var position: Vector3 = stop["position"]
	var heading: Vector3 = (stop["look_at"] as Vector3) - position
	_player.velocity = Vector3.ZERO
	_player.angular_velocity = Vector3.ZERO
	_player.global_transform = Transform3D(
		Basis.looking_at(heading.normalized(), _reference_up(heading)), position
	)


## Basis.looking_at fails when its up vector is parallel to the direction, and
## both shafts in this level are close to vertical.
func _reference_up(direction: Vector3) -> Vector3:
	if absf(direction.normalized().dot(Vector3.UP)) > 0.99:
		return Vector3.BACK
	return Vector3.UP


## Every live-tunable value, pushed onto the scene.
##
## Runs once at startup and again on every change from the tuning panel, so
## "it took effect while flying" and "it took effect on the next run" are the
## same code path rather than two that can drift apart.
##
## NOTHING IN HERE WRITES BACK TO `settings`. set_view_distance clamps the value
## it applies without storing the clamp, so this cannot re-enter `changed`.
func _apply_settings() -> void:
	var environment := _world_environment.environment
	environment.ambient_light_energy = settings.ambient_energy
	environment.fog_density = settings.fog_density
	environment.fog_depth_begin = TunnelKnobs.FOG_DEPTH_BEGIN
	set_view_distance(settings.view_distance)
	set_lamp_angle(settings.helmet_lamp_angle)
	if _player != null:
		var lamp := _player.get_node("HeadCamera/HelmetLamp") as SpotLight3D
		lamp.shadow_enabled = settings.helmet_lamp_shadows


## The player is instantiated and POSITIONED BEFORE being added to the tree, not
## placed as a node in the .tscn.
##
## ZeroGPlayer captures its respawn pose in its own _ready, and a child's _ready
## runs before its parent's - so moving it from here after the fact would leave R
## teleporting the player back to wherever the .tscn happened to put them. Setting
## the transform first means add_child triggers _ready on a player already in the
## right place, and the spawn stays a single value in tunnel_knobs.gd.
func _spawn_player() -> void:
	var scene := load(PLAYER_SCENE) as PackedScene
	if scene == null:
		push_error("could not load %s" % PLAYER_SCENE)
		return
	_player = scene.instantiate() as ZeroGPlayer
	_player.name = "ZeroGPlayer"
	_player.transform = Transform3D(
		Basis.looking_at(
			(TunnelKnobs.SPAWN_LOOK_AT - TunnelKnobs.SPAWN_POSITION).normalized(), Vector3.UP
		),
		TunnelKnobs.SPAWN_POSITION
	)
	add_child(_player)

	# The player scene belongs to the navigation prototype and reads THAT
	# prototype's knobs in its own _ready. Every value this scene cares about is
	# re-applied here, after add_child, so the navigation prototype's numbers never
	# govern this one.
	#
	# Overriding on the instance rather than copying the player keeps this
	# directory from forking a 200-line controller and its whole movement tuning
	# table - the movement is meant to feel identical, it is only the optics that
	# differ. Nothing outside prototypes/tunnel_system/ is modified.
	# The optics are not set here: _apply_settings runs next and owns every one of
	# them, so there is a single owner and the sliders cannot fight the startup
	# values. It also derives throw and clip distance from the one view-distance
	# number rather than letting three properties disagree.


## An emissive dot at every junction where three or more routes meet.
##
## Sixteen routes of identical rock behind twelve metres of fog, with no up and no
## down, means the player is thoroughly lost inside two minutes - and that single
## finding would drown every other finding this prototype exists to produce.
## ld0-asteroid.md lists "landmarks that survive having no up or down" as a hard
## requirement for the same reason.
##
## One MultiMeshInstance3D, one unshaded material, per-instance colour: fifteen
## landmarks for one draw call.
func _build_beacons() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = TunnelKnobs.BEACON_SIZE
	sphere.height = TunnelKnobs.BEACON_SIZE * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4

	var placed: Array[int] = []
	for index: int in network.junctions.size():
		if network.junction_degree(index) >= 3:
			placed.append(index)
	if placed.is_empty():
		return

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = sphere
	multimesh.instance_count = placed.size()
	for slot: int in placed.size():
		var junction := network.junctions[placed[slot]]
		multimesh.set_instance_transform(slot, Transform3D(Basis.IDENTITY, junction))
		multimesh.set_instance_color(
			slot, Color.from_hsv(fmod(float(placed[slot]) * 0.37, 1.0), 0.7, 1.0)
		)

	var node := MultiMeshInstance3D.new()
	node.name = "JunctionBeacons"
	node.multimesh = multimesh
	node.material_override = load("res://prototypes/tunnel_system/materials/junction_beacon.tres")
	add_child(node)


func _report() -> void:
	print(
		(
			"tunnel system: %d routes, %d junctions, %.0f m of centreline, spawn at %v"
			% [
				network.routes.size(),
				network.junctions.size(),
				network.total_length(),
				TunnelKnobs.SPAWN_POSITION,
			]
		)
	)
