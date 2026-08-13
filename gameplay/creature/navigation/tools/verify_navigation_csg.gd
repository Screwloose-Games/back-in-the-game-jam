extends Node3D

## Pins what `NavigationProbe.is_solid` can and cannot answer, against real colliders.
##
##   godot --headless --path <root> \
##     res://gameplay/creature/navigation/tools/verify_navigation_csg.tscn
##
## RUN IT AS THE .tscn, NOT WITH --script, for the reason verify_navigation_runtime.gd
## spells out: a node added during SceneTree._initialize() never receives _ready().
##
## WHY THIS FILE EXISTS. `is_solid` is exact for convex colliders and impossible for
## concave ones, and neither half of that is something Godot promises in writing. Every
## other scene in this module -- the sandbox cave, every fixture in tests/ -- is built
## from convex BoxShape3D, so nothing else in CI ever puts a trimesh in front of the
## probe. This file does, and asserts all three measured behaviours, so that the day a
## Godot or Jolt release changes one of them the suite says so instead of an alien
## quietly standing inside a wall.
##
## THE THREE MEASUREMENTS, taken on Godot 4.7.1 with Jolt:
##
##   convex, ray starts inside              -> hit AT the ray origin, normal (0, 0, 0)
##   CSG trimesh, ray starts inside rock    -> NO HIT (back faces are not reported)
##   trimesh with backface_collision = true -> hit, but the normal is FLIPPED to face the
##                                             ray, making it byte-identical to a
##                                             legitimate front-face hit from open space
##
## Only the first is usable. The second and third are why `is_solid` does not attempt a
## concave answer, and why a CSG greybox that wants exact navigation should draw with CSG
## and collide with generated convex boxes.
##
## The third check below therefore asserts a LIMIT rather than a capability. It fails if
## the engine's answer changes in EITHER direction -- a fix upstream is as much a reason
## to revisit this code as a regression is.

## Wall thickness. Comfortably more than twice the deepest sphere any clearance sample
## uses, so a point at the centre is one the overlap tests genuinely cannot see.
const WALL: float = 6.0
## Half-width of the hollow the subtraction carves, and of the box the convex case uses.
const CAVITY: float = 3.0
## How far `is_solid` may cast looking for its first face. Longer than the whole fixture,
## so a miss means open space rather than an exhausted ray.
const REACH: float = 128.0
const TERRAIN_LAYER: int = 1

var _failures: int = 0
var _probe: NavigationProbe = null


func _ready() -> void:
	_build_concave()
	_build_backface_trimesh()
	_build_convex()
	_probe = NavigationProbe.new()
	_probe.bind(get_world_3d())

	# CSG generates its trimesh collider as part of processing, so on this frame there is
	# no collision in the world at all -- and a probe against it reports open space
	# everywhere without raising a single error.
	await get_tree().physics_frame
	await get_tree().physics_frame

	_check_concave_interior()
	_check_backface_trimesh()
	_check_concave_cavity()
	_check_convex_interior()
	_check_open_space()
	_check_unbound_refuses()

	if _failures > 0:
		print("FAILED: %d check(s)" % _failures)
	else:
		print("all checks passed")
	get_tree().quit(1 if _failures > 0 else 0)


# ----- fixtures -----


## A CSG block with a room subtracted out of it, centred on the origin. This is the exact
## construction every greybox prototype uses, and the collider it produces is a concave
## trimesh.
func _build_concave() -> void:
	var combiner := CSGCombiner3D.new()
	combiner.name = "ConcaveBlock"
	combiner.use_collision = true
	combiner.collision_layer = TERRAIN_LAYER
	# Terrain collides with nothing; things collide with terrain.
	combiner.collision_mask = 0
	add_child(combiner)

	var rock := CSGBox3D.new()
	rock.size = Vector3(WALL, WALL, WALL) * 2.0
	rock.operation = CSGShape3D.OPERATION_UNION
	combiner.add_child(rock)

	var hollow := CSGBox3D.new()
	hollow.size = Vector3(CAVITY, CAVITY, CAVITY) * 2.0
	hollow.operation = CSGShape3D.OPERATION_SUBTRACTION
	combiner.add_child(hollow)


## The same concave geometry, but as an explicit ConcavePolygonShape3D with
## `backface_collision` turned ON -- which CSG's generated collider does not do and does
## not expose. This isolates whether the back-face branch is wrong, or merely unsupported
## by the shape CSG happens to build.
func _build_backface_trimesh() -> void:
	var body := StaticBody3D.new()
	body.name = "BackfaceTrimesh"
	body.position = Vector3(-40.0, 0.0, 0.0)
	body.collision_layer = TERRAIN_LAYER
	body.collision_mask = 0

	var box := BoxMesh.new()
	box.size = Vector3(CAVITY, CAVITY, CAVITY) * 2.0
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(box.get_faces())
	shape.backface_collision = true

	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	add_child(body)


