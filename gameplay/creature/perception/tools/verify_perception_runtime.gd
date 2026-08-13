extends Node

## Everything the GUT suite structurally cannot check: real physics, and the wires
## between the module and the engine.
##
##   godot --headless --path <root> \
##     res://gameplay/creature/perception/tools/verify_perception_runtime.tscn
##
## RUN IT AS A .tscn, NOT AS `--script`. Nodes added during SceneTree._initialize()
## never receive _ready(), so a bare script would run nothing, print nothing and
## exit 0 -- indistinguishable from a pass.
##
## The GUT suite runs every sense against a FakePerceptionProbe with scripted
## answers. That proves the senses agree with the fake; it says nothing about
## whether the fake agrees with Jolt. This file is where those two meet, and where
## an inverted collision mask or an unbound probe finally shows up.
##
## The other thing only this file can see is that _physics_process is actually
## wired to advance(). Every timing test in GUT passes against a facade that never
## ticks at all.

## project.godot names bit 1 "hull". PerceptionConfig.world_mask defaults to it.
const WALL_LAYER: int = 1
const WALL_THICKNESS: float = 1.0
## Corridor half-width; the corridor is therefore 4m across and comfortably wider
## than PerceptionConfig.geometry_min_clearance.
const CORRIDOR_HALF: float = 2.0

var _failures: int = 0
var _probe: PerceptionProbe = null


func _ready() -> void:
	_build_world()
	await get_tree().physics_frame
	await get_tree().physics_frame

	_probe = PerceptionProbe.new()
	_probe.bind(get_viewport().world_3d)

	_check_probe_is_bound()
	_check_line_of_sight()
	_check_obstruction()
	_check_volume_solidity()
	_check_clearance()
	_check_geometry_classification()
	await _check_hearing_through_a_wall()
	await _check_touch_area()
	await _check_physics_process_drives_the_clock()
	await _check_scan_duration_is_real_time()
	await _check_sandbox_runs()

	if _failures > 0:
		print("FAILED: %d check(s)" % _failures)
	else:
		print("all checks passed")
	get_tree().quit(1 if _failures > 0 else 0)


## A north-south corridor 4m wide, walled on both sides, with a solid block across
## the north end. Hand-built rather than generated so the expected numbers below are
## readable straight off the geometry.
func _build_world() -> void:
	_add_wall(Vector3(-CORRIDOR_HALF - WALL_THICKNESS * 0.5, 0, 0), Vector3(WALL_THICKNESS, 8, 40))
	_add_wall(Vector3(CORRIDOR_HALF + WALL_THICKNESS * 0.5, 0, 0), Vector3(WALL_THICKNESS, 8, 40))
	# The divider: a slab at z = -10, so a point at z = -20 is behind it from origin.
	_add_wall(Vector3(0, 0, -10), Vector3(4, 8, WALL_THICKNESS))


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


# ----- the probe against real geometry -----


func _check_probe_is_bound() -> void:
	# An unbound probe answers "clear" to everything, which reads as an omniscient
	# creature rather than as a missing binding.
	if not _probe.is_bound():
		_fail("probe", "the probe did not bind to a World3D")
	else:
		_pass("probe", "bound to the running world")


func _check_line_of_sight() -> void:
	var before: int = _failures
	var here := Vector3(0, 0, 0)
	var down_the_corridor := Vector3(0, 0, -5)
	var past_the_divider := Vector3(0, 0, -20)

	if not _probe.has_clear_line(here, down_the_corridor, WALL_LAYER):
		_fail("los", "open corridor reported as blocked")
	if _probe.has_clear_line(here, past_the_divider, WALL_LAYER):
		_fail("los", "the divider at z=-10 did not block sight to z=-20")
	# The mask, not the geometry, decides. A creature masking the wrong layer sees
	# through walls and nothing errors.
	if not _probe.has_clear_line(here, past_the_divider, 0):
		_fail("los", "a zero mask should hit nothing at all")
	_pass_if("los", before, "sight is clear along the corridor and blocked by the divider")


func _check_obstruction() -> void:
	var before: int = _failures
	var open: float = _probe.obstruction_between(Vector3.ZERO, Vector3(0, 0, -5), WALL_LAYER)
	var through: float = _probe.obstruction_between(Vector3.ZERO, Vector3(0, 0, -20), WALL_LAYER)

	if open != 0.0:
		_fail("obstruction", "open air reported obstruction %.2f" % open)
	if through <= 0.0:
		_fail("obstruction", "a wall between two points reported no obstruction")
	if through > 1.0:
		_fail("obstruction", "obstruction %.2f escaped its 0..1 range" % through)
	print("[obstruction] open %.2f, through the divider %.2f" % [open, through])
	_pass_if("obstruction", before, "obstruction is 0 in open air and positive through a wall")


