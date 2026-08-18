class_name NavigationSandboxGeometry
extends RefCounted

## The test cave, in code (navigation.md section 43 scenarios A, B, C, D and G).
##
## SHARED BY THE SANDBOX AND THE RUNTIME VERIFIER ON PURPOSE. The numbers below are
## load-bearing -- the tight tunnel is wiggle-only because it is 2 m across and the
## squeezed body is 1.5 m across -- and two copies of them drift the moment anyone
## retunes ClearanceProfile. One copy means the thing you look at in the sandbox is
## the thing CI asserts against.
##
## THE HOLES ARE THE SOURCE OF TRUTH AND THE WALLS ARE DERIVED. `_wall_x` and `_wall_z`
## emit the solid strips AROUND a list of openings, so the verifier can assert against
## WIDE_TUNNEL / TIGHT_TUNNEL / SLOT and be certain it is describing the same volumes
## the cave was built from. Hand-listing the strips instead is one edit away from a
## suite that passes while measuring a tunnel that has moved.
##
## Boxes rather than voxels. Nothing in this module knows what a voxel is (see
## NavigationProbe), and a StaticBody3D cave needs no GDExtension, imports in a cold CI
## checkout, and -- because BoxShape3D is convex -- has no interior blind spot for the
## overlap tests to fall into.
##
## THE LAYOUT IS DESIGNED AROUND THE 2 m CANDIDATE LATTICE, and that is not cheating.
## Section 12.1 samples on a lattice; a passage narrower than the lattice pitch simply
## contains no candidate, which is a genuine property of the algorithm rather than a
## bug in this file. The wide tunnel is 6 m across so its centre line lands on lattice
## points at three different heights; the tight tunnel is 2 m across so exactly one
## lattice line threads it, which is what a real crevice looks like to this sampler.
##
##     chamber A                  chamber B
##     x 0..16                    x 22..44, z 0..20
##     z 0..30          ####      +-----------------+
##     +--------+  6x6  ####      |                 |
##     |        |=======####======|                 |
##     |        |  2x2   ###      |                 |
##     |        |=======####======|                 |
##     +--------+       ####      +--[ 1x1 slot ]---+
##                   divider 1    +-----------------+  chamber C
##                                   z 26..30, sealed to everything
##                                   except that slot
##
## What each piece proves:
##
##     wide tunnel   6 x 6 m   normal body fits          -> NORMAL_VOLUME  (Scenario A)
##     tight tunnel  2 x 2 m   only squeezed body fits   -> WIGGLE         (Scenario B)
##     slot          1 x 1 m   neither body fits         -> NO EDGE        (Scenarios C, G)
##     chamber A     16x8x30   a ~23 m crawl end to end                    (Scenario D)
##
## Chamber C is the point of the slot. It is full of perfectly good open space, the bake
## fills it with perfectly good nodes, and the alien can never reach any of them --
## Invariant 5 with no flag, marker or special case anywhere in the module.

## Interior of the shell. Also the bake region.
const INTERIOR := AABB(Vector3.ZERO, Vector3(44.0, 8.0, 30.0))
const SHELL_THICKNESS: float = 2.0
const DIVIDER_THICKNESS: float = 6.0

## Chamber A from chamber B. 6 m across: the normal body needs 2.5 m of it.
const WIDE_TUNNEL := AABB(Vector3(16.0, 1.0, 3.0), Vector3(6.0, 6.0, 6.0))
## Chamber A from chamber B, the hard way. 2 m across: the squeezed body needs 1.5 m,
## the normal body needs 2.5 m and does not get it.
const TIGHT_TUNNEL := AABB(Vector3(16.0, 3.0, 15.0), Vector3(6.0, 2.0, 2.0))
## Chamber B from chamber C. 1 m across, which is less than the squeezed body needs.
## Nothing the alien can do makes this passable, and nothing in the module knows it is
## special.
const SLOT := AABB(Vector3(30.0, 3.5, 20.0), Vector3(1.0, 1.0, 6.0))
const CHAMBER_C := AABB(Vector3(22.0, 0.0, 26.0), Vector3(22.0, 8.0, 4.0))

const CHAMBER_A_CENTER := Vector3(8.0, 4.0, 8.0)
## The far end of chamber A, a ~23 m crawl from the near end.
const CHAMBER_A_FAR := Vector3(8.0, 4.0, 26.0)
const CHAMBER_B_CENTER := Vector3(32.0, 4.0, 8.0)
## Reachable only through the 1 x 1 slot, which means not reachable.
const CHAMBER_C_CENTER := Vector3(36.0, 4.0, 28.0)

## Terrain sits on bit 1, which project.godot names "hull" and which
## NavigationConfig.DEFAULT_WORLD_MASK already looks at. Put the cave anywhere else and
## every candidate reports open space with nothing in the log.
const TERRAIN_LAYER: int = 1


