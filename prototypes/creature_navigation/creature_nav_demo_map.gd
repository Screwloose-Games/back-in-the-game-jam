class_name CreatureNavDemoMap
extends Node3D

## The demo cave: four rooms and three sizes of tunnel, built from one table.
##
## VISUALS ARE CSG AND COLLISION IS CONVEX BOXES, generated from the same list. That looks
## like belt and braces and is not. `NavigationProbe.is_solid` is exact for convex
## colliders and impossible for concave ones -- measured, not assumed; see
## `gameplay/creature/navigation/tools/verify_navigation_csg.gd`, which pins all three
## engine behaviours. A CSG collider is a concave trimesh, so a point deep inside rock
## measures as wide-open and the bake scatters phantom nodes through the walls. Drawing
## with CSG and colliding with boxes costs one function and keeps navigation exact.
##
## THE ROCK IS COMPUTED AS THE COMPLEMENT OF THE OPEN SPACE, rather than authored. Writing
## the walls by hand means every tunnel mouth is a place two hand-written slabs have to
## line up, and one that does not is a hole nobody notices until an alien walks through it.
## Slicing the bounds on every open box's own coordinate planes is exact by construction.
##
## EVERY TUNNEL'S CROSS-SECTION IS CENTRED ON EVEN WORLD COORDINATES, and that is not
## decoration. Section 12.1's candidate lattice is snapped to world-space multiples of
## `candidate_spacing` (2 m by default), so a passage whose centre line misses the lattice
## contains no candidate and DOES NOT EXIST to the graph. That is the trap in this file.

## Wall thickness around the whole structure. Without it every candidate outside the cave
## has unlimited clearance and the graph wraps around through open sky.
const SHELL: float = 4.0

## Room A. The starting room: a plain crawl across a floor.
const DOCK := AABB(Vector3(0.0, 0.0, 0.0), Vector3(18.0, 10.0, 18.0))
## Room B. Tall and open, so a leap across it beats crawling round the walls.
const GALLERY := AABB(Vector3(34.0, 0.0, 0.0), Vector3(22.0, 22.0, 22.0))
## Room C. Only reachable through the wiggle tunnel.
const WARREN := AABB(Vector3(0.0, 0.0, 32.0), Vector3(18.0, 8.0, 16.0))
## Room D. Only reachable through the slot, which the alien cannot fit through at all.
const VENT_LOFT := AABB(Vector3(38.0, 26.0, 4.0), Vector3(14.0, 8.0, 14.0))

## 6 m bore. The normal body needs 2.5 m, so this is TUNNEL_SWIM.
const SWIM_TUNNEL := AABB(Vector3(18.0, 2.0, 6.0), Vector3(16.0, 6.0, 6.0))
## 2 m bore. Squeezed needs 1.5 m and normal needs 2.5 m, so this is WIGGLE and only that.
const WIGGLE_TUNNEL := AABB(Vector3(7.0, 3.0, 18.0), Vector3(2.0, 2.0, 14.0))
## 1 m bore. The player's hull is a 0.4 m sphere and fits; the alien's squeezed body needs
## 1.5 m and does not. NO EDGE IS EVER CREATED HERE, and no flag says so -- Invariant 5.
const PLAYER_SLOT := AABB(Vector3(44.0, 22.0, 10.0), Vector3(1.0, 4.0, 1.0))
## The long way round from the Warren to the Gallery, in two legs. Gives section 35 a
## genuinely different route to weigh against the wiggle tunnel.
const BACK_RUN_EAST := AABB(Vector3(18.0, 1.0, 36.0), Vector3(24.0, 6.0, 6.0))
const BACK_RUN_NORTH := AABB(Vector3(36.0, 1.0, 22.0), Vector3(6.0, 6.0, 14.0))

const TERRAIN_LAYER: int = 1

