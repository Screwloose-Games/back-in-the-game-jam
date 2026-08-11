class_name CoreLoopPrototype
extends Node3D

## The whole loop in one scene: fly the tunnels, haul the cube, keep the power
## moving, mine the crystals, and deal with what the noise brings.
##
## Five prototypes each answered one question on its own. This one asks whether
## they add up to something worth playing, which is a question none of them can be
## asked separately - the drill is only interesting if running it is dangerous,
## and the creature is only interesting if you have a reason to stand still.
##
## WHERE THE TUNING LIVES. This prototype's own nodes default their exports to
## CoreLoopKnobs, so there is nothing to push onto them and nothing that can be
## readied in the wrong order. What _apply_settings pushes is the tuning for the
## scenes it borrows, which know nothing about CoreLoopKnobs and would otherwise
## run at values chosen for a different room.

const SUIT_SCENE := preload("res://prototypes/core_loop/imported/core_loop_suit.tscn")

## Every value the tuning panel can move, and what SAVE writes back to. Assigned
## in the .tscn; see _ready for a missing one.
@export var settings: CoreLoopSettings

var _suit: CoreLoopSuit
var _cube: LifeSupportCube
var _suit_store: PowerStore
var _power: CoreLoopPowerSystem
var _suit_lamp_response: LampPowerResponse
var _cube_lamp_response: LampPowerResponse
var _beam: CoreLoopDrillBeam
var _debris_pool: OreDebrisPool
var _ore_nodes: Array[OreNode] = []
var _collector_shape: SphereShape3D
var _collected := 0
var _navigation_ready := false
var _noise: CoreLoopNoise

@onready var _world_environment: WorldEnvironment = $WorldEnvironment
@onready var _tunnels: CoreLoopTunnels = $Tunnels
@onready var _navigation: WallNavmeshBaker = $Navigation
@onready var _crawler: CrawlerBody = $Crawler
@onready var _tentacles: TentacleArray = $Crawler/Tentacles
@onready var _creature_light: OmniLight3D = $Crawler/CreatureLight
@onready var _contact: CreatureContact = $Crawler/CreatureContact
@onready var _follower: ChaseTargetFollower = $ChaseTargetFollower
@onready var _director: MonsterDirector = $MonsterDirector
@onready var _hud: CoreLoopHud = $HUD
@onready var _tuning: PrototypeTuningPanel = $HUD/Tuning


func _ready() -> void:
	# A fresh clone has no core_loop_settings.tres yet, and anyone may delete it.
	# A bare instance holds exactly the knobs consts, so the fallback is the
	# documented behaviour rather than a crash.
	if settings == null:
		settings = CoreLoopSettings.new()
		push_warning("No core_loop_settings.tres wired; running on core_loop_knobs.gd defaults.")
	settings.changed.connect(_apply_settings)

	_register_input()
	_apply_draw_distance()
	_build_debris_pool()
	_build_ore_nodes()
	_spawn_suit()
	_spawn_cube()
	_build_power()
	_build_noise()
	_apply_settings()
	_hud.bind(_suit, _beam, _power, _suit_store, _cube.get_store(), _noise, _director)
	_hud.set_score(_collected, _ore_nodes.size())
	_tuning.bind(settings)
	await _bake_navigation()
	# Only now: the director paths against the navigation map, and a spawn rolled
	# before the mesh is live picks a point it cannot measure a route to.
	_director.bind(_suit, _navigation.get_navigation_map())


func _physics_process(_delta: float) -> void:
	# Polled rather than handled in _input: cranking is a held gesture, and it has
	# to stop the frame the key comes up rather than on the next event.
	_power.set_crank_engaged(Input.is_action_pressed(CoreLoopKnobs.CRANK_ACTION))


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("reset_player"):
		# The suit handles this key for itself. Everything else in the experiment
		# is reset here, so one press restarts the whole run rather than leaving
		# the cube wherever the last attempt abandoned it.
		_reset()