## Every solid box in the cave, in world space.
static func solids() -> Array[AABB]:
	var boxes: Array[AABB] = []
	boxes.append_array(_shell())
	# Divider 1 runs the full depth of the cave, which is what seals chamber A off from
	# chamber C as well as gating it into chamber B.
	boxes.append_array(
		_wall_x(
			Vector2(WIDE_TUNNEL.position.x, WIDE_TUNNEL.end.x),
			Vector2(0.0, INTERIOR.size.y),
			Vector2(0.0, INTERIOR.size.z),
			[WIDE_TUNNEL, TIGHT_TUNNEL]
		)
	)
	boxes.append_array(
		_wall_z(
			Vector2(WIDE_TUNNEL.end.x, INTERIOR.size.x),
			Vector2(0.0, INTERIOR.size.y),
			Vector2(SLOT.position.z, SLOT.end.z),
			[SLOT]
		)
	)
	return boxes


## Adds the cave to `parent` as StaticBody3D children. Returns how many it added.
static func build(parent: Node3D) -> int:
	var boxes: Array[AABB] = solids()
	for index: int in boxes.size():
		parent.add_child(_solid_body(boxes[index], "Solid%d" % index))
	return boxes.size()


static func bake_region() -> AABB:
	return INTERIOR


# ----- pieces -----


## A sealed box around the interior, so "open space" means the cave rather than the
## infinite void outside it.
##
## NOT DECORATION. Without the shell every candidate outside the structure has
## unlimited clearance, the graph wraps around the dividers through open sky, and
## Scenario C passes for entirely the wrong reason.
static func _shell() -> Array[AABB]:
	var thick: float = SHELL_THICKNESS
	var inner: Vector3 = INTERIOR.size
	var outer_x: float = inner.x + thick * 2.0
	var outer_z: float = inner.z + thick * 2.0
	return [
		AABB(Vector3(-thick, -thick, -thick), Vector3(outer_x, thick, outer_z)),
		AABB(Vector3(-thick, inner.y, -thick), Vector3(outer_x, thick, outer_z)),
		AABB(Vector3(-thick, 0.0, -thick), Vector3(thick, inner.y, outer_z)),
		AABB(Vector3(inner.x, 0.0, -thick), Vector3(thick, inner.y, outer_z)),
		AABB(Vector3(0.0, 0.0, -thick), Vector3(inner.x, inner.y, thick)),
		AABB(Vector3(0.0, 0.0, inner.z), Vector3(inner.x, inner.y, thick)),
	]


## The solid strips of a wall whose thickness runs along x, given openings ordered by z.
##
## Written as the complement of the holes because Godot has no CSG in a physics shape,
## and generated rather than listed because the holes are what the verifier asserts
## against.
static func _wall_x(
	span_x: Vector2, span_y: Vector2, span_z: Vector2, holes: Array[AABB]
) -> Array[AABB]:
	var boxes: Array[AABB] = []
	var cursor: float = span_z.x
	for hole: AABB in holes:
		if hole.position.z > cursor:
			boxes.append(_strip(span_x, span_y, Vector2(cursor, hole.position.z)))
		var around := Vector2(hole.position.z, hole.end.z)
		if hole.position.y > span_y.x:
			boxes.append(_strip(span_x, Vector2(span_y.x, hole.position.y), around))
		if hole.end.y < span_y.y:
			boxes.append(_strip(span_x, Vector2(hole.end.y, span_y.y), around))
		cursor = hole.end.z
	if cursor < span_z.y:
		boxes.append(_strip(span_x, span_y, Vector2(cursor, span_z.y)))
	return boxes


## The same, for a wall whose thickness runs along z, given openings ordered by x.
static func _wall_z(
	span_x: Vector2, span_y: Vector2, span_z: Vector2, holes: Array[AABB]
) -> Array[AABB]:
	var boxes: Array[AABB] = []
	var cursor: float = span_x.x
	for hole: AABB in holes:
		if hole.position.x > cursor:
			boxes.append(_strip(Vector2(cursor, hole.position.x), span_y, span_z))
		var around := Vector2(hole.position.x, hole.end.x)
		if hole.position.y > span_y.x:
			boxes.append(_strip(around, Vector2(span_y.x, hole.position.y), span_z))
		if hole.end.y < span_y.y:
			boxes.append(_strip(around, Vector2(hole.end.y, span_y.y), span_z))
		cursor = hole.end.x
	if cursor < span_x.y:
		boxes.append(_strip(Vector2(cursor, span_x.y), span_y, span_z))
	return boxes


static func _strip(span_x: Vector2, span_y: Vector2, span_z: Vector2) -> AABB:
	return AABB(
		Vector3(span_x.x, span_y.x, span_z.x),
		Vector3(span_x.y - span_x.x, span_y.y - span_y.x, span_z.y - span_z.x)
	)


static func _solid_body(box: AABB, node_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = box.get_center()
	body.collision_layer = TERRAIN_LAYER
	# Terrain collides with nothing; things collide with terrain. A mask here would make
	# every box test every other box for no reason.
	body.collision_mask = 0

	var shape := BoxShape3D.new()
	shape.size = box.size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	return body
