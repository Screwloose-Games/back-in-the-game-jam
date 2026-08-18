class_name EncounterSandboxGeometry
extends RefCounted

## The cave behavior.md section 35's encounter needs, in code.
##
## THE NUMBERS ARE LOAD-BEARING AND THERE IS ONE COPY OF THEM. The refuge is player-only
## because its opening is 1 m across and the alien's squeezed body needs 1.5 m -- change
## ClearanceProfile and this cave stops proving anything, which is exactly why the sandbox and
## its own start-up proof read the same constants rather than two sets that drift apart.
##
## THE HOLES ARE THE SOURCE OF TRUTH AND THE WALLS ARE DERIVED. `_wall_x` emits the solid
## strips AROUND a list of openings, so a check can assert against SLOT and be certain it is
## describing the same volume the wall was built from. Hand-listing the strips instead is one
## edit away from a scene that looks right and a proof that measures a wall which has moved.
##
##     the hall, x 0..48                                  refuge C, x 52..60
##     nests at the west end, one pillar mid-floor,       reachable only
##     and 40 m of chase between them                     through a 1 m slot
##
##     +--------------------------------------------+     +--------+
##     |  n                                         |     |        |
##     |      n              [][]                   |= =|         |
##     |  n                  [][]                   | 1x1        |
##     +--------------------------------------------+     +--------+
##                            pillar             slot
##
## What each piece is for:
##
##     pillar   3 x 3 m   free-standing, on the chase line  -> local avoidance has to steer
##     slot     1 x 1 m   neither body fits                 -> NO EDGE AT ALL
##     refuge   8 x 26 m  full of nodes, none of them reachable
##
## ONE HALL RATHER THAN TWO CHAMBERS AND A DOORWAY, and that is a finding rather than a
## simplification. An earlier version of this cave put a 4 m-thick divider with an 8 m doorway
## between the nests and the chase floor, and the alien wedged in it every run: approaching at
## an angle it comes within a metre of the door frame, a wall nearer than the floor becomes
## SurfaceCrawlController's `dominant_normal`, the tangent plane rotates onto that face, and
## every candidate then points straight out of the surface -- so the fan validates nothing and
## the planner answers BLOCKED for ever, holding a COMPLETE route. That is the same wedge
## `behavior_sandbox.gd` reports at ITS doorway, and it belongs to Movement rather than to
## anything here. A doorway is not part of what this scene demonstrates, so it is not in it.
##
## The refuge is the point of the slot. It is perfectly good open space, the bake fills it with
## perfectly good nodes, and the alien can never reach one of them -- which is behavior.md
## section 29's "non-creature passable tunnel" with no flag, marker or layer anywhere. The
## creature infers you went in there from its own graph refusing to route, and that inference
## covers every gap too tight for it rather than the ones somebody remembered to tag.
##
## Boxes rather than voxels, and built in code rather than authored into the .tscn: nothing in
## these modules knows what a voxel is, BoxShape3D is convex so the overlap tests have no
## interior blind spot, and the editor rewrites relative ext_resource paths on every re-save.

## Interior of the shell. Also the bake region.
##
## 60 m of it, because a chase has to read as a chase. The nests to the slot is roughly 42 m
## of route, which at the alien's crawl speed is long enough to watch it commit, lose you and
## commit again -- and short enough that a viewer does not give up before the beat lands.
const INTERIOR := AABB(Vector3.ZERO, Vector3(60.0, 8.0, 26.0))
const SHELL_THICKNESS: float = 2.0
## The wall the slot goes through. Thick enough that the opening is a PASSAGE rather than a
## hole in a sheet, which is what the swept-shape edge validation in section 13.2 measures.
const DIVIDER_THICKNESS: float = 4.0

