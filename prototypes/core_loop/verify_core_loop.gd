extends Node

## Headless check that the core loop prototype stands up. Run it with:
##
##     godot --headless --path . res://prototypes/core_loop/verify_core_loop.tscn
##
## As a SCENE named on the command line, not as `--script` and not bare. The
## project's main scene is the main menu, so anything that does not name a scene
## boots that instead and this never runs.
##
## The groups here exist because each one is a failure this composition can have
## while looking completely healthy:
##
##   [geometry]  a CSG network whose collision never materialised renders fine and
##               is invisible to every physics query, including the navmesh bake.
##   [widths]    the refuge routes are the only thing making "duck in here" a rule
##               rather than a hope, and the number that enforces it lives in a
##               different region of the knobs file from the routes themselves.
##   [power]     the drill drawing charge is the one thing in this composition that
##               neither donor prototype had, so nothing anywhere else has ever
##               exercised it.
##   [mining]    a drill wired to the wrong store, or to no store, cuts rock
##               perfectly and costs nothing - which looks exactly like success.
##
## [power] and [mining] DRIVE THE REAL INPUT PATH rather than calling the carve
## directly. The gate they are checking lives on `_is_firing`, which is assembled
## from the action, the mouse capture state and the battery together, so a test
## that reached past it into _fire would pass on a build where the gate is broken.

const SCENE_PATH := "res://prototypes/core_loop/core_loop_prototype.tscn"

## Physics frames of held trigger per drilling check. At 60 Hz this is two
## seconds, which is long enough for the drain to clear the noise floor of a
## single frame's rounding.
const DRILL_FRAMES := 120

## How far in front of the ore node the suit is parked to drill it, metres. Inside
## DRILL_RANGE and outside the node's own rock.
const DRILL_STANDOFF := 2.5

## How long the crystal-freeing check will hold the trigger before giving up. One
## minute: far past anything anyone would call playable, so the failure means
## "never" rather than "slow" and the reported time carries the judgement.
const FREE_CRYSTAL_FRAME_CAP := 3600

## How wide a circle the crystal-freeing check sweeps the crosshair around, in
## metres, and how fast in radians per frame. Roughly a bore's width of wobble at
## a bit under one revolution a second - a hand, not a machine.
const SWEEP_RADIUS := 0.35
const SWEEP_RATE := 0.1

## How far a probe may be from open space and still count as open. The suit is a
## 0.4 m sphere; this is that with room for the CSG surface landing a little
## inside the authored bore.
const OPEN_PROBE_RADIUS := 0.6

## How far a wall probe casts before it gives up. Longer than the widest chamber,
## so "no hit" means no rock rather than a ray that ran out.
const WALL_PROBE_DISTANCE := 40.0

## How long to wait for the flood fill before calling it a failure. The fill is
## several thousand physics queries in GDScript, and it is allowed to be slow -
## it is not allowed to never finish.
const NAVMESH_BAKE_TIMEOUT_MS := 120000

## Slack on top of a corridor's own half-width when asking whether a point has
## navmesh on it. Covers the CSG surface landing a little off the authored bore
## and the lattice quantising the wall.
const PROJECTION_MARGIN := 2.0

## How close a path's last corner has to get before the destination counts as
## reached.
const ARRIVAL_TOLERANCE := 4.0

var _failures: int = 0
var _checks: int = 0

## When the scene entered the tree, so the navmesh check can report how long the
## whole build-and-bake took rather than how long it waited afterwards.
var _scene_started_ms: int = 0


