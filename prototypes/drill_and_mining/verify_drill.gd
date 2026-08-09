extends Node

## Headless check that the voxel rock holds together. Run it as:
##
##     godot --headless --path <root> \
##       res://prototypes/drill_and_mining/verify_drill.tscn
##
## As a SCENE named on the command line, not as `--script` and not bare - this
## builds real nodes and needs them to reach _ready.
##
## [release] AND [mesh] ARE THE CHECKS THIS FILE EXISTS FOR.
##
## The release rule is the one piece of logic here a person cannot see working: a
## hole either frees a crystal or it does not, and a bug where it frees on the
## first frame looks exactly like a generous clearance, while one where it never
## frees looks exactly like a mean one.
##
## The mesher is worse. A surface nets bug that drops quads leaves a hole in the
## rock, and a hole in the rock looks EXACTLY like a winding bug - which is the
## other thing that can go wrong here. Counting triangles and watching them fall
## as rock is removed separates the two before anyone has to squint at a wall.
##
## Nothing here tests how any of it LOOKS. There is no renderer in headless mode.

var _checks := 0
var _failures := 0


func _ready() -> void:
	_verify_field()
	_verify_mesh()
	_verify_carve()
	_verify_release()
	_verify_crystal()
	_verify_spray()
	_verify_debris_cap()
	_verify_heft()
	_report()


## The field starts as a ball of rock that fits inside its own grid.
func _verify_field() -> void:
	var field := _make_field(11)
	var half_extent := field.half_extent()

	_check(
		"[field] the rock fits in the grid",
		DrillKnobs.NODE_RADIUS + DrillKnobs.NODE_SURFACE_NOISE < half_extent,
		(
			"rock reaches %.2f m against a %.2f m half-extent; it would be clipped flat"
			% [DrillKnobs.NODE_RADIUS + DrillKnobs.NODE_SURFACE_NOISE, half_extent]
		)
	)
	_check("[field] the centre is solid", field.sample(Vector3.ZERO) < 0.0, "the node is hollow")
	_check(
		"[field] the corners are empty",
		field.sample(Vector3.ONE * half_extent * 0.99) > 0.0,
		"rock reaches the corner of the grid"
	)

	var solid := field.count_solid_corners()
	var total := (DrillKnobs.FIELD_RESOLUTION + 1) ** 3
	# A ball of radius r in a cube of side 2r*1.2 is about pi/6 / 1.2^3 of it.
	_check(
		"[field] roughly a ball's worth of rock",
		solid > total / 8 and solid < total / 2,
		"%d of %d corners solid, which is not a ball" % [solid, total]
	)


## The mesher produces a closed-looking surface, and every sub-chunk that should
## have triangles has them.
func _verify_mesh() -> void:
	var field := _make_field(12)
	var mesher := SurfaceNetMesher.new()
	var total_triangles := 0
	var subchunks_with_surface := 0
	for z in field.subchunks_per_axis:
		for y in field.subchunks_per_axis:
			for x in field.subchunks_per_axis:
				var normals := PackedVector3Array()
				var triangles := mesher.build(field, Vector3i(x, y, z), normals)
				_checks += 1
				if triangles.size() % 3 != 0 or triangles.size() != normals.size():
					_failures += 1
					printerr(
						(
							"  FAIL  [mesh] sub-chunk %d,%d,%d: %d vertices, %d normals"
							% [x, y, z, triangles.size(), normals.size()]
						)
					)
					return
				total_triangles += triangles.size() / 3
				if not triangles.is_empty():
					subchunks_with_surface += 1
	print("  PASS  [mesh] every sub-chunk returns whole triangles with matching normals")

	_check(
		"[mesh] the ball has a surface",
		total_triangles > 200,
		"only %d triangles across the whole node" % total_triangles
	)
	# The rock is a ball inside a cube: the sub-chunks at the middle of a face and
	# at the centre are the ones that can legitimately hold no surface.
	_check(
		"[mesh] the surface is spread over the node",
		subchunks_with_surface >= 8,
		(
			"only %d of %d sub-chunks hold any surface"
			% [subchunks_with_surface, field.subchunks_per_axis ** 3]
		)
	)