## Somewhere to stand in each room, for the HUD's shortcut keys.
const DOCK_SPAWN := Vector3(4.0, 2.0, 4.0)
const GALLERY_FLOOR := Vector3(38.0, 2.0, 4.0)
const GALLERY_HIGH := Vector3(52.0, 19.0, 18.0)
const WARREN_CENTRE := Vector3(8.0, 4.0, 40.0)
const VENT_LOFT_CENTRE := Vector3(45.0, 30.0, 11.0)

var _hull_material: StandardMaterial3D = null


## Every open volume, in the order they are carved.
static func open_volumes() -> Array[AABB]:
	return [
		DOCK,
		GALLERY,
		WARREN,
		VENT_LOFT,
		SWIM_TUNNEL,
		WIGGLE_TUNNEL,
		PLAYER_SLOT,
		BACK_RUN_EAST,
		BACK_RUN_NORTH,
	]


## The whole structure plus its shell. Also the bake region.
static func bounds() -> AABB:
	var total: AABB = open_volumes()[0]
	for box: AABB in open_volumes():
		total = total.merge(box)
	return total.grow(SHELL)


## The rock, as convex boxes.
##
## Slices `bounds()` on every coordinate plane any open box contributes, keeps the cells
## that lie in no open volume, and merges runs along x so the result is a few hundred
## boxes rather than a few thousand. Exact by construction: a cell is either wholly inside
## an open volume or wholly outside one, because the planes that could split it are all in
## the slicing set.
static func solids() -> Array[AABB]:
	var opens: Array[AABB] = open_volumes()
	var region: AABB = bounds()
	var xs: PackedFloat32Array = _cuts(opens, region, 0)
	var ys: PackedFloat32Array = _cuts(opens, region, 1)
	var zs: PackedFloat32Array = _cuts(opens, region, 2)

	var rock: Array[AABB] = []
	for j: int in ys.size() - 1:
		for k: int in zs.size() - 1:
			var run_start: int = -1
			for i: int in xs.size() - 1:
				var cell := AABB(
					Vector3(xs[i], ys[j], zs[k]),
					Vector3(xs[i + 1] - xs[i], ys[j + 1] - ys[j], zs[k + 1] - zs[k])
				)
				if _is_open(cell, opens):
					if run_start >= 0:
						rock.append(_run(xs, run_start, i, ys[j], ys[j + 1], zs[k], zs[k + 1]))
						run_start = -1
					continue
				if run_start < 0:
					run_start = i
			if run_start >= 0:
				rock.append(_run(xs, run_start, xs.size() - 1, ys[j], ys[j + 1], zs[k], zs[k + 1]))
	return rock


func _ready() -> void:
	_hull_material = _make_hull_material()
	_build_visual()
	_build_collision()


## Carves a fresh opening, for the mining demo. Returns the region navigation should be
## told about.
##
## The CSG brush and the collision boxes are both updated, so the two representations stay
## in step -- a hole you can see and cannot fly through is worse than no hole at all.
func carve(at: Vector3, size: float) -> AABB:
	var half := Vector3.ONE * (size * 0.5)
	var hole := AABB(at - half, half * 2.0)
	var brush := CSGBox3D.new()
	brush.size = hole.size
	brush.position = hole.get_center()
	brush.operation = CSGShape3D.OPERATION_SUBTRACTION
	get_node("HullCombiner").add_child(brush)
	_recarve_collision(hole)
	return hole


# ----- construction -----


## Union one block of rock, then subtract every open volume. The ordering is
## `prototypes/navigation/corridor_generator.gd`'s, which is proven.
##
## `use_collision` is FALSE here. See the class docstring.
func _build_visual() -> void:
	var combiner := CSGCombiner3D.new()
	combiner.name = "HullCombiner"
	combiner.use_collision = false
	combiner.material_override = _hull_material
	add_child(combiner)

	var region: AABB = bounds()
	var rock := CSGBox3D.new()
	rock.size = region.size
	rock.position = region.get_center()
	rock.operation = CSGShape3D.OPERATION_UNION
	combiner.add_child(rock)

	for box: AABB in open_volumes():
		var hollow := CSGBox3D.new()
		hollow.size = box.size
		hollow.position = box.get_center()
		hollow.operation = CSGShape3D.OPERATION_SUBTRACTION
		combiner.add_child(hollow)