func _ready() -> void:
	_run()


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		print("FAIL [load] could not load %s" % SCENE_PATH)
		get_tree().quit(1)
		return

	var scene := packed.instantiate()
	_scene_started_ms = Time.get_ticks_msec()
	add_child(scene)

	# CSG generates its trimesh collider as part of processing, so on the frame
	# the tree is built there is no collision in the physics world at all. A probe
	# here finds nothing anywhere and reports a network made entirely of void,
	# without raising a single error.
	for _frame: int in 10:
		await get_tree().physics_frame

	var tunnels: CoreLoopTunnels = scene.get_node("Tunnels")
	_report(tunnels)
	_check_widths()
	_check_geometry(tunnels)
	await _check_navmesh(scene as CoreLoopPrototype, tunnels)
	await _check_monster(scene as CoreLoopPrototype)
	await _check_drill(scene as CoreLoopPrototype)

	print("")
	if _failures == 0:
		print("PASS  %d checks" % _checks)
	else:
		print("FAIL  %d of %d checks failed" % [_failures, _checks])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(tag: String, condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	print("FAIL [%s] %s" % [tag, message])


func _report(tunnels: CoreLoopTunnels) -> void:
	var summary := tunnels.width_summary()
	print(
		(
			"[map] %d routes, %.0f m of centreline, bounds %v"
			% [CoreLoopKnobs.ROUTES.size(), tunnels.network_length(), tunnels.bounds().size]
		)
	)
	print(
		(
			"[map] creature passes %.1f m and wider, blocked by %.1f m and under (needs %.1f m)"
			% [
				summary["narrowest_passable"],
				summary["widest_blocked"],
				2.0 * CoreLoopKnobs.CREATURE_PROBE_COMFORT,
			]
		)
	)


## The refuge routes have to be genuinely impassable and everything else has to be
## genuinely passable. Checked against the creature's own comfort distance rather
## than against a literal, so retuning the creature fails this rather than quietly
## opening the refuges up.
func _check_widths() -> void:
	var minimum := 2.0 * CoreLoopKnobs.CREATURE_PROBE_COMFORT
	for route: Dictionary in CoreLoopKnobs.ROUTES:
		var name_of: String = route["name"]
		var width: float = route["width"]
		var is_refuge := CoreLoopKnobs.REFUGE_ROUTES.has(name_of)
		if is_refuge:
			_check(
				"widths",
				width < minimum,
				(
					"'%s' is listed as refuge but is %.1f m wide, which the creature can enter"
					% [name_of, width]
				)
			)
		else:
			_check(
				"widths",
				width >= minimum,
				(
					"'%s' is %.1f m wide, under the creature's %.1f m minimum, so it is refuge in fact and not in REFUGE_ROUTES"
					% [name_of, width, minimum]
				)
			)
		_check(
			"widths",
			width > 2.0 * CoreLoopKnobs.PLAYER_RADIUS + 1.0,
			(
				"'%s' is %.1f m wide, which is not enough room for the player to fly down"
				% [name_of, width]
			)
		)


## Every junction and every span midpoint has to be open space, and there has to
## be rock somewhere around it.
##
## The second half is the one that matters. A network whose CSG failed to build
## collision passes an openness test everywhere, because empty space is open - so
## "is it open" and "is there a wall" have to both be asked or the check proves
## nothing.
func _check_geometry(tunnels: CoreLoopTunnels) -> void:
	var space := get_viewport().world_3d.direct_space_state

	var named_places := {
		"ENTRANCE": CoreLoopKnobs.ENTRANCE,
		"HUB_ANTECHAMBER": CoreLoopKnobs.HUB_ANTECHAMBER,
		"HUB_EAST": CoreLoopKnobs.HUB_EAST,
		"HUB_WEST": CoreLoopKnobs.HUB_WEST,
		"HUB_DEEP": CoreLoopKnobs.HUB_DEEP,
		"CORE_CHAMBER": CoreLoopKnobs.CORE_CHAMBER,
		"SUIT_SPAWN": CoreLoopKnobs.SUIT_SPAWN,
		"CUBE_SPAWN": CoreLoopKnobs.CUBE_SPAWN,
	}
	for label: String in named_places:
		var point: Vector3 = named_places[label]
		_check("geometry", _is_open(space, point), "%s at %v is inside solid rock" % [label, point])
		_check(
			"geometry",
			_has_rock_around(space, point),
			"%s at %v has no rock around it; the CSG hull did not build collision" % [label, point]
		)

	for route: Dictionary in CoreLoopKnobs.ROUTES:
		for midpoint: Vector3 in tunnels.route_midpoints(route["name"]):
			_check(
				"geometry",
				_is_open(space, midpoint),
				"'%s' is blocked at %v" % [route["name"], midpoint]
			)

	for entry: Dictionary in CoreLoopKnobs.ORE_NODES:
		var position: Vector3 = entry["position"]
		_check(
			"geometry",
			_is_open(space, position),
			"ore node at %v is buried in the tunnel wall" % position
		)


## The navmesh has to cover everywhere the creature should hunt and nowhere it
## should not.
##
## The second half is the one that is easy to get wrong and impossible to see. A
## mesh painted into a 4 m refuge route does not look like anything - the creature
## simply swims into the passage, finds itself inside its own comfort distance on
## all four sides, and stops. That reads as broken pathfinding for as long as it
## takes somebody to measure the corridor.
func _check_navmesh(prototype: CoreLoopPrototype, tunnels: CoreLoopTunnels) -> void:
	while not prototype.is_navigation_ready():
		if Time.get_ticks_msec() - _scene_started_ms > NAVMESH_BAKE_TIMEOUT_MS:
			_check("navmesh", false, "the bake never finished")
			return
		await get_tree().physics_frame

	var baker := prototype.get_navmesh_baker()
	var stats := baker.stats()
	print(
		(
			"[navmesh] %d cells, %d quads, leaked %s, ready %.1f s after the scene was built"
			% [
				stats["cells"],
				stats["quads"],
				str(stats["leaked"]),
				float(Time.get_ticks_msec() - _scene_started_ms) / 1000.0,
			]
		)
	)
	_check("navmesh", not stats["leaked"], "the flood fill escaped its bounds; the hull has a hole")
	_check("navmesh", stats["quads"] > 0, "the bake produced no polygons at all")

	var map := baker.get_navigation_map()
	for route: Dictionary in CoreLoopKnobs.ROUTES:
		var route_name: String = route["name"]
		var width: float = route["width"]
		var is_refuge := CoreLoopKnobs.REFUGE_ROUTES.has(route_name)
		# The navmesh is painted ON the walls, so the nearest polygon to a point on
		# the centreline is half a corridor away by construction. "Reachable" is
		# therefore a projection that lands on THIS corridor's own wall rather than
		# on some other tunnel's through the rock.
		var reach := width * 0.5 + PROJECTION_MARGIN
		var on_mesh := 0
		var midpoints := tunnels.route_midpoints(route_name)
		for midpoint: Vector3 in midpoints:
			if _projection_distance(map, midpoint) <= reach:
				on_mesh += 1
		if CoreLoopKnobs.NAVMESH_ISLAND_ROUTES.has(route_name):
			# A documented island - see NAVMESH_ISLAND_ROUTES. Asserted rather than
			# skipped, so the day the baker stops severing it this fails and tells
			# whoever fixed it to take the route off that list and put its spawn
			# points back.
			_check(
				"navmesh",
				not _can_path(map, midpoints[midpoints.size() - 1], CoreLoopKnobs.SUIT_SPAWN),
				(
					"'%s' now reaches the rest of the network; drop it from NAVMESH_ISLAND_ROUTES and restore its MONSTER_SPAWN_POINTS"
					% route_name
				)
			)
		elif is_refuge:
			# The DEEPEST point, not every point. A refuge route leaves a hub the
			# creature can stand in, so its first span is always within reach of
			# that hub's own mesh - that is the mouth, not the passage. What has to
			# be true is that following you DOWN it is impossible.
			var deepest: Vector3 = midpoints[midpoints.size() - 1]
			_check(
				"navmesh",
				_projection_distance(map, deepest) > reach,
				(
					"refuge route '%s' has navmesh within %.1f m of its far end; the creature will try to follow you in and jam"
					% [route_name, reach]
				)
			)
		else:
			_check(
				"navmesh",
				on_mesh > 0,
				(
					"'%s' has no navmesh within %.1f m of any of its %d points; the creature cannot hunt there"
					% [route_name, reach, midpoints.size()]
				)
			)

	# Connectivity, not just coverage, and every spawn point rather than a sample.
	#
	# Polygons in one NavigationMesh join only where they share an edge, and this
	# bake reports a handful of edge-merge errors where the chamber spheres meet
	# the corridor boxes. A network can be fully covered and still be islands, and
	# a spawn point on the wrong island is a creature that wakes up and never
	# arrives - which reads as the whole noise system being broken.
	var unreachable := 0
	for point: Vector3 in CoreLoopKnobs.MONSTER_SPAWN_POINTS:
		if not _can_path(map, point, CoreLoopKnobs.SUIT_SPAWN):
			unreachable += 1
			print("[navmesh] spawn point %v cannot reach the player's start" % point)
	_check(
		"navmesh",
		unreachable == 0,
		(
			"%d of %d monster spawn points cannot path to the player's start; the creature would wake there and never arrive"
			% [unreachable, CoreLoopKnobs.MONSTER_SPAWN_POINTS.size()]
		)
	)


## How far the nearest navigation polygon is from a point, or INF on a dead map.
func _projection_distance(map: RID, point: Vector3) -> float:
	if not NavigationServer3D.map_is_active(map):
		return INF
	return NavigationServer3D.map_get_closest_point(map, point).distance_to(point)


## Whether the creature could actually walk from one place to the other.
##
## BOTH ENDS ARE PROJECTED ONTO THE MESH FIRST, because neither is on it: the
## creature crawls the shell of a corridor and these are points down the middle of
## one. That is exactly what ChaseTarget does with its quarry every 0.2 s, so
## pathing between raw centreline points would be testing a query the game never
## makes - and failing it, because a 10 m tube's centreline is 5 m from anything.
##
## NavigationServer answers an unreachable query with a partial path to the
## nearest polygon it CAN get to rather than with a failure, so the last corner is
## checked or every disconnected mesh passes.
func _can_path(map: RID, from: Vector3, to: Vector3) -> bool:
	if not NavigationServer3D.map_is_active(map):
		return false
	var start := NavigationServer3D.map_get_closest_point(map, from)
	var finish := NavigationServer3D.map_get_closest_point(map, to)
	var corners := NavigationServer3D.map_get_path(map, start, finish, true)
	if corners.size() < 2:
		return false
	return corners[corners.size() - 1].distance_to(finish) < ARRIVAL_TOLERANCE


## Drives the whole state machine with synthetic noise.
##
## SYNTHETIC, not by drilling, and the difference matters. Waking the creature for
## real is a dice roll against SPAWN_CHANCE_PER_SECOND, so a test that drilled and
## waited would fail at random and pass at random. force_spawn() and hear() are the
## same entry points the noise bus uses; only the dice are skipped.
##
## The timers are shortened first. Nothing here is testing that six seconds is six
## seconds - it is testing that the edges exist and fire in the right order, and at
## shipped values that would be half a minute of simulation.
func _check_monster(prototype: CoreLoopPrototype) -> void:
	var director := prototype.get_director()
	var suit := prototype.get_suit()

	var kept_chase := director.chase_duration
	var kept_silence := director.despawn_silence
	director.chase_duration = 0.4
	director.despawn_silence = 1.0

	_check(
		"monster",
		not director.is_spawned(),
		"the creature is already in the world before anything has made a noise"
	)

	# A dormant creature must be parked outside the network. Its catch sphere is
	# 8.5 m across and still exists while it is disabled, so leaving it where it
	# stood would put an invisible trigger in a tunnel you are about to fly down.
	_check(
		"monster",
		prototype.get_crawler().global_position.distance_to(CoreLoopKnobs.SUIT_SPAWN) > 100.0,
		"a dormant creature is parked inside the network"
	)

	var woke := director.force_spawn(suit.global_position)
	_check("monster", woke, "no spawn point qualified for a noise at the player's own start")
	if not woke:
		director.chase_duration = kept_chase
		director.despawn_silence = kept_silence
		return

	_check(
		"monster",
		director.get_state() == MonsterDirector.State.HUNTING,
		"a woken creature is in %s rather than hunting" % director.state_name()
	)
	var spawn_path: float = director.debug_state()["spawn_path"]
	print("[monster] woke %.0f m away along the navmesh" % spawn_path)
	_check(
		"monster",
		spawn_path >= CoreLoopKnobs.SPAWN_MIN_PATH and spawn_path <= CoreLoopKnobs.SPAWN_MAX_PATH,
		(
			"woke %.0f m away, outside the %.0f-%.0f m window; it either appears on top of you or never arrives"
			% [spawn_path, CoreLoopKnobs.SPAWN_MIN_PATH, CoreLoopKnobs.SPAWN_MAX_PATH]
		)
	)

	# Hearing something while standing next to the player is what gives you away.
	# Put it next to the player first, since it woke up a long way off.
	prototype.get_crawler().teleport(suit.global_position + Vector3(0, 0, 4.0))
	await get_tree().physics_frame
	director.hear(suit.global_position, CoreLoopKnobs.DRILL_NOISE_RADIUS)
	_check(
		"monster",
		director.get_state() == MonsterDirector.State.CHASING,
		"a noise inside the trigger radius left it %s rather than chasing" % director.state_name()
	)

	# Silence ends the chase, and then ends the creature.
	for _frame: int in 60:
		await get_tree().physics_frame
	_check(
		"monster",
		director.get_state() == MonsterDirector.State.HUNTING,
		"the chase never timed out; it is still %s" % director.state_name()
	)
	for _frame: int in 90:
		await get_tree().physics_frame
	_check(
		"monster",
		not director.is_spawned(),
		"the creature never gave up and despawned; it is %s" % director.state_name()
	)

	# A noise it cannot hear must not move it, and THE QUARRY IS WHERE THAT SHOWS.
	# The director records every noise for the HUD whether or not it heard it, so
	# the readout is not evidence; where it decided to walk is.
	director.chase_duration = kept_chase
	director.despawn_silence = kept_silence
	director.force_spawn(suit.global_position)
	var quarry_before := director.global_position
	director.hear(CoreLoopKnobs.CORE_CHAMBER, 1.0)
	_check(
		"monster",
		director.global_position.is_equal_approx(quarry_before),
		"a 1 m noise on the far side of the network moved its target; it is not deaf to anything"
	)

	# And one it can hear must. The other half of the same rule.
	var shout := prototype.get_crawler().global_position + Vector3(3.0, 0.0, 0.0)
	director.hear(shout, 30.0)
	_check(
		"monster",
		director.global_position.is_equal_approx(shout),
		"a noise right next to it did not move its target"
	)

	director.despawn()
	_check("monster", not director.is_spawned(), "despawn() left it in the world")


## Parks the suit in front of an ore node, holds the trigger, and checks that rock
## came off and charge went with it - then empties the battery and checks that
## both stop.
##
## The second half is the half worth having. A drill that draws power correctly
## and never runs out is indistinguishable from one that draws none, right up
## until a playtest where the battery matters.
func _check_drill(prototype: CoreLoopPrototype) -> void:
	var suit := prototype.get_suit()
	var store := prototype.get_suit_store()
	var ore_node := prototype.get_ore_node(0)
	if ore_node == null:
		_check("mining", false, "there are no ore nodes to drill")
		return

	var beam := prototype.get_drill_beam()
	# Headless has no window, so Input.mouse_mode never leaves VISIBLE and the
	# panel guard would hold the trigger down forever. See the flag's docstring.
	beam.mouse_capture_required = false
	_aim_suit_at(suit, ore_node.global_position)

	# The control window. The lamp is draining the same battery the drill is, so
	# the only honest way to attribute a spend to the drill is to measure the same
	# number of frames with the trigger up and subtract.
	store.set_fraction(1.0)
	var idle_before := store.charge
	for _frame: int in DRILL_FRAMES:
		await get_tree().physics_frame
	var idle_spent := idle_before - store.charge

	store.set_fraction(1.0)
	var charge_before := store.charge
	var rock_before := ore_node.get_rock_fraction()
	Input.action_press(CoreLoopKnobs.DRILL_ACTION)
	var fired_frames := 0
	for _frame: int in DRILL_FRAMES:
		await get_tree().physics_frame
		if beam.is_firing():
			fired_frames += 1
	Input.action_release(CoreLoopKnobs.DRILL_ACTION)
	var drilling_spent := charge_before - store.charge

	_check(
		"mining",
		fired_frames > 0,
		"the beam never fired in %d frames of held trigger" % DRILL_FRAMES
	)
	_check(
		"mining",
		rock_before - ore_node.get_rock_fraction() > 0.0,
		"holding the trigger on an ore node removed no rock"
	)

	# Attributed, not absolute. Half the drill's own rate is slack for the frames
	# either side of the press, and the subtraction is what stops the lamp's own
	# drain passing this check on a drill that is wired to nothing.
	var attributed := drilling_spent - idle_spent
	var drill_owes := CoreLoopKnobs.DRILL_POWER_PER_SECOND * float(fired_frames) / 60.0
	print(
		(
			"[drill] fired %d/%d frames, rock %.3f -> %.3f, idle spent %.1f, drilling spent %.1f"
			% [
				fired_frames,
				DRILL_FRAMES,
				rock_before,
				ore_node.get_rock_fraction(),
				idle_spent,
				drilling_spent,
			]
		)
	)
	_check(
		"power",
		attributed >= drill_owes * 0.5,
		(
			"drilling cost %.1f more than idling, against the %.1f the drill alone owes; it is not spending from the suit battery"
			% [attributed, drill_owes]
		)
	)

	# Flat battery: the gate has to stop the beam, not just the carve.
	store.set_fraction(0.0)
	var rock_at_empty := ore_node.get_rock_fraction()
	Input.action_press(CoreLoopKnobs.DRILL_ACTION)
	for _frame: int in 30:
		await get_tree().physics_frame
	_check("power", not beam.is_firing(), "the drill still fires on a flat battery")
	Input.action_release(CoreLoopKnobs.DRILL_ACTION)
	_check(
		"power",
		is_equal_approx(rock_at_empty, ore_node.get_rock_fraction()),
		"the drill still cuts rock on a flat battery"
	)

	# A DIFFERENT node, untouched by the checks above: time-to-free measured on
	# rock that has already been bored for two seconds is not a number anyone can
	# use.
	await _check_crystal_frees(prototype, store, prototype.get_ore_node(1))
	beam.mouse_capture_required = true


## Holds the trigger until the crystal comes loose, and reports how long it took.
##
## The reported number is the point. Freeing a crystal is the beat the whole loop
## is built around, and how many seconds of standing still and making the loudest
## noise in the game it costs is exactly what decides whether the creature is a
## threat or a formality. A number here is worth more than a pass.
func _check_crystal_frees(
	prototype: CoreLoopPrototype, store: PowerStore, ore_node: OreNode
) -> void:
	var suit := prototype.get_suit()
	Input.action_press(CoreLoopKnobs.DRILL_ACTION)
	var frames := 0
	while frames < FREE_CRYSTAL_FRAME_CAP and not ore_node.is_crystal_free():
		# Topped up every frame: this is measuring how long the ROCK takes, not
		# how far one battery goes. The battery's side of it is [power]'s job.
		store.set_fraction(1.0)

		# SWEPT, NOT BORED. The beam refuses to cut crystal, so aiming dead centre
		# opens a tube to the crystal and then stops forever - measured, and it is
		# the mechanic working rather than failing. A player widens the hole by
		# moving the crosshair, so the check has to as well.
		var angle := float(frames) * SWEEP_RATE
		var offset := Vector3(cos(angle), sin(angle), 0.0) * SWEEP_RADIUS
		_aim_suit_at(suit, ore_node.global_position + offset)
		await get_tree().physics_frame
		frames += 1
	Input.action_release(CoreLoopKnobs.DRILL_ACTION)

	var seconds := float(frames) / 60.0
	print(
		(
			"[drill] crystal loose after %.1f s (rock %.3f left, widest opening %.3f m, needs %.3f)"
			% [
				seconds,
				ore_node.get_rock_fraction(),
				ore_node.get_widest_opening(),
				CoreLoopKnobs.ESCAPE_CLEARANCE,
			]
		)
	)
	_check(
		"mining",
		ore_node.is_crystal_free(),
		(
			"a crystal never came loose in %.0f s of drilling straight at it; the loop has no payoff"
			% (float(FREE_CRYSTAL_FRAME_CAP) / 60.0)
		)
	)


## Puts the suit a fixed standoff from a point with its camera on it. The beam
## hangs under the head camera, which sits square to the body, so aiming the body
## aims the beam.
func _aim_suit_at(suit: CoreLoopSuit, target: Vector3) -> void:
	var from := target + Vector3(0, 0, DRILL_STANDOFF)
	var facing := (target - from).normalized()
	suit.velocity = Vector3.ZERO
	suit.angular_velocity = Vector3.ZERO
	suit.global_transform = Transform3D(Basis.looking_at(facing, Vector3.UP), from)


func _is_open(space: PhysicsDirectSpaceState3D, point: Vector3) -> bool:
	var sphere := SphereShape3D.new()
	sphere.radius = OPEN_PROBE_RADIUS
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, point)
	query.collision_mask = CoreLoopKnobs.HULL_LAYER
	return space.intersect_shape(query, 1).is_empty()


## True when at least one of the six axes finds rock. One is enough: a junction
## chamber is wider than some of these rays are long, and what this is proving is
## that the hull exists at all.
func _has_rock_around(space: PhysicsDirectSpaceState3D, point: Vector3) -> bool:
	for axis: Vector3 in [
		Vector3.RIGHT,
		Vector3.LEFT,
		Vector3.UP,
		Vector3.DOWN,
		Vector3.BACK,
		Vector3.FORWARD,
	]:
		var query := PhysicsRayQueryParameters3D.create(
			point, point + axis * WALL_PROBE_DISTANCE, CoreLoopKnobs.HULL_LAYER
		)
		if not space.intersect_ray(query).is_empty():
			return true
	return false