## Carving removes rock, dirties only what it touched, and stops mattering once
## the hole is already there.
func _verify_carve() -> void:
	var field := _make_field(13)
	field.take_dirty(1_000_000)

	var before := field.count_solid_corners()
	var carved := field.erode(Vector3.ZERO, 0.3, 5.0)
	_check("[carve] a carve reports it did something", carved, "erode returned false on solid rock")
	var after := field.count_solid_corners()
	_check(
		"[carve] rock actually goes",
		after < before,
		"%d corners solid before, %d after" % [before, after]
	)

	var dirty := field.take_dirty(1_000_000)
	_check("[carve] the carve dirties something", not dirty.is_empty(), "nothing was queued")
	_check(
		"[carve] the carve does not dirty the whole node",
		dirty.size() < field.subchunks_per_axis ** 3,
		"a 0.3 m carve queued all %d sub-chunks" % dirty.size()
	)

	# Enough passes that the field there is at its ceiling. A beam left pointing
	# into a finished hole must stop queueing remeshes, or it burns the frame
	# budget for ever.
	for _pass in 200:
		field.erode(Vector3.ZERO, 0.3, 5.0)
	field.take_dirty(1_000_000)
	_check(
		"[carve] carving a hole that is already there is free",
		not field.erode(Vector3.ZERO, 0.3, 5.0),
		"the field is still being written after it has bottomed out"
	)


## A tube cut straight out from the crystal frees it, and nothing less does.
func _verify_release() -> void:
	var ore_node := _make_node(14)
	_check(
		"[release] crystal starts held", not ore_node.is_crystal_free(), "freed before any drilling"
	)

	# One pass of erosion, deep enough to matter but nowhere near a tunnel.
	var direction := Vector3.FORWARD
	ore_node.carve(
		ore_node.global_position + direction * DrillKnobs.NODE_RADIUS, DrillKnobs.CARVE_RADIUS, 0.2
	)
	ore_node.apply_tuning(DrillKnobs.ESCAPE_CLEARANCE)
	_run_pending(ore_node)
	_check(
		"[release] a scratch is not enough",
		not ore_node.is_crystal_free(),
		"one shallow carve freed the crystal; the clearance test is not testing anything"
	)

	# Now cut all the way from the crystal's surface out through the rock, in
	# steps small enough that the bores overlap into a tube.
	var step := DrillKnobs.CARVE_RADIUS * 0.5
	var travelled := DrillKnobs.CRYSTAL_RADIUS
	while travelled < DrillKnobs.NODE_RADIUS + DrillKnobs.NODE_SURFACE_NOISE + step:
		for _pass in 40:
			ore_node.carve(
				ore_node.global_position + direction * travelled, DrillKnobs.CARVE_RADIUS, 0.2
			)
		travelled += step
	_run_pending(ore_node)

	_check(
		"[release] a tube out frees the crystal",
		ore_node.is_crystal_free(),
		"a bore was cut from the crystal to open space and the rock still has it"
	)
	_check(
		"[release] the rest of the rock is still standing",
		ore_node.get_rock_fraction() > 0.4,
		(
			"%.0f%% left; the whole node was removed, so this proves nothing"
			% (ore_node.get_rock_fraction() * 100.0)
		)
	)
	var crystal := ore_node.get_crystal()
	_check(
		"[release] crystal changes layer",
		crystal.collision_layer == DrillKnobs.CRYSTAL_LAYER,
		(
			"layer is %d, wanted %d - the collector will never see it"
			% [crystal.collision_layer, DrillKnobs.CRYSTAL_LAYER]
		)
	)
	_check(
		"[release] crystal cannot wedge in the rubble",
		crystal.collision_mask == DrillKnobs.HULL_LAYER,
		"mask is %d, wanted %d" % [crystal.collision_mask, DrillKnobs.HULL_LAYER]
	)
	_check(
		"[release] crystal is no longer frozen", not crystal.freeze, "it is free but cannot move"
	)
	ore_node.queue_free()


## The beam stops on the crystal, and carving cannot reach it.
func _verify_crystal() -> void:
	var ore_node := _make_node(15)
	var origin := ore_node.global_position + Vector3(0.0, 0.0, 4.0)
	var aim := Vector3.FORWARD

	var first := ore_node.cast(origin, aim, 8.0)
	_check("[crystal] the beam hits the node at all", not first.is_empty(), "the ray missed")
	if not first.is_empty():
		_check(
			"[crystal] rock is hit before the crystal is",
			not first["is_crystal"],
			"the ray reached the crystal through solid rock"
		)

	# Cut in until the crystal is what is in front of the beam.
	var travelled := DrillKnobs.NODE_RADIUS
	while travelled > DrillKnobs.CRYSTAL_RADIUS:
		for _pass in 40:
			ore_node.carve(
				ore_node.global_position + aim * -travelled, DrillKnobs.CARVE_RADIUS, 0.2
			)
		travelled -= DrillKnobs.CARVE_RADIUS * 0.5
	var through := ore_node.cast(origin, aim, 8.0)
	_check("[crystal] the beam still stops on something", not through.is_empty(), "the ray missed")
	if not through.is_empty():
		_check(
			"[crystal] the beam stops on the crystal",
			through["is_crystal"],
			"the bore reached the crystal and the ray went straight past it"
		)
	ore_node.queue_free()