## The suit the player is wearing, for whatever needs to measure against it.
func get_suit() -> CoreLoopSuit:
	return _suit


## The life support cube.
func get_cube() -> LifeSupportCube:
	return _cube


## The suit's battery. Also what the drill spends out of.
func get_suit_store() -> PowerStore:
	return _suit_store


func get_power_system() -> CoreLoopPowerSystem:
	return _power


## Runs once at startup and again on every change from the tuning panel, so "it
## took effect while being chased" and "it took effect on the next run" are the
## same code path rather than two that can drift apart.
##
## MUST NOT WRITE BACK TO `settings`, or it re-enters `changed`.
func _apply_settings() -> void:
	_suit.max_speed = settings.max_speed
	_beam.apply_tuning(
		settings.carve_rate,
		settings.carve_radius,
		CoreLoopKnobs.DRILL_RANGE,
		CoreLoopKnobs.DEBRIS_SPAWN_RATE,
		settings.drill_power_per_second
	)
	_debris_pool.apply_tuning(CoreLoopKnobs.DEBRIS_KNOCK, CoreLoopKnobs.DEBRIS_LIFETIME)
	# Through the shape, not the Area3D: the sphere is built once and writing a
	# radius anywhere else would leave the reach at its startup size.
	_collector_shape.radius = CoreLoopKnobs.COLLECT_RADIUS
	for ore_node: OreNode in _ore_nodes:
		ore_node.apply_tuning(CoreLoopKnobs.ESCAPE_CLEARANCE)

	# The creature arrives tuned for a 244 m corridor it shared with nothing. The
	# masks are the ones that matter: both default to hull|prop, and in THIS
	# project layer 2 is the player - so untouched, the body probe reads the player
	# as a wall to swerve away from and the tentacles try to take a grip on one.
	_crawler.max_speed = settings.creature_max_speed
	_crawler.leash_slack = CoreLoopKnobs.CREATURE_LEASH_SLACK
	_crawler.probe_comfort = CoreLoopKnobs.CREATURE_PROBE_COMFORT
	_crawler.probe_mask = CoreLoopKnobs.CREATURE_PROBE_MASK
	_tentacles.query_mask = CoreLoopKnobs.CREATURE_TENTACLE_MASK
	_follower.move_speed = CoreLoopKnobs.FOLLOWER_SPEED
	_follower.clearance_radius = CoreLoopKnobs.FOLLOWER_CLEARANCE
	# Through the setter, not the property: the catch sphere is built once and
	# writing the number alone would leave the reach at its startup size.
	_contact.set_catch_radius(settings.catch_radius)

	_creature_light.light_color = CoreLoopKnobs.CREATURE_LIGHT_COLOR
	_creature_light.light_energy = CoreLoopKnobs.CREATURE_LIGHT_ENERGY
	_creature_light.omni_range = CoreLoopKnobs.CREATURE_LIGHT_RANGE
	_creature_light.omni_attenuation = CoreLoopKnobs.CREATURE_LIGHT_ATTENUATION
	_creature_light.shadow_enabled = CoreLoopKnobs.CREATURE_LIGHT_SHADOWS

	_director.spawn_chance_per_second = settings.spawn_chance_per_second
	_director.chase_trigger_radius = settings.chase_trigger_radius
	_director.chase_duration = settings.chase_duration
	_director.despawn_silence = settings.despawn_silence

	_noise.drill_radius = settings.drill_noise_radius
	_noise.crank_radius = settings.drill_noise_radius
	_noise.thrust_radius = settings.thrust_noise_radius

	for failure: String in settings.invariant_failures():
		push_warning("core_loop_settings: %s" % failure)


