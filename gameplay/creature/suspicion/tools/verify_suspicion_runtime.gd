extends Node

## Everything the GUT suite structurally cannot check: the wires between this module
## and the engine, and the two modules meeting over real geometry.
##
##   godot --headless --path <root> \
##     res://gameplay/creature/suspicion/tools/verify_suspicion_runtime.tscn
##
## RUN IT AS A .tscn, NOT AS `--script`. Nodes added during SceneTree._initialize()
## never receive _ready(), so a bare script would run nothing, print nothing and exit 0
## -- indistinguishable from a pass.
##
## The GUT suite drives advance() by hand, so every timing assertion in it passes
## perfectly against a facade whose _physics_process was deleted -- and belief would
## then never decay in a real game. That wire can only be seen from here.
##
## The other thing only this file can see is Suspicion meeting a REAL noise through a
## REAL wall. The unit suite hands Suspicion the uncertainty radius it expects; this
## one lets Jolt and the hearing model decide, and checks that a muffled noise still
## produces an area to search rather than a point to walk to.

## project.godot names bit 1 "hull". PerceptionConfig.world_mask defaults to it.
const WALL_LAYER: int = 1
const WALL_THICKNESS: float = 1.0

var _failures: int = 0


func _ready() -> void:
	_build_world()
	await get_tree().physics_frame
	await get_tree().physics_frame

	await _check_physics_process_drives_the_clock()
	await _check_a_real_noise_becomes_a_real_belief()
	await _check_a_muffled_noise_produces_an_area_not_a_point()
	await _check_the_investigate_loop_closes()
	await _check_sandbox_runs()

	if _failures > 0:
		print("FAILED: %d check(s)" % _failures)
	else:
		print("all checks passed")
	get_tree().quit(1 if _failures > 0 else 0)


## A corridor with a slab across it at z = -10, so a noise at z = -20 is behind a wall
## from the origin. Hand-built rather than generated so the numbers below are readable
## straight off the geometry.
func _build_world() -> void:
	_add_wall(Vector3(-3.0, 0, 0), Vector3(WALL_THICKNESS, 8, 60))
	_add_wall(Vector3(3.0, 0, 0), Vector3(WALL_THICKNESS, 8, 60))
	_add_wall(Vector3(0, 0, -10), Vector3(6, 8, WALL_THICKNESS))


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
	add_child(body)


## NO GUT TEST CAN SEE THIS. Every decay assertion in tests/ drives advance() directly,
## so all of them pass against a facade whose _physics_process was deleted -- and the
## creature would then stay suspicious of a footstep forever.
func _check_physics_process_drives_the_clock() -> void:
	var before: int = _failures
	var suspicion := CreatureSuspicion.new()
	suspicion.config = SuspicionConfig.new()
	add_child(suspicion)

	var started: float = suspicion.clock
	for _i: int in 30:
		await get_tree().physics_frame
	var moved: float = suspicion.clock - started

	if moved <= 0.0:
		_fail("tick", "the clock did not advance; _physics_process is not calling advance()")
	elif absf(moved - 0.5) > 0.1:
		_fail("tick", "30 physics frames advanced the clock %.3fs, expected about 0.5s" % moved)
	print("[tick] 30 physics frames advanced the clock %.3fs" % moved)
	suspicion.queue_free()
	_pass_if("tick", before, "_physics_process drives the suspicion clock in real time")


## Perception and Suspicion in one tree, over real geometry, with the two-line wiring
## the READMEs promise. An inverted collision mask or an unbound probe shows up here
## and nowhere in the fast suite.
func _check_a_real_noise_becomes_a_real_belief() -> void:
	var before: int = _failures
	var pair: Array = await _wired_pair()
	var perception: CreaturePerception = pair[0]
	var suspicion: CreatureSuspicion = pair[1]

	perception.receive_noise(NoiseEvent.make(Vector3(0, 0, -4), 1.0, &"drill"))
	await _tick(4)

	var hotspot: SuspicionHotspot = suspicion.get_strongest_hotspot()
	if hotspot == null:
		_fail("belief", "a real noise down an open corridor produced no hotspot")
	else:
		print("[belief] hotspot %.2f, radius %.1fm" % [hotspot.suspicion, hotspot.radius])
		if hotspot.suspicion <= 0.0:
			_fail("belief", "the hotspot formed with no suspicion in it")
	_free_pair(pair)
	_pass_if("belief", before, "a real noise becomes a real hotspot")


