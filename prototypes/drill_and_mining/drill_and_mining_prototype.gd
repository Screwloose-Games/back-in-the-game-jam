class_name DrillAndMiningPrototype
extends Node3D

## Stage 1 of the drill: a room, four ore nodes, and a beam that eats rock.
##
## Assembles everything and owns every setter the tuning panel reaches through.
## The chamber is in the .tscn; the suit, the beam, the collector, the debris
## pool and the ore nodes are all built here, because what they are made of comes
## from drill_knobs.gd and a scene file cannot read a const.
##
## WHAT THIS STAGE DOES NOT HAVE: power draw, the lamp as anything but light,
## sound, a creature, and anywhere to take a crystal once you have it. All of
## those are later stages and each arrives as a switch in the knobs file.

const SUIT_SCENE := preload("res://prototypes/drill_and_mining/imported/drill_suit.tscn")

## Drill feel and murk you can move from the tuning panel, and what SAVE writes
## back to. Assigned in the .tscn; see _ready for what happens when it is missing.
@export var settings: DrillSettings

var _suit: DrillSuit
var _beam: DrillBeam
var _debris_pool: OreDebrisPool
var _ore_nodes: Array[OreNode] = []
var _collector_shape: SphereShape3D

## Freed crystals currently inside the collector. Only used when collection is
## on a key rather than on touch; on touch a crystal never stays in it long
## enough to be listed.
var _crystals_in_reach: Array[RigidBody3D] = []
var _collected := 0

@onready var _world_environment: WorldEnvironment = $WorldEnvironment
@onready var _hud: DrillHud = $HUD
@onready var _tuning: PrototypeTuningPanel = $HUD/Tuning


func _ready() -> void:
	# A fresh clone has no drill_settings.tres yet, and anyone may delete it. A
	# bare instance holds exactly the knobs consts, so the fallback is the
	# ordinary behaviour rather than a crash.
	if settings == null:
		settings = DrillSettings.new()
		push_warning("No drill_settings.tres wired; running on drill_knobs.gd defaults.")
	settings.changed.connect(_apply_settings)

	_register_input()
	_build_debris_pool()
	_build_ore_nodes()
	_spawn_suit()

	_hud.bind(_suit, _beam, _debris_pool, _ore_nodes.size())
	_hud.set_collected(0)
	_tuning.bind(settings)
	_apply_settings()
	_report()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("reset_player"):
		# The suit handles this in its own _input and neither of us marks the
		# event handled, so one key both respawns you and puts the rock back.
		_rebuild_field()
	elif DrillKnobs.COLLECT_REQUIRES_KEY and event.is_action_pressed("grab"):
		_collect_nearest()


## Runs once at startup and again on every change from the tuning panel, so "it
## took effect while flying" and "it took effect on the next run" are the same
## code path rather than two that can drift apart.
##
## Writes nothing back to `settings`; doing so would re-enter `changed`.
func _apply_settings() -> void:
	var scene_environment := _world_environment.environment
	scene_environment.fog_depth_begin = DrillKnobs.FOG_DEPTH_BEGIN
	scene_environment.fog_depth_end = settings.fog_depth_end
	scene_environment.fog_density = DrillKnobs.FOG_DENSITY
	scene_environment.fog_light_color = DrillKnobs.FOG_LIGHT_COLOR
	scene_environment.ambient_light_color = DrillKnobs.AMBIENT_COLOR
	scene_environment.ambient_light_energy = settings.ambient_energy

	if _suit != null:
		_suit.set_camera_far(settings.camera_far)
		_suit.set_lamp(
			DrillKnobs.HELMET_LAMP_RANGE,
			DrillKnobs.HELMET_LAMP_ANGLE,
			DrillKnobs.HELMET_LAMP_ENERGY
		)
		_suit.set_lamp_shadows(DrillKnobs.SHADOW_REVERSE_CULL, DrillKnobs.SHADOW_NORMAL_BIAS)
	if _beam != null:
		_beam.apply_tuning(
			settings.carve_rate,
			settings.carve_radius,
			settings.drill_range,
			settings.debris_spawn_rate
		)
	if _debris_pool != null:
		_debris_pool.apply_tuning(settings.debris_knock, settings.debris_lifetime)
	if _collector_shape != null:
		_collector_shape.radius = settings.collect_radius
	for ore_node: OreNode in _ore_nodes:
		ore_node.apply_tuning(settings.escape_clearance)

	for failure: String in settings.invariant_failures():
		push_warning("drill_settings: %s" % failure)


# --- Assembly --------------------------------------------------------------


## Adds the drill binding to the running InputMap.
##
## Nothing is written back to project.godot. That file is shared with the game
## and with every other prototype, and this one may not outlive the week; the
## power prototype set the precedent and the reason is the same.
func _register_input() -> void:
	if InputMap.has_action(DrillKnobs.DRILL_ACTION):
		return
	InputMap.add_action(DrillKnobs.DRILL_ACTION)
	var trigger := InputEventMouseButton.new()
	trigger.button_index = DrillKnobs.DRILL_MOUSE_BUTTON
	InputMap.action_add_event(DrillKnobs.DRILL_ACTION, trigger)


func _build_debris_pool() -> void:
	_debris_pool = OreDebrisPool.new()
	_debris_pool.name = "Debris"
	add_child(_debris_pool)


