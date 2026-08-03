extends Node

## Headless check that the chase prototype stands up. Run it with:
##
##     godot --headless --path . res://prototypes/tentacle_crawler_chaser/verify_chase.tscn
##
## As a SCENE named on the command line, not as `--script` and not bare. The
## project's main scene is the main menu, so anything that does not name a scene
## boots that instead and this never runs. verify_chase.tscn exists only to be
## that named scene; it instances the prototype below as a child of itself.
##
## [transit] is the check this file exists for. The creature getting stuck at a
## junction is the failure this prototype has actually had - in its first version
## a 5 m hatch was narrower than the creature's own comfort radius and it could
## almost never get through. Nothing static catches that. It has to be driven.
##
## [connectivity] is the static half: every route below crosses a boundary the
## mesh only survives if the grid welded it. [coverage] doubles as the regression
## test for the navigation server sync problem documented in wall_navmesh_baker.gd
## - before _await_map_sync existed, every probe answered the world origin.

const SCENE_PATH := "res://prototypes/tentacle_crawler_chaser/tentacle_crawler_chaser_prototype.tscn"

## How close a probe point's projection has to land to count as covered, metres.
const COVERAGE_TOLERANCE := 2.5

## How close a path's last corner has to get to the destination before the
## destination counts as reached. NavigationServer answers an unreachable query
## with a partial path to the nearest polygon it CAN get to rather than with a
## failure, so without this every disconnected mesh passes.
const ARRIVAL_TOLERANCE := 3.0

## Physics frames to let the chase actually run. Thirty seconds: the creature
## starts on the upper deck and has about 135 m of corridor and a vertical shaft
## between it and the player.
const TRANSIT_FRAMES := 1800

## Fraction of the opening distance the creature has to close inside that window.
## Generous on purpose - this is testing that it is not stuck, not that it is
## fast, and how fast belongs in ChaseKnobs where it can be felt rather than here.
const TRANSIT_CLOSE_FRACTION := 0.5

var _failures: int = 0
var _plants: int = 0
var _softest: float = INF
var _hardest: float = -INF