## THE CHECK THIS FILE EXISTS FOR. perception/README.md: if a muffled distant noise and
## a clear near one produce the same uncertainty, hearing is handing Suspicion magically
## precise coordinates and the whole searching layer above it has nothing to do.
## The muffled side needs several noises, and that is the point rather than a fudge: a
## single drill stroke through a wall arrives at about 0.02 effective strength, which is
## remembered but is deliberately not enough to form a hotspot on its own. Sustained
## drilling accumulates into one. A player who wants to stay unnoticed through a wall
## has to stop drilling.
func _check_a_muffled_noise_produces_an_area_not_a_point() -> void:
	var before: int = _failures
	var near_radius: float = await _hotspot_radius_for(Vector3(0, 0, -3), 1)
	var through_the_wall: float = await _hotspot_radius_for(Vector3(0, 0, -12), 5)

	if near_radius <= 0.0 or through_the_wall <= 0.0:
		_fail("uncertainty", "one of the two noises produced no hotspot at all")
	elif through_the_wall <= near_radius * 1.5:
		_fail(
			"uncertainty",
			(
				(
					"a noise behind a wall produced a %.1fm hotspot against %.1fm for a clear one; "
					+ "Suspicion is being handed exact coordinates"
				)
				% [through_the_wall, near_radius]
			)
		)
	print("[uncertainty] near %.1fm, through the divider %.1fm" % [near_radius, through_the_wall])
	_pass_if("uncertainty", before, "real obstruction produces a real area to search")


## The whole cycle, with Behavior's part played by four lines: believe, go and look,
## observe nothing, believe less. Nothing anywhere subtracts a suspicion value.
func _check_the_investigate_loop_closes() -> void:
	var before: int = _failures
	var pair: Array = await _wired_pair()
	var perception: CreaturePerception = pair[0]
	var suspicion: CreatureSuspicion = pair[1]

	perception.receive_noise(NoiseEvent.make(Vector3(0, 0, -4), 1.0, &"drill"))
	await _tick(4)
	var hotspot: SuspicionHotspot = suspicion.get_strongest_hotspot()
	if hotspot == null:
		_fail("loop", "nothing to investigate")
		_free_pair(pair)
		return

	var believed: float = suspicion.get_overall_suspicion()
	var target: Vector3 = suspicion.get_best_unresolved_location(hotspot.id)
	perception.request_activity_scan(AABB(target - Vector3.ONE * 3.0, Vector3.ONE * 6.0), 1.0)

	var guard: int = 0
	while not perception.is_activity_scan_complete() and guard < 1200:
		await get_tree().physics_frame
		guard += 1
	await _tick(4)

	var after: float = suspicion.get_overall_suspicion()
	# investigation_progress alongside the suspicion drop, because `suspicion` is
	# saturated: at high belief a large amount of cleared evidence shows up as a small
	# movement in the reported number, and only the raw figure says how much of the
	# hotspot the creature actually accounted for.
	var searched: float = 0.0
	var remaining: SuspicionHotspot = suspicion.get_hotspot(hotspot.id)
	if remaining != null:
		searched = remaining.investigation_progress
	if guard >= 1200:
		_fail("loop", "the search never completed under a real physics tick")
	elif suspicion.memory.disconfirmations.is_empty():
		_fail("loop", "a fruitless search produced no disconfirmation record")
	elif after >= believed:
		_fail("loop", "searching where it believed left suspicion at %.2f" % after)
	elif remaining != null and searched <= 0.2:
		_fail("loop", "the search accounted for only %d%% of the hotspot" % int(searched * 100.0))
	print(
		(
			"[loop] believed %.2f, searched, now %.2f (%d%% of the hotspot accounted for)"
			% [believed, after, int(searched * 100.0)]
		)
	)
	_free_pair(pair)
	_pass_if("loop", before, "believe -> look -> find nothing -> believe less")