## The hall into the refuge. 1 m across, which is less than the squeezed body's 1.5 m.
## Nothing the alien can do makes this passable, and nothing in the behavior module knows it
## is special.
##
## AT THE CREATURE'S EYE HEIGHT ON PURPOSE, and that is what makes the whole beat happen
## rather than merely being possible. The alien only ever believes what it has perceived, so
## an opening above or below its line of sight leaves it with a last known position at the
## mouth -- which is reachable, so it sweeps there and eventually starves, and the lurk never
## fires. Put the gap where it can look through and the evidence lands INSIDE the refuge:
## somewhere its own graph refuses to route to, which is the whole of section 29's inference.
## It can see you. It cannot come and get you. That is the beat.
const SLOT := AABB(Vector3(48.0, 1.5, 12.5), Vector3(4.0, 1.0, 1.0))
## Free-standing rock in the middle of the chase floor, and the only reason local avoidance
## has anything to do in this scene.
##
## IT HAS TO BE FURTHER FROM THE BODY THAN THE FLOOR IS, which is why it sits in open ground
## rather than beside a wall. A surface nearer than the floor becomes the crawler's
## `dominant_normal`, the tangent plane rotates onto that face, and the goal is then straight
## out of the surface -- a legitimate refusal that looks exactly like a broken demo.
## `test_local_avoidance.gd` documents the same trap.
const PILLAR := AABB(Vector3(34.0, 0.0, 11.5), Vector3(3.0, 8.0, 3.0))

## Open space the alien can see the edge of and never stand in.
const REFUGE := AABB(Vector3(52.0, 0.0, 0.0), Vector3(8.0, 8.0, 26.0))
## The west end of the hall, where the nests are. Only the start-up proof reads this: it needs
## one node it is certain is on the alien's side of the slot.
const CHAMBER_A := AABB(Vector3(0.0, 0.0, 0.0), Vector3(20.0, 8.0, 26.0))

## Where the alien starts, and where R puts it back.
##
## NEAR THE FLOOR BUT NOT ON IT. A body with nothing inside `crawl_surface_reach` reads as
## slipped and spends its first seconds recovering rather than deciding, and one pressed
## against the floor has less than the 1.25 m of clearance the normal shape needs.
const CREATURE_START := Vector3(6.0, 2.0, 13.0)
const PLAYER_START := Vector3(13.0, 2.0, 13.0)
## Three, spread across the west end, so a wander has somewhere to go that is not a patrol and
## a retreat has somewhere genuinely far from the slot.
const NEST_POSITIONS: Array[Vector3] = [
	Vector3(5.0, 2.0, 5.0),
	Vector3(5.0, 2.0, 21.0),
	Vector3(16.0, 2.0, 13.0),
]

## Terrain sits on bit 1, which project.godot names "hull" and which
## NavigationConfig.DEFAULT_WORLD_MASK and PerceptionConfig.world_mask both already look at.
## Put the cave anywhere else and every candidate reports open space with nothing in the log.
const TERRAIN_LAYER: int = 1


## Every solid box in the cave, in world space.
static func solids() -> Array[AABB]:
	var boxes: Array[AABB] = []
	boxes.append_array(_shell())
	boxes.append_array(
		_wall_x(
			Vector2(SLOT.position.x, SLOT.end.x),
			Vector2(0.0, INTERIOR.size.y),
			Vector2(0.0, INTERIOR.size.z),
			[SLOT]
		)
	)
	boxes.append(PILLAR)
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


## A sealed box around the interior, so "open space" means the cave rather than the infinite
## void outside it.
##
## NOT DECORATION. Without the shell every candidate outside the structure has unlimited
## clearance, the graph wraps around the dividers through open sky, and the slot passes its
## check for entirely the wrong reason -- the alien would reach the refuge the long way and
## the whole scenario would quietly stop being about a gap at all.
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
## Written as the complement of the holes because Godot has no CSG in a physics shape, and
## generated rather than listed because the holes are what everything else asserts against.
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
	# Terrain collides with nothing; things collide with terrain. A mask here would make every
	# box test every other box for no reason.
	body.collision_mask = 0

	var shape := BoxShape3D.new()
	shape.size = box.size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	return body