func _build_collision() -> void:
	var root := Node3D.new()
	root.name = "HullCollision"
	add_child(root)
	for box: AABB in solids():
		root.add_child(_solid_body(box))


## Splits any collision box the hole touches, so the boxes still describe the rock.
##
## Crude on purpose: it removes every box the hole overlaps and re-emits the parts of each
## that survive. A prototype mines a handful of times, and the alternative is a BSP.
func _recarve_collision(hole: AABB) -> void:
	var root: Node3D = get_node("HullCollision")
	for child: Node in root.get_children():
		var body := child as StaticBody3D
		var shape := body.get_child(0) as CollisionShape3D
		var box := AABB(
			body.position - (shape.shape as BoxShape3D).size * 0.5, (shape.shape as BoxShape3D).size
		)
		if not box.intersects(hole):
			continue
		root.remove_child(body)
		body.queue_free()
		for piece: AABB in _subtract(box, hole):
			root.add_child(_solid_body(piece))


func _solid_body(box: AABB) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = box.get_center()
	body.collision_layer = TERRAIN_LAYER
	# Terrain collides with nothing; things collide with terrain.
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = box.size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	return body


func _make_hull_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.42, 0.44, 0.52, 1.0)
	material.roughness = 0.95
	# No SSAO, SSIL, SSR or SDFGI anywhere: the project targets GL Compatibility, where
	# they do not error and simply never appear.
	return material


# ----- geometry helpers -----


## Every coordinate plane on `axis` that could split a cell, sorted and deduplicated.
static func _cuts(opens: Array[AABB], region: AABB, axis: int) -> PackedFloat32Array:
	var seen: Dictionary = {}
	seen[region.position[axis]] = true
	seen[region.end[axis]] = true
	for box: AABB in opens:
		seen[box.position[axis]] = true
		seen[box.end[axis]] = true
	var cuts := PackedFloat32Array()
	for value: float in seen:
		if value >= region.position[axis] and value <= region.end[axis]:
			cuts.append(value)
	cuts.sort()
	return cuts


static func _is_open(cell: AABB, opens: Array[AABB]) -> bool:
	var middle: Vector3 = cell.get_center()
	for box: AABB in opens:
		if box.has_point(middle):
			return true
	return false


static func _run(
	xs: PackedFloat32Array,
	from: int,
	to: int,
	low_y: float,
	high_y: float,
	low_z: float,
	high_z: float
) -> AABB:
	return AABB(
		Vector3(xs[from], low_y, low_z), Vector3(xs[to] - xs[from], high_y - low_y, high_z - low_z)
	)


## `box` minus `hole`, as up to six boxes.
##
## The six slabs OVERLAP each other outside the hole, which is redundant and not wrong:
## solid boxes union, so the rock is the same shape either way, and none of them covers
## the hole. Clipping them into a disjoint set costs more code than a prototype's handful
## of mining operations can possibly justify.
static func _subtract(box: AABB, hole: AABB) -> Array[AABB]:
	var pieces: Array[AABB] = []
	var clipped: AABB = box.intersection(hole)
	if clipped.size.x <= 0.0 or clipped.size.y <= 0.0 or clipped.size.z <= 0.0:
		return [box]
	for axis: int in 3:
		if clipped.position[axis] > box.position[axis]:
			var low: AABB = box
			low.size[axis] = clipped.position[axis] - box.position[axis]
			pieces.append(low)
		if clipped.end[axis] < box.end[axis]:
			var high: AABB = box
			high.position[axis] = clipped.end[axis]
			high.size[axis] = box.end[axis] - clipped.end[axis]
			pieces.append(high)
	return pieces