## Cranking gets its own key, and that is a deliberate departure from the power
## and lighting prototype.
##
## That one splits tap-grip from hold-crank on F by ERASING every event from the
## project's `grab` action at runtime and re-synthesising it through
## Input.action_press, with a physics priority chosen to make the ordering work.
## It gets away with it because nothing else in that scene wants the key. Here the
## drill and the crystal collector both do, so the gesture that would have to be
## disambiguated is simply given a binding of its own and `grab` is left alone.
func _register_input() -> void:
	if not InputMap.has_action(CoreLoopKnobs.CRANK_ACTION):
		InputMap.add_action(CoreLoopKnobs.CRANK_ACTION)
		var key := InputEventKey.new()
		key.physical_keycode = CoreLoopKnobs.CRANK_KEY
		InputMap.action_add_event(CoreLoopKnobs.CRANK_ACTION, key)

	if not InputMap.has_action(CoreLoopKnobs.DRILL_ACTION):
		InputMap.add_action(CoreLoopKnobs.DRILL_ACTION)
		var trigger := InputEventMouseButton.new()
		trigger.button_index = CoreLoopKnobs.DRILL_MOUSE_BUTTON
		InputMap.action_add_event(CoreLoopKnobs.DRILL_ACTION, trigger)


func _build_debris_pool() -> void:
	_debris_pool = OreDebrisPool.new()
	_debris_pool.name = "Debris"
	add_child(_debris_pool)


## The crystals, placed by CoreLoopKnobs.ORE_NODES.
##
## Where they are IS the risk curve of this prototype - six sit where the creature
## can reach and two do not - so the table is the level design and this is only
## the loop that reads it.
func _build_ore_nodes() -> void:
	for index: int in CoreLoopKnobs.ORE_NODES.size():
		var entry: Dictionary = CoreLoopKnobs.ORE_NODES[index]
		var ore_node := OreNode.new()
		ore_node.name = "OreNode%d" % index
		ore_node.position = entry["position"]
		ore_node.debris_pool = _debris_pool
		add_child(ore_node)
		ore_node.build(entry["seed"], entry["hardness"], CoreLoopKnobs.ESCAPE_CLEARANCE)
		ore_node.crystal_freed.connect(_on_crystal_freed)
		_ore_nodes.append(ore_node)


## Placed before it enters the tree, and that is not a tidiness choice.
##
## Repositioning a body that is already in the physics world is a kinematic
## sweep. Nothing is in its hands yet on the first frame, so the cost here is only
## a jolt - but the cube spawns a few metres away on the same frame, and the same
## mistake made after the tether exists flings whatever is on the end of it across
## the chamber. Doing it the safe way once is cheaper than remembering which
## spawns are safe.
func _spawn_suit() -> void:
	_suit = SUIT_SCENE.instantiate()
	var facing := (CoreLoopKnobs.SUIT_LOOK_AT - CoreLoopKnobs.SUIT_SPAWN).normalized()
	_suit.transform = Transform3D(
		Basis.looking_at(facing, _reference_up(facing)), CoreLoopKnobs.SUIT_SPAWN
	)
	add_child(_suit)

	_beam = CoreLoopDrillBeam.new()
	_beam.name = "DrillBeam"
	_beam.ore_nodes = _ore_nodes
	_beam.debris_pool = _debris_pool
	# Under the camera, so the beam's own local space is already aim space.
	_suit.get_head_camera().add_child(_beam)

	# The pickup watches CRYSTAL_LAYER, and a crystal only reaches that layer when
	# its node lets go of it - so an embedded crystal cannot be collected by flying
	# at it. Nothing checks a flag, so nothing can forget to.
	var collector := _suit.get_node("CrystalCollector") as Area3D
	_collector_shape = (collector.get_node("CollectorShape") as CollisionShape3D).shape
	collector.body_entered.connect(_on_crystal_in_reach)


func _spawn_cube() -> void:
	_cube = LifeSupportCube.new()
	_cube.name = "LifeSupportCube"
	_cube.transform = Transform3D(Basis.IDENTITY, CoreLoopKnobs.CUBE_SPAWN)
	add_child(_cube)


