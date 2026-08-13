class_name PerceptionSandbox
extends Node3D

## A room, a wall, a stand-in player and one creature that only perceives.
##
## It exists because the section 30 overlay cannot be unit-tested -- every geometric
## assertion in tests/ passes against a debug draw that renders as nothing at all.
## Looking at it is the only check, so there has to be somewhere to look.
##
## The creature does not move, hunt, or react. That is the point: everything on
## screen is perception and nothing else, so anything wrong is wrong HERE.
##
##     WASD / QE   move the stand-in player
##     1 / 2       emit a quiet / loud noise at the player
##     3           request an activity scan around the player
##     4           request a geometry scan around the player
##     V           toggle vision
##     G           toggle passive geometry perception
##     [ / ]       lower / raise alertness
##     Tab         toggle the overlay
##
## The walls are built in code rather than saved into the .tscn on purpose. The
## editor rewrites relative ext_resource paths to absolute ones on every re-save,
## and a generated room cannot drift from the numbers this file documents.

## Layer 1 is "hull" in project.godot, which is what PerceptionConfig.world_mask
## defaults to. Putting the walls anywhere else makes the creature deaf and blind
## with nothing in the log.
const WALL_LAYER: int = 1
const MOVE_SPEED: float = 6.0
const ROOM := Vector3(24.0, 6.0, 24.0)
## Splits the room, with a doorway, so line of sight can actually be broken.
const DIVIDER_THICKNESS: float = 0.6
const DOORWAY_WIDTH: float = 3.0

@export var quiet_loudness: float = 0.25
@export var loud_loudness: float = 1.0

var _perception: CreaturePerception = null
var _player: Node3D = null
var _overlay: PerceptionDebugDraw = null
var _panel: PerceptionDebugPanel = null
var _alertness: float = 1.0


func _ready() -> void:
	_build_room()
	_player = _build_player()
	_perception = _build_creature()
	_build_debug()
	_build_camera()
	_perception.set_alertness_context(_alertness)


func _process(delta: float) -> void:
	_drive_player(delta)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_1:
			_emit_noise(quiet_loudness, &"footstep")
		KEY_2:
			_emit_noise(loud_loudness, &"drill")
		KEY_3:
			_perception.request_activity_scan(
				_around_player(_perception.config.search_scan_radius), 1.0
			)
		KEY_4:
			_perception.request_geometry_scan(
				_around_player(_perception.config.geometry_validation_radius),
				CreatureGeometryPerception.GeometryScanReason.PATH_BLOCKED
			)
		KEY_V:
			_perception.vision.enabled = not _perception.vision.enabled
		KEY_G:
			var config := _perception.config
			config.geometry_perception_enabled = not config.geometry_perception_enabled
		KEY_BRACKETLEFT:
			_set_alertness(_alertness - 0.25)
		KEY_BRACKETRIGHT:
			_set_alertness(_alertness + 0.25)
		KEY_TAB:
			_overlay.visible = not _overlay.visible
			_panel.visible = _overlay.visible


func _set_alertness(value: float) -> void:
	_alertness = clampf(value, 0.0, 1.0)
	_perception.set_alertness_context(_alertness)


func _emit_noise(loudness: float, category: StringName) -> void:
	# Straight into the creature, because nothing in this project emits NoiseEvents
	# yet. A real emitter arrives with the systems that make noise; the shape of the
	# call does not change.
	_perception.receive_noise(
		NoiseEvent.make(_player.global_position, loudness, category, _player, _player)
	)


func _around_player(radius: float) -> AABB:
	return AABB(_player.global_position - Vector3.ONE * radius, Vector3.ONE * radius * 2.0)


func _drive_player(delta: float) -> void:
	# Raw keys rather than InputMap actions: this scene must run in a clone where
	# nobody has added perception_* actions to project.godot, and registering them at
	# runtime would be a lot of machinery for a debug room.
	var move := Vector3.ZERO
	move.x = float(int(Input.is_key_pressed(KEY_D)) - int(Input.is_key_pressed(KEY_A)))
	move.z = float(int(Input.is_key_pressed(KEY_S)) - int(Input.is_key_pressed(KEY_W)))
	move.y = float(int(Input.is_key_pressed(KEY_E)) - int(Input.is_key_pressed(KEY_Q)))
	if move.length_squared() > 0.0:
		_player.global_position += move.normalized() * MOVE_SPEED * delta