func _ready() -> void:
	_run()


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		print("FAIL [load] could not load %s" % SCENE_PATH)
		get_tree().quit(1)
		return

	var scene := packed.instantiate()
	add_child(scene)

	# The prototype root awaits two physics frames before baking, the flood fill
	# then spends a long frame on several thousand physics queries, and the bake
	# does not return until the mesh is live. Ninety is slack on all of it.
	for _i: int in 90:
		await get_tree().physics_frame

	var baker: WallNavmeshBaker = scene.get_node("CorridorNavigation")
	# The region's own map, not the viewport's. They are the same map here, but
	# asking the region removes one thing this can be wrong about.
	var map := baker.get_navigation_map()

	_report_map(baker, map)
	_check_bake(baker)
	_check_coverage(map)
	_check_connectivity(map)
	await _check_transit(scene)

	print("")
	if _failures == 0:
		print("PASS  all checks")
	else:
		print("FAIL  %d check(s) failed" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _fail(tag: String, message: String) -> void:
	_failures += 1
	print("FAIL [%s] %s" % [tag, message])


func _pass(tag: String, message: String) -> void:
	print("ok   [%s] %s" % [tag, message])


## What the region handed the server, and what the server made of it. Printed
## rather than asserted: when something here goes wrong the answer is usually a
## mismatch between two of these numbers, and which two is not predictable.
func _report_map(baker: WallNavmeshBaker, map: RID) -> void:
	var mesh := baker.navigation_mesh
	if mesh == null:
		print("info [map] the region has no navigation_mesh at all")
		return
	print(
		(
			"info [map] mesh %d verts / %d polys, cell %.3f x %.3f"
			% [mesh.vertices.size(), mesh.get_polygon_count(), mesh.cell_size, mesh.cell_height]
		)
	)
	print(
		(
			"info [map] map cell %.3f, %d region(s), active %s, region on map %s"
			% [
				NavigationServer3D.map_get_cell_size(map),
				NavigationServer3D.map_get_regions(map).size(),
				NavigationServer3D.map_is_active(map),
				NavigationServer3D.region_get_map(baker.get_rid()) == map,
			]
		)
	)


func _check_bake(baker: WallNavmeshBaker) -> void:
	var stats := baker.stats()
	var cells: int = stats["cells"]
	var quads: int = stats["quads"]
	if quads == 0:
		_fail("bake", "nothing was baked - the corridors' CSG collision was not there yet")
		return
	if stats["leaked"]:
		_fail("bake", "the flood fill hit its cell budget: the hull has a hole in it")
		return
	_pass("bake", "%d quads over %d open cells" % [quads, cells])


## Somewhere in every limb of the network, so a corridor that failed to generate
## or failed to be reached by the fill shows up as a hole rather than as a chase
## that mysteriously takes the long way round.
func _check_coverage(map: RID) -> void:
	var probes := {
		"trunk floor": Vector3(0.0, -4.0, 20.0),
		"trunk ceiling": Vector3(0.0, 4.0, 20.0),
		"trunk wall": Vector3(-4.0, 0.0, 20.0),
		"trunk far end": Vector3(0.0, -4.0, -40.0),
		"mid branch": Vector3(20.0, -4.0, 0.0),
		"far junction": Vector3(36.0, -4.0, 0.0),
		"lower loop": Vector3(40.0, -4.0, 20.0),
		"loop return": Vector3(0.0, -4.0, 35.0),
		"shaft wall": Vector3(-4.0, 15.0, -45.0),
		"upper deck": Vector3(20.0, 26.0, -45.0),
		"descent": Vector3(36.0, 15.0, -45.0),
	}
	# Every probe sits a metre off a surface, never in mid-corridor. A 10 m tube
	# puts its centreline 5 m from everything, which reads as a hole in the mesh.
	for probe_name: String in probes:
		var probe: Vector3 = probes[probe_name]
		var landed := NavigationServer3D.map_get_closest_point(map, probe)
		var gap := probe.distance_to(landed)
		if gap > COVERAGE_TOLERANCE:
			_fail("coverage", "%s: nearest mesh is %.1f m away at %v" % [probe_name, gap, landed])
		else:
			_pass("coverage", "%s covered (%.2f m)" % [probe_name, gap])


## Each route crosses something the mesh only survives if the grid welded it: a
## tube's inside surface wraps floor to wall to ceiling, junctions are two tubes
## meeting at right angles, and the shaft turns the floor into a wall for 30 m.
func _check_connectivity(map: RID) -> void:
	_check_route(map, "around the tube", Vector3(0, -5, 20), Vector3(0, 5, 20))
	_check_route(map, "along the trunk", Vector3(0, 0, 40), Vector3(0, 0, -40))
	_check_route(map, "through the mid junction", Vector3(0, 0, 20), Vector3(36, 0, 0))
	_check_route(map, "round the lower loop", Vector3(0, 0, 30), Vector3(40, 0, 20))
	_check_route(map, "up the shaft", Vector3(0, 0, -40), Vector3(0, 25, -45))
	_check_route(map, "creature to player", ChaseKnobs.CREATURE_SPAWN, ChaseKnobs.PLAYER_SPAWN)


func _check_route(map: RID, tag: String, from: Vector3, to: Vector3) -> void:
	var start := NavigationServer3D.map_get_closest_point(map, from)
	var goal := NavigationServer3D.map_get_closest_point(map, to)

	# Guard against the degenerate pass: on an empty map both ends collapse onto
	# the origin, and a zero-length path between two identical points otherwise
	# satisfies every check below.
	if start.distance_to(goal) < 1.0:
		_fail("connectivity", "%s: both ends resolved to %v - the map is empty" % [tag, start])
		return

	var path := NavigationServer3D.map_get_path(map, start, goal, true)
	if path.size() < 2:
		_fail("connectivity", "%s: no path at all" % tag)
		return

	var arrived := path[path.size() - 1].distance_to(goal)
	if arrived > ARRIVAL_TOLERANCE:
		_fail(
			"connectivity",
			(
				"%s: path stops %.1f m short - the mesh is not welded across that boundary"
				% [tag, arrived]
			)
		)
		return

	var walked := 0.0
	for i: int in range(1, path.size()):
		walked += path[i - 1].distance_to(path[i])
	_pass(
		"connectivity",
		(
			"%s: %d corners, %.1f m walked vs %.1f m straight"
			% [tag, path.size(), walked, start.distance_to(goal)]
		)
	)


func _on_tentacle_planted(_strand: int, _position: Vector3, impact: float) -> void:
	_plants += 1
	_softest = minf(_softest, impact)
	_hardest = maxf(_hardest, impact)


func _any_voice_playing(impact_audio: TentacleImpactAudio) -> bool:
	for voice: Node in impact_audio.get_children():
		if voice is AudioStreamPlayer3D and (voice as AudioStreamPlayer3D).playing:
			return true
	return false


## The tentacle-hit event, and the thud hung off it.
##
## Asserting the SPREAD of impact, not just that the signal fired. A signal that
## reports the same number every time drives a bank of identical thuds, which is
## the failure mode that matters here - eight limbs landing on one note reads as a
## machine gun rather than as an animal.
func _check_impact_audio(impact_audio: TentacleImpactAudio, heard: bool) -> void:
	if _plants == 0:
		_fail("audio", "tentacle_planted never fired - no tentacle registered hitting a wall")
		return
	_pass("audio", "tentacle_planted fired %d times" % _plants)

	if _hardest - _softest < 0.15:
		_fail(
			"audio",
			"impact only ranged %.2f to %.2f: every thud will sound alike" % [_softest, _hardest]
		)
	else:
		_pass("audio", "impact ranged %.2f to %.2f of reach" % [_softest, _hardest])

	# A one-shot that loops is the nastiest failure available here: the .import
	# says "Detect From WAV" rather than an explicit Disabled, six voices would
	# latch on forever, and the "a voice played" test above would still pass while
	# the creature droned. See the loop_mode gotcha in the placeholder audio skill.
	for clip: AudioStream in TentacleImpactAudio.CLIPS:
		var wav := clip as AudioStreamWAV
		if wav != null and wav.loop_mode != AudioStreamWAV.LOOP_DISABLED:
			_fail(
				"audio",
				"%s loops; a one-shot thud would never stop" % clip.resource_path.get_file()
			)
			return
	_pass("audio", "all %d clips are one-shot" % TentacleImpactAudio.CLIPS.size())

	var voices := 0
	for voice: Node in impact_audio.get_children():
		if voice is AudioStreamPlayer3D:
			voices += 1
	if voices == 0:
		_fail("audio", "the impact audio node built no voices")
	elif not heard:
		_fail("audio", "%d voices exist but none ever played a thud" % voices)
	else:
		_pass("audio", "%d voices, at least one playing during the run" % voices)

	_check_cave_audio(impact_audio)


## The cave the thuds are supposed to be echoing around in.
##
## Every failure here is INAUDIBLE IN THE RUN THAT CAUSES IT, which is the only
## reason this is worth asserting. The creature keeps making noise whatever these
## come out as - the bus falls back to Master, the voices fall back to dry, a
## doubled chain only doubles the tail on the NEXT run - so there is nothing to
## notice while the thing is quietly wrong.
func _check_cave_audio(impact_audio: TentacleImpactAudio) -> void:
	var index := AudioServer.get_bus_index(ChaseKnobs.CAVE_BUS)
	if index < 0:
		_fail("cave", "no bus named %s - the corridors will sound dry" % ChaseKnobs.CAVE_BUS)
		return

	var send := AudioServer.get_bus_send(index)
	if send != ChaseKnobs.CAVE_SEND_BUS:
		# Sending anywhere but SFX takes the cave out from under the options
		# menu's volume slider, which is a bug nobody finds by listening.
		_fail(
			"cave",
			"%s sends to %s, not to %s" % [ChaseKnobs.CAVE_BUS, send, ChaseKnobs.CAVE_SEND_BUS]
		)
	else:
		_pass("cave", "%s sends to %s" % [ChaseKnobs.CAVE_BUS, send])

	# The count, not just the presence, and that is the point of this one. The
	# AudioServer outlives the SceneTree, so an install() that appended instead of
	# rebuilding would leave two reverbs stacked after a single scene reload.
	var effects := AudioServer.get_bus_effect_count(index)
	var reverbs := 0
	var delays := 0
	for slot: int in effects:
		var effect := AudioServer.get_bus_effect(index, slot)
		if effect is AudioEffectReverb:
			reverbs += 1
		elif effect is AudioEffectDelay:
			delays += 1
	if effects != CaveReverbBus.EFFECT_COUNT or reverbs != 1 or delays != 1:
		_fail(
			"cave",
			(
				"%s carries %d effect(s) (%d reverb, %d delay); expected exactly one of each"
				% [ChaseKnobs.CAVE_BUS, effects, reverbs, delays]
			)
		)
	else:
		_pass("cave", "%s carries one delay then one reverb" % ChaseKnobs.CAVE_BUS)

	# Did the _enter_tree push actually beat the crawler's _ready? TentacleImpactAudio
	# reads its bus once, when it builds the voices, so this is the only place the
	# ordering shows up at all.
	var routed := 0
	var strays := 0
	var nearest_fade := INF
	for voice: Node in impact_audio.get_children():
		var player := voice as AudioStreamPlayer3D
		if player == null:
			continue
		nearest_fade = minf(nearest_fade, player.max_distance)
		if player.bus == ChaseKnobs.CAVE_BUS:
			routed += 1
		else:
			strays += 1
	if strays > 0 or routed == 0:
		_fail(
			"cave",
			(
				"%d of %d voices are on %s - the bus was pushed after the voices were built"
				% [routed, routed + strays, ChaseKnobs.CAVE_BUS]
			)
		)
	else:
		_pass("cave", "all %d voices play on %s" % [routed, ChaseKnobs.CAVE_BUS])

	# Read off a VOICE, not off the export. Attenuation happens before the bus, so
	# a voice still fading out at the shipped 40 m is one the reverb can never
	# reach - the cave would say nothing about a creature at the far end of the
	# 90 m trunk, which is most of what it is here to do.
	if nearest_fade < ChaseKnobs.CREATURE_AUDIO_MAX_DISTANCE:
		_fail(
			"cave",
			(
				"a voice fades out at %.0f m, not %.0f - the far end of the trunk is silent"
				% [nearest_fade, ChaseKnobs.CREATURE_AUDIO_MAX_DISTANCE]
			)
		)
	else:
		_pass("cave", "thuds carry %.0f m" % nearest_fade)


## Drive it, and see whether the creature actually gets here.
##
## A path existing on the mesh is not the same as the creature being able to walk
## it. The failure this guards against is the creature stalling somewhere the
## marker sails through - which is what a passage narrower than its comfort
## radius does, and which no amount of querying the navmesh would ever reveal.
func _check_transit(scene: Node) -> void:
	var crawler: CrawlerBody = scene.get_node("Crawler")
	var follower: ChaseTargetFollower = scene.get_node("ChaseTargetFollower")
	var contact: CreatureContact = scene.get_node("Crawler/CreatureContact")
	var tentacles: TentacleArray = scene.get_node("Crawler/Tentacles")
	var impact_audio: TentacleImpactAudio = scene.get_node("Crawler/ImpactAudio")
	var player: Node3D = scene.get_node("CarrierPlayer")

	if not follower.enabled:
		_fail("transit", "the follower was never enabled - the bake await did not complete")
		return

	tentacles.tentacle_planted.connect(_on_tentacle_planted)
	var heard := false

	var seconds := float(TRANSIT_FRAMES) / Engine.physics_ticks_per_second
	var opening := crawler.global_position.distance_to(player.global_position)
	var start_height := crawler.global_position.y
	var travelled := 0.0
	var previous := crawler.global_position
	var closest := opening
	var stalled_at := Vector3.INF
	var stalled_for := 0
	var worst_stall := 0
	var worst_stall_at := Vector3.ZERO

	for _i: int in TRANSIT_FRAMES:
		await get_tree().physics_frame
		var here := crawler.global_position
		# A catch teleports the creature back to its spawn to start again, and
		# that jump is not distance it travelled.
		var step := previous.distance_to(here)
		if step < 5.0:
			travelled += step
		closest = minf(closest, here.distance_to(player.global_position))
		if not heard:
			heard = _any_voice_playing(impact_audio)
		# A creature that has not moved a body length in seconds is snagged, and
		# WHERE it snagged is the useful half: junctions and the shaft mouth are
		# the places to look, and this is what points at them.
		if here.distance_to(stalled_at) > 2.0:
			stalled_at = here
			stalled_for = 0
		else:
			stalled_for += 1
			if stalled_for > worst_stall:
				worst_stall = stalled_for
				worst_stall_at = here
		previous = here

	var descended := start_height - crawler.global_position.y
	_check_impact_audio(impact_audio, heard)

	_pass(
		"transit",
		(
			"creature covered %.0f m in %.0f s, descended %.0f m, longest pause %.1f s at %v"
			% [
				travelled,
				seconds,
				descended,
				float(worst_stall) / Engine.physics_ticks_per_second,
				worst_stall_at.snappedf(1.0),
			]
		)
	)

	# Catching a stationary player is the real bar, and it is stricter than
	# closing the distance. The creature can cross the whole network, arrive, and
	# still never touch you: it settles at the sum of the marker's standoff off
	# the wall and the slack in its own leash, and if that sum is larger than
	# CATCH_RADIUS the fail state is decorative. Both numbers carry a comment
	# about it in chase_knobs.gd.
	if contact.catch_count() > 0:
		_pass(
			"transit",
			"caught the player %d time(s), closest %.1f m" % [contact.catch_count(), closest]
		)
	elif closest > opening * TRANSIT_CLOSE_FRACTION:
		_fail(
			"transit",
			(
				(
					"the creature got no closer than %.0f m of %.0f m in %.0f s: it is stuck "
					+ "somewhere between the upper deck and the trunk"
				)
				% [closest, opening, seconds]
			)
		)
	else:
		_fail(
			"transit",
			(
				(
					"the creature reached %.1f m but never caught a stationary player: "
					+ "CATCH_RADIUS is %.1f m and the chase settles further out than that"
				)
				% [closest, ChaseKnobs.CATCH_RADIUS]
			)
		)