## The suit's battery, the two lamp responses, and the rules that move charge
## between them.
##
## The suit's store hangs off the suit rather than off this node so that anything
## holding the suit can find its battery, which is the same reason the cube owns
## its own.
func _build_power() -> void:
	_suit_store = PowerStore.new()
	_suit_store.name = "SuitPower"
	_suit.add_child(_suit_store)
	_suit_store.configure(
		CoreLoopKnobs.SUIT_CAPACITY,
		CoreLoopKnobs.SUIT_START_FRACTION,
		CoreLoopKnobs.SUIT_DRAIN_PER_SECOND
	)

	_suit_lamp_response = _make_lamp_response(
		"SuitLampResponse",
		_suit.get_helmet_lamp(),
		_suit_store,
		CoreLoopKnobs.HELMET_LAMP_ENERGY,
		CoreLoopKnobs.HELMET_LAMP_RANGE,
		CoreLoopKnobs.SUIT_DIM_POINTS,
		CoreLoopKnobs.SUIT_FLICKER_POINTS,
		CoreLoopKnobs.SUIT_LAMP_MIN_RANGE_FRACTION,
		1.0
	)
	_suit_lamp_response.set_color(CoreLoopKnobs.HELMET_LAMP_COLOR)
	_suit_lamp_response.set_shadows(CoreLoopKnobs.HELMET_LAMP_SHADOWS)
	_suit_lamp_response.set_distance_falloff(CoreLoopKnobs.HELMET_LAMP_ATTENUATION)
	_suit_lamp_response.set_cone(CoreLoopKnobs.HELMET_LAMP_ANGLE)
	_suit_lamp_response.set_edge_falloff(CoreLoopKnobs.HELMET_LAMP_ANGLE_ATTENUATION)

	_cube_lamp_response = _make_lamp_response(
		"CubeLampResponse",
		_cube.get_lamp(),
		_cube.get_store(),
		CoreLoopKnobs.CUBE_LIGHT_ENERGY,
		CoreLoopKnobs.CUBE_LIGHT_RANGE,
		CoreLoopKnobs.CUBE_DIM_POINTS,
		CoreLoopKnobs.CUBE_FLICKER_POINTS,
		CoreLoopKnobs.CUBE_LAMP_MIN_RANGE_FRACTION,
		CoreLoopKnobs.CUBE_FLICKER_SCALE
	)
	_cube_lamp_response.set_color(CoreLoopKnobs.CUBE_LIGHT_COLOR)
	_cube_lamp_response.set_shadows(CoreLoopKnobs.CUBE_LIGHT_SHADOWS)
	_cube_lamp_response.set_distance_falloff(CoreLoopKnobs.CUBE_LIGHT_ATTENUATION)

	_power = CoreLoopPowerSystem.new()
	_power.name = "PowerSystem"
	add_child(_power)
	_power.bind(_suit, _cube, _suit_store, _cube.get_store())

	# The drill runs off the same battery the lamp does, which is the whole point:
	# cutting rock and being able to see are now competing for one number.
	_beam.power_store = _suit_store


func _make_lamp_response(
	node_name: String,
	light: Light3D,
	store: PowerStore,
	base_energy: float,
	base_range: float,
	dim_points: Array[Vector2],
	flicker_points: Array[Vector2],
	min_range_fraction: float,
	flicker_scale: float
) -> LampPowerResponse:
	var response := LampPowerResponse.new()
	response.name = node_name
	response.base_energy = base_energy
	response.base_range = base_range
	response.dim_curve = LampPowerResponse.build_curve(dim_points, 1.0)
	response.flicker_curve = LampPowerResponse.build_curve(
		flicker_points, CoreLoopKnobs.FLICKER_RATE_MAX
	)
	response.min_range_fraction = min_range_fraction
	response.flicker_scale = flicker_scale if CoreLoopKnobs.FLICKER_ENABLED else 0.0
	add_child(response)
	response.bind(light, store)
	return response


func get_noise() -> CoreLoopNoise:
	return _noise


func get_director() -> MonsterDirector:
	return _director