func _check_volume_solidity() -> void:
	var before: int = _failures
	var in_the_wall := AABB(Vector3(-0.5, -0.5, -10.5), Vector3.ONE)
	var in_the_corridor := AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)

	if not _probe.is_volume_solid(in_the_wall, WALL_LAYER):
		_fail("solid", "a cell inside the divider was not reported solid")
	if _probe.is_volume_solid(in_the_corridor, WALL_LAYER):
		_fail("solid", "a cell in open corridor was reported solid")
	_pass_if("solid", before, "solid cells read solid and open cells read open")


func _check_clearance() -> void:
	var before: int = _failures
	var left: float = _probe.clearance_at(Vector3.ZERO, Vector3.LEFT, WALL_LAYER, 20.0)
	var right: float = _probe.clearance_at(Vector3.ZERO, Vector3.RIGHT, WALL_LAYER, 20.0)
	var width: float = left + right

	# Measured against the geometry above: 2m of corridor either side of the centre.
	if absf(width - CORRIDOR_HALF * 2.0) > 0.2:
		_fail(
			"clearance",
			"corridor measured %.2fm across, expected %.2f" % [width, CORRIDOR_HALF * 2.0]
		)
	var unobstructed: float = _probe.clearance_at(Vector3.ZERO, Vector3.UP, WALL_LAYER, 20.0)
	if unobstructed != 20.0:
		_fail("clearance", "an unobstructed ray returned %.2f, not its max length" % unobstructed)
	print("[clearance] corridor %.2fm across (left %.2f, right %.2f)" % [width, left, right])
	_pass_if("clearance", before, "clearance measures the corridor to within 0.2m")


## The check that catches an inverted collision mask: with the mask wrong, every
## cell comes back FREE and the alien believes it lives in an empty universe.
func _check_geometry_classification() -> void:
	var before: int = _failures
	var geometry := CreatureGeometryPerception.new()
	geometry.config = PerceptionConfig.new()

	var region := AABB(Vector3(-4, -1, -12), Vector3(8, 2, 14))
	var observations := geometry.scan_region(_probe, region, Vector3.ZERO, 8.0, 0.0)

	var solid: int = 0
	var free: int = 0
	for observation: GeometryObservation in observations:
		if observation.type == GeometryObservation.ObservationType.SOLID:
			solid += 1
		elif observation.type == GeometryObservation.ObservationType.FREE:
			free += 1

	if observations.is_empty():
		_fail("geometry", "a scan across real geometry produced nothing")
	if solid == 0:
		_fail("geometry", "no SOLID cells found; the corridor walls were not perceived")
	if free == 0:
		_fail("geometry", "no FREE cells found; the open corridor was not perceived")
	print("[geometry] %d cells: %d solid, %d free" % [observations.size(), solid, free])
	_pass_if("geometry", before, "a real scan finds both the walls and the space between them")


# ----- the facade against real physics -----


func _check_hearing_through_a_wall() -> void:
	var before: int = _failures
	var open_strength: float = await _hear_from(Vector3(0, 0, -5))
	var muffled_strength: float = await _hear_from(Vector3(0, 0, -20))

	if open_strength <= 0.0:
		_fail("hearing", "a noise 5m down an open corridor was not heard at all")
	if muffled_strength >= open_strength:
		_fail(
			"hearing",
			(
				"a noise behind a wall (%.3f) was not quieter than one in the open (%.3f)"
				% [muffled_strength, open_strength]
			)
		)
	print("[hearing] open %.3f, through the divider %.3f" % [open_strength, muffled_strength])
	_pass_if("hearing", before, "real geometry muffles a real noise")


## The same loudness at the same distance, in the open and behind the divider. The
## distances differ, so this compares the direction of the effect, not its size.
func _hear_from(at: Vector3) -> float:
	var creature := CreaturePerception.new()
	creature.config = PerceptionConfig.new()
	creature.config.hearing_position_jitter = 0.0
	add_child(creature)
	await get_tree().physics_frame

	var heard: Array[SuspicionEvidence] = []
	creature.evidence_observed.connect(func(e: SuspicionEvidence) -> void: heard.append(e))
	creature.receive_noise(NoiseEvent.make(at, 1.0, &"drill"))

	var strength: float = heard[0].strength if not heard.is_empty() else 0.0
	creature.queue_free()
	return strength