## A plain StaticBody3D box well away from the CSG, for the convex half of `is_solid`.
## The sandbox cave is made of these, so this is the branch the rest of the suite covers
## -- it is here to prove the two branches do not disagree.
func _build_convex() -> void:
	var body := StaticBody3D.new()
	body.name = "ConvexBlock"
	body.position = Vector3(40.0, 0.0, 0.0)
	body.collision_layer = TERRAIN_LAYER
	body.collision_mask = 0

	var shape := BoxShape3D.new()
	shape.size = Vector3(CAVITY, CAVITY, CAVITY) * 2.0
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	add_child(body)


# ----- checks -----


## THE KNOWN LIMIT, asserted so it cannot change without anyone noticing.
##
## A point midway through the rock of a CSG collider currently reads as OPEN, because the
## ray out of it crosses only back faces and Jolt reports none of them. If this ever
## starts reading solid, the engine has gained something `is_solid` can use and this
## module should use it -- which is why the check fails on an improvement too.
func _check_concave_interior() -> void:
	var before: int = _failures
	var depth: float = 0.5 * (CAVITY + WALL)
	if _probe.is_solid(Vector3(depth, 0.0, 0.0), TERRAIN_LAYER, REACH):
		_fail(
			"concave",
			(
				(
					"a point %.1f m inside CSG rock now reads as SOLID. That is better than "
					+ "the measured behaviour this check pins -- revisit is_solid and the "
					+ "greybox advice in its docstring, both of which assume it cannot."
				)
				% depth
			)
		)
	_pass_if("concave", before, "a point inside CSG rock still reads as open (known limit)")


## The same question against a trimesh that opts into back-face collision, which is the
## obvious fix and does not work: the hit is reported, but with a flipped normal that no
## test can distinguish from a front face.
func _check_backface_trimesh() -> void:
	var before: int = _failures
	if _probe.is_solid(Vector3(-40.0, 0.0, 0.0), TERRAIN_LAYER, REACH):
		_fail(
			"backface",
			(
				"backface_collision now yields a usable answer inside a trimesh. "
				+ "is_solid can be extended to cover concave terrain; see its docstring."
			)
		)
	_pass_if("backface", before, "backface_collision does not disambiguate (known limit)")


## The hollow the subtraction carved. If this reads solid, `is_solid` is answering
## "there is geometry somewhere along the ray" rather than "you are inside it", and every
## candidate in every cave would be rejected.
func _check_concave_cavity() -> void:
	var before: int = _failures
	if _probe.is_solid(Vector3.ZERO, TERRAIN_LAYER, REACH):
		_fail("concave", "the carved cavity read as solid; is_solid rejects open space")
	_pass_if("concave", before, "the carved cavity reads as open")


func _check_convex_interior() -> void:
	var before: int = _failures
	if not _probe.is_solid(Vector3(40.0, 0.0, 0.0), TERRAIN_LAYER, REACH):
		_fail(
			"convex",
			(
				"the centre of a BoxShape3D read as open space; "
				+ "hit_from_inside no longer reports a zero normal"
			)
		)
	_pass_if("convex", before, "the centre of a convex box reads as solid")


## Far from everything. A ray that hits nothing must mean open space, not "unknown".
func _check_open_space() -> void:
	var before: int = _failures
	if _probe.is_solid(Vector3(0.0, 500.0, 0.0), TERRAIN_LAYER, REACH):
		_fail("open", "empty space read as solid")
	_pass_if("open", before, "empty space reads as open")


## The refuse-everything rule, pointed the immobilising way. An unbound probe calling the
## world open would fill a graph with nodes inside rock; calling it solid produces an
## empty graph, which nobody mistakes for working.
func _check_unbound_refuses() -> void:
	var before: int = _failures
	var loose := NavigationProbe.new()
	if not loose.is_solid(Vector3.ZERO, TERRAIN_LAYER, REACH):
		_fail("unbound", "an unbound probe reported open space rather than refusing")
	_pass_if("unbound", before, "an unbound probe calls everything solid")


# ----- helpers -----


func _fail(tag: String, message: String) -> void:
	_failures += 1
	printerr("[%s] FAIL  %s" % [tag, message])


func _pass_if(tag: String, failures_before: int, message: String) -> void:
	if _failures == failures_before:
		print("[%-10s] PASS  %s" % [tag, message])