func get_crawler() -> CrawlerBody:
	return _crawler


## The one wire between what you do and what hears you.
func _build_noise() -> void:
	_noise = CoreLoopNoise.new()
	_noise.name = "Noise"
	add_child(_noise)
	_noise.bind(_suit, _beam, _power)
	_noise.noise_made.connect(_director.hear)


## True once the navmesh is live on the map. Nothing that paths may run before it.
func is_navigation_ready() -> bool:
	return _navigation_ready


func get_navmesh_baker() -> WallNavmeshBaker:
	return _navigation


## Bakes late, and that is not caution - it is the only order that works.
##
## CSG generates its trimesh collider as part of processing, so on the frame this
## scene is built there is no collision in the physics world at all. A bake here
## probes an empty world, finds no surface anywhere, and produces a mesh of
## nothing without raising a single error.
##
## bake_network() then does not return until the mesh is live on the navigation
## map, which is what makes anything that starts pathing afterwards safe.
func _bake_navigation() -> void:
	_navigation.cell = CoreLoopKnobs.NAVMESH_CELL
	_navigation.openness_radius = CoreLoopKnobs.NAVMESH_OPENNESS_RADIUS
	_navigation.probe_mask = CoreLoopKnobs.NAVMESH_PROBE_MASK
	_navigation.cell_size = CoreLoopKnobs.NAVMESH_CELL_SIZE
	_navigation.max_cells = CoreLoopKnobs.NAVMESH_MAX_CELLS

	await get_tree().physics_frame
	await get_tree().physics_frame
	# Seeded from the suit's spawn, which is inside the entrance shaft by
	# construction, and fenced by the network's own bounds so a hole in the hull
	# cannot send the fill off into the void.
	await _navigation.bake_network(CoreLoopKnobs.SUIT_SPAWN, _tunnels.bounds())
	_navigation_ready = true


# --- The loop --------------------------------------------------------------


## How many crystals have been collected, and how many there are to find.
func get_score() -> int:
	return _collected


func get_ore_node_count() -> int:
	return _ore_nodes.size()


## One ore node by index, or null. For the verifier, which drills a real one
## rather than a stand-in.
func get_ore_node(index: int) -> OreNode:
	if index < 0 or index >= _ore_nodes.size():
		return null
	return _ore_nodes[index]


func get_drill_beam() -> CoreLoopDrillBeam:
	return _beam


## Cutting a crystal out and collecting it are two separate beats on purpose: in
## zero g the freed crystal drifts, so going to get it is a small chase and is
## worth being able to fail.
func _on_crystal_freed(ore_node: OreNode) -> void:
	if ore_node == null:
		push_warning("crystal_freed fired with no node")


func _on_crystal_in_reach(body: Node3D) -> void:
	var crystal := body as RigidBody3D
	if crystal == null:
		return
	_collected += 1
	_hud.set_score(_collected, _ore_nodes.size())
	crystal.queue_free()


func _reset() -> void:
	_cube.respawn()
	_suit_store.set_fraction(CoreLoopKnobs.SUIT_START_FRACTION)


## Basis.looking_at fails when its up vector is parallel to the direction, and the
## suit spawns pointing almost straight down the entrance shaft.
func _reference_up(direction: Vector3) -> Vector3:
	if absf(direction.dot(Vector3.UP)) > 0.99:
		return Vector3.BACK
	return Vector3.UP


func _apply_draw_distance() -> void:
	var scene_environment := _world_environment.environment
	scene_environment.fog_depth_begin = CoreLoopKnobs.FOG_DEPTH_BEGIN
	scene_environment.fog_depth_end = CoreLoopKnobs.FOG_DEPTH_END
	scene_environment.fog_density = CoreLoopKnobs.FOG_DENSITY
	scene_environment.fog_light_color = CoreLoopKnobs.FOG_LIGHT_COLOR
	scene_environment.ambient_light_energy = CoreLoopKnobs.AMBIENT_ENERGY