func _check_touch_area() -> void:
	var before: int = _failures
	var creature := CreaturePerception.new()
	creature.config = PerceptionConfig.new()

	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 1 << 4
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.5
	shape.shape = sphere
	area.add_child(shape)
	creature.proximity_area = area
	creature.add_child(area)
	creature.position = Vector3(0, 0, 5)
	add_child(creature)

	var heard: Array[SuspicionEvidence] = []
	creature.evidence_observed.connect(func(e: SuspicionEvidence) -> void: heard.append(e))
	await get_tree().physics_frame

	var intruder := CharacterBody3D.new()
	intruder.collision_layer = 1 << 4
	intruder.collision_mask = 0
	var intruder_shape := CollisionShape3D.new()
	var intruder_sphere := SphereShape3D.new()
	intruder_sphere.radius = 0.5
	intruder_shape.shape = intruder_sphere
	intruder.add_child(intruder_shape)
	intruder.position = Vector3(0, 0, 5)
	add_child(intruder)

	for _i: int in 8:
		await get_tree().physics_frame

	if heard.is_empty():
		_fail("touch", "an Area3D overlap produced no evidence; the signal is not wired")
	elif heard[0].sense != SuspicionEvidence.Sense.TOUCH:
		_fail("touch", "an overlap produced %s, not TOUCH" % heard[0].sense_name())
	intruder.queue_free()
	creature.queue_free()
	_pass_if("touch", before, "an Area3D overlap becomes TOUCH evidence")


## NO GUT TEST CAN SEE THIS. Every timing assertion in tests/ drives advance()
## directly, so all of them pass perfectly against a facade whose _physics_process
## was deleted -- and the creature would then never perceive anything in a real game.
func _check_physics_process_drives_the_clock() -> void:
	var before: int = _failures
	var creature := CreaturePerception.new()
	creature.config = PerceptionConfig.new()
	add_child(creature)

	var started: float = creature.clock
	for _i: int in 30:
		await get_tree().physics_frame
	var moved: float = creature.clock - started

	if moved <= 0.0:
		_fail("tick", "the clock did not advance; _physics_process is not calling advance()")
	elif absf(moved - 0.5) > 0.1:
		_fail("tick", "30 physics frames advanced the clock %.3fs, expected about 0.5s" % moved)
	print("[tick] 30 physics frames advanced the clock %.3fs" % moved)
	creature.queue_free()
	_pass_if("tick", before, "_physics_process drives the perception clock in real time")


## And the same for the scan machine: a scan must finish in wall-clock seconds when
## nothing but the engine is ticking it.
func _check_scan_duration_is_real_time() -> void:
	var before: int = _failures
	var creature := CreaturePerception.new()
	creature.config = PerceptionConfig.new()
	add_child(creature)
	await get_tree().physics_frame

	var expected: float = creature.config.scan_duration(0.5)
	creature.request_activity_scan(AABB(Vector3(0, -1, -6), Vector3(4, 2, 4)), 0.5)
	var started: float = creature.clock
	var guard: int = 0
	while not creature.is_activity_scan_complete() and guard < 1200:
		await get_tree().physics_frame
		guard += 1
	var took: float = creature.clock - started

	if guard >= 1200:
		_fail("scan", "an activity scan never completed under a real physics tick")
	elif absf(took - expected) > 0.1:
		_fail("scan", "the scan took %.3fs, expected about %.3fs" % [took, expected])
	print("[scan] a thoroughness-0.5 scan took %.3fs (expected %.3f)" % [took, expected])
	creature.queue_free()
	_pass_if("scan", before, "scan duration matches the configured seconds in real time")


## Every geometric assertion above passes against a debug overlay that renders as
## nothing at all, so this cannot prove the sandbox LOOKS right. It can prove the
## thing runs, ticks, and does not error -- which is the failure that would otherwise
## be discovered by opening it.
func _check_sandbox_runs() -> void:
	var before: int = _failures
	var packed: PackedScene = load(
		"res://gameplay/creature/perception/sandbox/perception_sandbox.tscn"
	)
	if packed == null:
		_fail("sandbox", "the sandbox scene did not load")
		return
	var sandbox: Node = packed.instantiate()
	if sandbox.get_script() == null:
		_fail("sandbox", "the sandbox instantiated without its script")
		return
	add_child(sandbox)
	for _i: int in 20:
		await get_tree().physics_frame

	var creature := sandbox.get_node_or_null("CreaturePerception") as CreaturePerception
	if creature == null:
		_fail("sandbox", "the sandbox built no CreaturePerception")
	else:
		if creature.clock <= 0.0:
			_fail("sandbox", "the sandbox creature's clock never advanced")
		if creature.candidate_targets().is_empty():
			_fail("sandbox", "the perceivable group fallback found no stand-in player")
		if not creature.probe.is_bound():
			_fail("sandbox", "the sandbox creature's probe never bound to the world")
	sandbox.queue_free()
	_pass_if("sandbox", before, "the sandbox scene builds, ticks and finds its target")


func _fail(tag: String, message: String) -> void:
	_failures += 1
	printerr("[%s] FAIL  %s" % [tag, message])


func _pass(tag: String, message: String) -> void:
	print("[%-11s] PASS  %s" % [tag, message])


func _pass_if(tag: String, failures_before: int, message: String) -> void:
	if _failures == failures_before:
		_pass(tag, message)