## Every assertion above passes against an overlay that renders as nothing at all, so
## this cannot prove the sandbox LOOKS right. It can prove the thing runs, ticks and
## does not error -- which is the failure that would otherwise be discovered by opening
## it.
func _check_sandbox_runs() -> void:
	var before: int = _failures
	var packed: PackedScene = load(
		"res://gameplay/creature/suspicion/sandbox/suspicion_sandbox.tscn"
	)
	if packed == null:
		_fail("sandbox", "the sandbox scene did not load")
		return
	var sandbox: Node = packed.instantiate()
	if sandbox.get_script() == null:
		_fail("sandbox", "the sandbox instantiated without its script")
		return
	add_child(sandbox)
	await _tick(20)

	var suspicion := sandbox.get_node_or_null("CreatureSuspicion") as CreatureSuspicion
	var perception := (
		sandbox.get_node_or_null("PerceptionSandbox/CreaturePerception") as CreaturePerception
	)
	if suspicion == null:
		_fail("sandbox", "the sandbox built no CreatureSuspicion")
	elif perception == null:
		_fail("sandbox", "the sandbox did not reach the perception inside the inner scene")
	else:
		if suspicion.clock <= 0.0:
			_fail("sandbox", "the sandbox suspicion's clock never advanced")
		# The wiring itself, asserted rather than assumed: an unconnected signal is a
		# sandbox that looks completely normal and never forms a single belief.
		if not perception.evidence_observed.is_connected(suspicion.submit_evidence):
			_fail("sandbox", "evidence_observed is not wired to submit_evidence")
		if not perception.disconfirmation_observed.is_connected(suspicion.submit_disconfirmation):
			_fail("sandbox", "disconfirmation_observed is not wired to submit_disconfirmation")
	sandbox.queue_free()
	_pass_if("sandbox", before, "the sandbox scene builds, ticks and wires both modules")


# ----- helpers -----


## A CreaturePerception and a CreatureSuspicion in the tree, connected the way the
## READMEs say to connect them.
func _wired_pair(position_jitter: float = 1.0) -> Array:
	var perception := CreaturePerception.new()
	perception.config = PerceptionConfig.new()
	# Off: passive geometry scanning is Spatial Memory's channel and only adds noise to
	# the log here.
	perception.config.geometry_perception_enabled = false
	perception.config.hearing_position_jitter = position_jitter
	var suspicion := CreatureSuspicion.new()
	suspicion.config = SuspicionConfig.new()
	suspicion.config.hotspot_update_interval = 0.0
	perception.evidence_observed.connect(suspicion.submit_evidence)
	perception.disconfirmation_observed.connect(suspicion.submit_disconfirmation)
	add_child(perception)
	add_child(suspicion)
	await get_tree().physics_frame
	return [perception, suspicion]


## Hearing's positional jitter is switched off here, so the hotspot radius is exactly
## the uncertainty the sense reported rather than that plus however far the jitter threw
## the repeated strokes apart. The jitter itself is perception's property and
## perception's own suites cover it; what is under test here is that Suspicion sizes a
## search area to the uncertainty it was handed.
func _hotspot_radius_for(noise_at: Vector3, strokes: int) -> float:
	var pair: Array = await _wired_pair(0.0)
	var perception: CreaturePerception = pair[0]
	var suspicion: CreatureSuspicion = pair[1]
	for _stroke: int in strokes:
		perception.receive_noise(NoiseEvent.make(noise_at, 1.0, &"drill"))
	await _tick(4)
	var hotspot: SuspicionHotspot = suspicion.get_strongest_hotspot()
	var radius: float = hotspot.radius if hotspot != null else 0.0
	_free_pair(pair)
	return radius


func _tick(frames: int) -> void:
	for _i: int in frames:
		await get_tree().physics_frame


func _free_pair(pair: Array) -> void:
	for node: Node in pair:
		node.queue_free()


func _fail(tag: String, message: String) -> void:
	_failures += 1
	printerr("[%s] FAIL  %s" % [tag, message])


func _pass(tag: String, message: String) -> void:
	print("[%-11s] PASS  %s" % [tag, message])


func _pass_if(tag: String, failures_before: int, message: String) -> void:
	if _failures == failures_before:
		_pass(tag, message)