## The spray comes back out of the hole rather than into it.
##
## A sign error in the field's gradient costs nothing visible except this: every
## fragment leaves along the beam, buries itself in rock it does not collide
## with, and the drill looks like it has stopped throwing anything. Cheap to
## assert, and the symptom would send you looking at the pool.
func _verify_spray() -> void:
	var ore_node := _make_node(23)
	var origin := ore_node.global_position + Vector3(0.0, 0.0, 4.0)
	var aim := Vector3.FORWARD

	var hit := ore_node.cast(origin, aim, 8.0)
	_check("[spray] the beam hits the node at all", not hit.is_empty(), "the ray missed")
	if not hit.is_empty():
		var surface_normal: Vector3 = hit["normal"]
		_check(
			"[spray] the surface faces the beam it was hit by",
			surface_normal.dot(aim) < 0.0,
			"normal %v against aim %v; the gradient points into the rock" % [surface_normal, aim]
		)
		# Straight at an unbroken ball, the reflection is very nearly straight
		# back. Anything with a forward component is a fragment thrown into rock.
		_check(
			"[spray] rock leaves the hole rather than entering it",
			aim.bounce(surface_normal).dot(aim) < 0.0,
			"the reflection still runs along the beam"
		)
	ore_node.queue_free()


## The pool caps what is in the room, and never refuses a fragment.
func _verify_debris_cap() -> void:
	var pool := OreDebrisPool.new()
	add_child(pool)
	var overflow := DrillKnobs.DEBRIS_POOL_SIZE + 5
	for _index in overflow:
		pool.launch(Vector3.ZERO, Vector3.FORWARD, randf())
	_check(
		"[debris] the pool caps the room",
		pool.get_active_count() <= DrillKnobs.DEBRIS_POOL_SIZE,
		"%d live against a pool of %d" % [pool.get_active_count(), DrillKnobs.DEBRIS_POOL_SIZE]
	)
	_check(
		"[debris] the cap does not refuse a fragment",
		pool.get_active_count() == DrillKnobs.DEBRIS_POOL_SIZE,
		(
			"%d live after %d launches; the oldest is not being recycled"
			% [pool.get_active_count(), overflow]
		)
	)
	pool.clear()
	_check(
		"[debris] clear empties it",
		pool.get_active_count() == 0,
		"%d survived a clear" % pool.get_active_count()
	)
	pool.queue_free()


## Heft actually reaches the fragment, and reaches all four of the things it is
## supposed to.
##
## Worth asserting because the failure is silent: heft that is computed, passed,
## and then dropped on one of the four leaves a spray that still works and is
## merely less interesting than it was meant to be. Nothing would ever point at
## it.
func _verify_heft() -> void:
	var pool := OreDebrisPool.new()
	add_child(pool)
	pool.launch(Vector3.ZERO, Vector3.FORWARD, 0.0)
	var grit := pool.describe_newest()
	pool.launch(Vector3.ZERO, Vector3.FORWARD, 1.0)
	var slab := pool.describe_newest()

	_check(
		"[heft] a long wait is a bigger fragment",
		slab["volume"] > grit["volume"],
		"%.5f m^3 against %.5f" % [slab["volume"], grit["volume"]]
	)
	_check(
		"[heft] a long wait is a heavier fragment",
		slab["mass"] > grit["mass"],
		"%.2f kg against %.2f" % [slab["mass"], grit["mass"]]
	)
	_check(
		"[heft] a heavier fragment leaves slower",
		slab["speed"] < grit["speed"],
		(
			"%.2f m/s against %.2f; the impulse is not being divided by the mass"
			% [slab["speed"], grit["speed"]]
		)
	)
	_check(
		"[heft] a heavier fragment lasts longer",
		slab["life"] > grit["life"],
		"%.2f s against %.2f" % [slab["life"], grit["life"]]
	)
	pool.clear()
	pool.queue_free()


func _make_field(field_seed: int) -> VoxelField:
	var rng := RandomNumberGenerator.new()
	rng.seed = field_seed
	var field := VoxelField.new(
		DrillKnobs.FIELD_RESOLUTION, DrillKnobs.VOXEL_SIZE, DrillKnobs.SUBCHUNK_CELLS
	)
	field.fill_sphere(DrillKnobs.NODE_RADIUS, DrillKnobs.NODE_SURFACE_NOISE, rng)
	return field


func _make_node(node_seed: int) -> OreNode:
	var ore_node := OreNode.new()
	add_child(ore_node)
	ore_node.build(node_seed, 1.0, DrillKnobs.ESCAPE_CLEARANCE)
	return ore_node


## The escape test runs from _process, which never fires inside a single _ready.
func _run_pending(ore_node: OreNode) -> void:
	ore_node.run_pending_work()


func _check(check_name: String, passed: bool, detail: String) -> void:
	_checks += 1
	if passed:
		print("  PASS  %s" % check_name)
		return
	_failures += 1
	printerr("  FAIL  %s: %s" % [check_name, detail])


func _report() -> void:
	print("%d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
