extends Node3D

## Puts the object carrying prototype's chamber and player in a room with the
## tentacle crawler's creature, and gives the creature a navmesh instead of a
## pilot.
##
## The question is GDD open question 6 - does the creature wall-crawl, or float
## and navigate around obstacles - and underneath it the one that decides whether
## any of this is worth building: is a thing crawling the walls of a sealed room
## frightening, or is it just in the way.
##
## WHERE THE TUNING LIVES. The prototype's own nodes default their exports
## straight to ChaseKnobs, so there is nothing to push onto them and nothing that
## can be readied in the wrong order. What this script pushes is the tuning for
## the two scenes it borrows, which know nothing about ChaseKnobs and would
## otherwise run at values chosen for a different room.

## Creature and pursuit values you can move from the tuning panel, and what SAVE
## writes back to. Assigned in the .tscn; see _ready for a missing one.
@export var settings: ChaseSettings

var _debug_camera_active: bool = false

@onready var _world_environment: WorldEnvironment = $WorldEnvironment
@onready var _corridors: ChaseCorridorGenerator = $Corridors
@onready var _navigation: WallNavmeshBaker = $CorridorNavigation
@onready var _player: CarrierPlayer = $CarrierPlayer
@onready var _follower: ChaseTargetFollower = $ChaseTargetFollower
@onready var _crawler: CrawlerBody = $Crawler
@onready var _tentacles: TentacleArray = $Crawler/Tentacles
@onready var _creature_light: OmniLight3D = $Crawler/CreatureLight
@onready var _contact: CreatureContact = $Crawler/CreatureContact
@onready var _director: CrawlerCameraDirector = $DebugCamera
@onready var _debug_draw: ChaseDebugDraw = $DebugDraw
@onready var _tuning: PrototypeTuningPanel = $HUD/Tuning


# Both the player and the creature have to be at their spawns before they enter
# the tree. The player for the reason object_carrying_prototype.gd sets out at
# length - repositioning a body already in the physics world is a kinematic move,
# and the module sitting on the origin would be flung across the chamber by it.
# The creature for a quieter one: CrawlerBody caches its own position in _ready
# and integrates from there, so a Crawler moved afterwards spends the first
# second swimming back to wherever it thought it was.
func _enter_tree() -> void:
	($CarrierPlayer as Node3D).position = ChaseKnobs.PLAYER_SPAWN
	($Crawler as Node3D).position = ChaseKnobs.CREATURE_SPAWN
	($ChaseTargetFollower as Node3D).position = ChaseKnobs.FOLLOWER_SPAWN
	_apply_cave_audio()


## The creature's audio, pushed HERE rather than from _ready with the rest of the
## tuning, and that is not a tidiness choice.
##
## TentacleImpactAudio reads `bus` and `max_distance` exactly once, in its own
## _ready, when it builds its six voices. _ready runs bottom-up, so the crawler is
## finished before this scene's root starts - a push from _apply_creature_tuning
## would arrive a frame after the voices already existed, route nothing, and
## report no error at all. The creature would simply go on sounding dry.
## _enter_tree runs top-down, which is the whole reason this is up here, and the
## bus has to be registered in the same call for the same reason.
##
## The verifier asserts the voices came out on the cave bus, because a regression
## in that ordering is silent everywhere else.
func _apply_cave_audio() -> void:
	CaveReverbBus.install(
		ChaseKnobs.CAVE_BUS, ChaseKnobs.CAVE_SEND_BUS, ChaseKnobs.CAVE_BUS_VOLUME_DB
	)
	var impact_audio := $Crawler/ImpactAudio as TentacleImpactAudio
	impact_audio.bus = ChaseKnobs.CAVE_BUS
	impact_audio.max_distance = ChaseKnobs.CREATURE_AUDIO_MAX_DISTANCE


func _ready() -> void:
	# A fresh clone has no chase_settings.tres yet, and anyone may delete it. A
	# bare instance holds exactly the knobs consts, so the fallback is the old
	# behaviour rather than a crash.
	if settings == null:
		settings = ChaseSettings.new()
		push_warning("No chase_settings.tres wired; running on chase_knobs.gd defaults.")
	settings.changed.connect(_apply_creature_tuning)

	_apply_draw_distance()
	_apply_creature_tuning()
	_tuning.bind(settings)
	_contact.caught.connect(_on_caught)
	_set_debug_camera(false)
	await _bake_navigation()


## The one level-design rule this prototype cannot break is now
## ChaseSettings.invariant_failures(), because creature_probe_comfort has a
## slider and the rule has to hold against whatever that slider is left on.
##
## The first version of this scene ran the chase through the object carrying
## prototype's chamber, whose two halves are joined by a 5 m hatch. The creature
## could almost never get through: at 5 m it is inside its own comfort distance of
## all four sides at once and its avoidance pushes it back out of the opening. It
## read as broken pathfinding for a long time before it turned out to be a
## corridor narrower than the thing walking down it. That is also why the slider's
## maximum is 5.0 rather than something round - a value that cannot pass is not
## worth being able to dial in.


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("reset_player"):
		# The player handles this key for itself. Everything else in the
		# experiment is reset here, so one press restarts the whole run rather
		# than leaving the creature wherever the last attempt abandoned it.
		_reset()
		return

	# Two debug toggles do not justify mutating the host project's InputMap, and
	# every action name in it is already spoken for by the carrying prototype.
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_F1:
		_debug_draw.visible = not _debug_draw.visible
	elif key.physical_keycode == KEY_F2:
		_set_debug_camera(not _debug_camera_active)