# ----- construction -----


func _build_room() -> void:
	var half := ROOM * 0.5
	_add_wall(Vector3(0, -0.5, 0), Vector3(ROOM.x, 1.0, ROOM.z))
	_add_wall(Vector3(0, ROOM.y + 0.5, 0), Vector3(ROOM.x, 1.0, ROOM.z))
	_add_wall(Vector3(-half.x, half.y, 0), Vector3(1.0, ROOM.y, ROOM.z))
	_add_wall(Vector3(half.x, half.y, 0), Vector3(1.0, ROOM.y, ROOM.z))
	_add_wall(Vector3(0, half.y, -half.z), Vector3(ROOM.x, ROOM.y, 1.0))
	_add_wall(Vector3(0, half.y, half.z), Vector3(ROOM.x, ROOM.y, 1.0))

	# The divider, in two pieces with a doorway between them. Without something to
	# hide behind, every line-of-sight colour on the overlay stays the same green
	# forever and the cone tells you nothing.
	var wing: float = (ROOM.z - DOORWAY_WIDTH) * 0.5
	var offset: float = (DOORWAY_WIDTH + wing) * 0.5
	_add_wall(Vector3(0, half.y, -offset), Vector3(DIVIDER_THICKNESS, ROOM.y, wing))
	_add_wall(Vector3(0, half.y, offset), Vector3(DIVIDER_THICKNESS, ROOM.y, wing))


func _add_wall(centre: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = WALL_LAYER
	body.collision_mask = 0
	body.position = centre

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)

	var view := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	view.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.30, 0.31, 0.34)
	view.material_override = material
	body.add_child(view)

	add_child(body)


func _build_player() -> Node3D:
	var player := Node3D.new()
	player.name = "StandIn"
	player.position = Vector3(6, 2, 0)
	# The group CreaturePerception falls back to when `targets` is not wired -- so
	# this scene also exercises the fallback rather than only the explicit path.
	player.add_to_group(&"perceivable")

	var view := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.height = 1.8
	capsule.radius = 0.4
	view.mesh = capsule
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.95, 0.75, 0.25)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	view.material_override = material
	player.add_child(view)

	add_child(player)
	return player


func _build_creature() -> CreaturePerception:
	var creature := CreaturePerception.new()
	creature.name = "CreaturePerception"
	creature.position = Vector3(-8, 2, 0)
	# Looking along +X, at the divider and the far half of the room.
	creature.rotation = Vector3(0.0, -PI * 0.5, 0.0)
	creature.config = PerceptionConfig.new()
	add_child(creature)

	var view := MeshInstance3D.new()
	var body := SphereMesh.new()
	body.radius = 0.5
	body.height = 1.0
	view.mesh = body
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.55, 0.25, 0.60)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	view.material_override = material
	creature.add_child(view)
	return creature


func _build_debug() -> void:
	_overlay = PerceptionDebugDraw.new()
	_overlay.perception = _perception
	add_child(_overlay)

	var layer := CanvasLayer.new()
	add_child(layer)
	_panel = PerceptionDebugPanel.new()
	_panel.perception = _perception
	_panel.debug_draw = _overlay
	_panel.position = Vector2(12, 12)
	layer.add_child(_panel)


func _build_camera() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0, 26, 20)
	camera.rotation = Vector3(deg_to_rad(-52.0), 0.0, 0.0)
	camera.current = true
	add_child(camera)

	# Flat colour background and a colour ambient source. Every other environment
	# feature this project might want (SDFGI, SSAO, SSIL, SSR, volumetric fog) is
	# silently unsupported on the GL Compatibility renderer -- they do not error,
	# they simply never appear.
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.06, 0.06, 0.09)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.55, 0.62)
	environment.ambient_light_energy = 1.0
	world.environment = environment
	add_child(world)