func _build_ore_nodes() -> void:
	for index in DrillKnobs.ORE_NODES.size():
		var entry: Dictionary = DrillKnobs.ORE_NODES[index]
		var ore_node := OreNode.new()
		ore_node.name = "OreNode%d" % index
		ore_node.position = entry["position"]
		ore_node.debris_pool = _debris_pool
		add_child(ore_node)
		ore_node.build(entry["seed"], entry["hardness"], settings.escape_clearance)
		ore_node.crystal_freed.connect(_on_crystal_freed)
		_ore_nodes.append(ore_node)
	if _beam != null:
		_beam.ore_nodes = _ore_nodes


func _spawn_suit() -> void:
	_suit = SUIT_SCENE.instantiate() as DrillSuit
	_suit.name = "DrillSuit"
	_suit.position = DrillKnobs.SUIT_SPAWN
	add_child(_suit)

	_beam = DrillBeam.new()
	_beam.name = "DrillBeam"
	_beam.ore_nodes = _ore_nodes
	_beam.debris_pool = _debris_pool
	# Under the camera, so the beam's own local space is already aim space.
	_suit.get_head_camera().add_child(_beam)

	_build_collector()


## The pickup, on the suit rather than on each crystal.
##
## One area and one signal instead of four of each - but the real reason is the
## mask. It watches CRYSTAL_LAYER, and a crystal only reaches that layer when its
## node lets go of it, so an embedded crystal cannot be collected by flying at
## it. Nothing checks a flag, so nothing can forget to.
##
## On the body rather than under the camera: how far you can reach is a fact
## about the suit, not about where you happen to be looking.
func _build_collector() -> void:
	_collector_shape = SphereShape3D.new()
	_collector_shape.radius = DrillKnobs.COLLECT_RADIUS
	var collider := CollisionShape3D.new()
	collider.shape = _collector_shape

	var collector := Area3D.new()
	collector.name = "CrystalCollector"
	collector.collision_layer = 0
	collector.collision_mask = DrillKnobs.CRYSTAL_LAYER
	collector.add_child(collider)
	collector.body_entered.connect(_on_crystal_in_reach)
	collector.body_exited.connect(_on_crystal_out_of_reach)
	_suit.add_child(collector)


# --- The loop --------------------------------------------------------------


func _on_crystal_freed(ore_node: OreNode) -> void:
	_hud.show_notice("a crystal is loose - go and get it")
	# Nothing is scored here. Cutting it out and collecting it are two separate
	# beats on purpose: in zero-G the crystal drifts, so the second one is a
	# chase and is worth being able to fail.
	if ore_node == null:
		push_warning("crystal_freed fired with no node")


func _on_crystal_in_reach(body: Node3D) -> void:
	var crystal := body as RigidBody3D
	if crystal == null:
		return
	if DrillKnobs.COLLECT_REQUIRES_KEY:
		if not _crystals_in_reach.has(crystal):
			_crystals_in_reach.append(crystal)
		_hud.show_notice("press F to take it")
		return
	_collect(crystal)


func _on_crystal_out_of_reach(body: Node3D) -> void:
	var crystal := body as RigidBody3D
	if crystal != null:
		_crystals_in_reach.erase(crystal)


func _collect_nearest() -> void:
	while not _crystals_in_reach.is_empty():
		var crystal: RigidBody3D = _crystals_in_reach.pop_front()
		if is_instance_valid(crystal):
			_collect(crystal)
			return


func _collect(crystal: RigidBody3D) -> void:
	_crystals_in_reach.erase(crystal)
	_collected += 1
	_hud.set_collected(_collected)
	crystal.queue_free()
	if _collected >= _ore_nodes.size():
		_hud.show_notice("all %d collected - TAB puts the rock back" % _collected)
	else:
		_hud.show_notice("crystal collected")


## Puts every node back as it was, on the same seeds, and clears the room.
##
## The nodes come out of the tree before they are freed rather than being left to
## queue_free on their own: a freed node's collision is still on the ore layer
## for the rest of the frame, and the replacements stand in exactly the same
## place. The beam does not care - it walks fields, not shapes - but the suit
## flying through the room does.
func _rebuild_field() -> void:
	for ore_node: OreNode in _ore_nodes:
		remove_child(ore_node)
		ore_node.queue_free()
	_ore_nodes.clear()
	_crystals_in_reach.clear()
	_debris_pool.clear()
	_collected = 0
	_build_ore_nodes()
	_hud.set_collected(0)
	_apply_settings()


## One line at startup saying what was actually built, and a hard error for the
## one generation failure that would otherwise be silent.
func _report() -> void:
	var half_extent := DrillKnobs.FIELD_RESOLUTION * DrillKnobs.VOXEL_SIZE * 0.5
	var widest_rock := DrillKnobs.NODE_RADIUS + DrillKnobs.NODE_SURFACE_NOISE
	if widest_rock >= half_extent:
		push_error(
			(
				"NODE_RADIUS + NODE_SURFACE_NOISE is %.2f m against a field half-extent of %.2f m; nodes are clipped flat where the rock meets the edge of the grid"
				% [widest_rock, half_extent]
			)
		)
	var corners := (DrillKnobs.FIELD_RESOLUTION + 1) ** 3
	print(
		(
			"drill and mining: %d nodes, %d^3 cells at %.2f m each (%d corners a node), %.2f m/s carve"
			% [
				_ore_nodes.size(),
				DrillKnobs.FIELD_RESOLUTION,
				DrillKnobs.VOXEL_SIZE,
				corners,
				settings.carve_rate,
			]
		)
	)