## Bake late, and enable the follower later still.
##
## ChamberGenerator raises the room as a CSGCombiner3D in its own _ready. CSG
## generates its trimesh collider as part of processing, so on the frame this
## runs there is no collision in the world at all - a bake here probes an empty
## chamber, finds no surface anywhere, and produces a mesh of nothing without
## raising a single error.
##
## The second wait is for a different server. NavigationServer3D applies map
## changes at the end of the physics frame, so a follower that starts pathing on
## the same frame the mesh is assigned queries a map that is still empty, gets
## the origin back as the closest point, and sets off through the divider.
func _bake_navigation() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	# Seeded from the player's spawn, which is inside a corridor by construction,
	# and fenced by the network's own bounds so a hole in the hull cannot send the
	# fill off into the void. bake_network() does not return until the mesh is
	# live on the map, which is what makes the line below safe.
	await _navigation.bake_network(ChaseKnobs.PLAYER_SPAWN, _corridors.bounds())
	_follower.enabled = true


func _apply_draw_distance() -> void:
	var scene_environment := _world_environment.environment
	scene_environment.fog_depth_begin = CarryKnobs.FOG_DEPTH_BEGIN
	scene_environment.fog_depth_end = CarryKnobs.FOG_DEPTH_END
	scene_environment.fog_density = CarryKnobs.FOG_DENSITY


## The creature arrives tuned for a 244 m corridor it shared with nothing. Two of
## these are comfort, and two are not.
##
## The masks are the ones that matter. Both default to hull|prop, and in THIS
## project layer 2 is the player - so untouched, the creature's body probe reads
## the player as a wall to swerve away from, and its tentacles will try to take a
## grip on one. Neither is a subtle failure once you have seen it, and both are
## exported, which is the only reason none of this needed the crawler prototype
## edited.
##
## Its AUDIO is overridden too, but not from here - see _apply_cave_audio, which
## runs in _enter_tree because the two exports it writes are read once at the
## crawler's own _ready, and this function is far too late for them.
## Runs once at startup and again on every change from the tuning panel, so
## "it took effect while being chased" and "it took effect on the next run" are
## the same code path rather than two that can drift apart.
func _apply_creature_tuning() -> void:
	_crawler.max_speed = settings.creature_max_speed
	_crawler.leash_slack = settings.creature_leash_slack
	_crawler.probe_comfort = settings.creature_probe_comfort
	_crawler.probe_mask = ChaseKnobs.CREATURE_PROBE_MASK
	_tentacles.query_mask = ChaseKnobs.CREATURE_TENTACLE_MASK
	_follower.move_speed = settings.follower_speed
	# Through the setter, not the property: the catch sphere is built once and
	# writing the number alone would leave the reach at its startup size.
	_contact.set_catch_radius(settings.catch_radius)

	_creature_light.light_color = ChaseKnobs.CREATURE_LIGHT_COLOR
	_creature_light.light_energy = settings.creature_light_energy
	_creature_light.omni_range = ChaseKnobs.CREATURE_LIGHT_RANGE
	_creature_light.omni_attenuation = ChaseKnobs.CREATURE_LIGHT_ATTENUATION
	_creature_light.shadow_enabled = ChaseKnobs.CREATURE_LIGHT_SHADOWS

	# The corridor-width rule that used to be _check_passage_width, plus the
	# catch-inside-the-standoff one. Both are ChaseSettings.invariant_failures()
	# now, so they are checked against the SAVED values and by the verifier
	# rather than only at startup against the consts.
	for failure: String in settings.invariant_failures():
		push_warning("chase_settings: %s" % failure)


## Which camera is rendering, decided here rather than left to tree order.
##
## CrawlerCameraDirector makes one of its own cameras current in _ready, and so
## does the player's head camera; whichever is readied last wins, and that is a
## property of where the nodes sit in the scene rather than of anything anyone
## chose. Setting it explicitly from the parent - which is readied after both -
## is what makes the answer stable.
##
## The chase rig, never the orbit rig. Orbit needs mouse deltas to steer and the
## player owns the pointer; the chase rig hangs off a SpringArm and needs no
## input at all, which is exactly what a look-at-the-creature-while-tuning camera
## should need.
func _set_debug_camera(active: bool) -> void:
	_debug_camera_active = active
	_director.process_mode = PROCESS_MODE_INHERIT if active else PROCESS_MODE_DISABLED
	if active:
		_director.set_orbit_active(false)
	else:
		_player.get_node("HeadCamera").current = true


func _reset() -> void:
	_corridors.reset_carry_object()
	_crawler.teleport(ChaseKnobs.CREATURE_SPAWN)
	_follower.teleport(ChaseKnobs.FOLLOWER_SPAWN)
	_contact.armed = true


func _on_caught(_body: Node3D) -> void:
	# Held for a moment before the reset, so the flash on the HUD is something
	# you read rather than something you suspect you saw.
	await get_tree().create_timer(ChaseKnobs.CATCH_RESPAWN_DELAY).timeout
	_player.respawn()
	_reset()
