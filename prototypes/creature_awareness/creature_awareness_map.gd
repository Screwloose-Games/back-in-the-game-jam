class_name CreatureAwarenessMap
extends Node3D

## The cave the alien lives in: three 40 m caverns and one loft, joined by the four passage
## classes the navigation module distinguishes between.
##
## CONCAVE ON PURPOSE. One `CSGCombiner3D` with `use_collision = true`, so the collider is
## the trimesh the engine generates from the same brushes that draw the cave and the two
## cannot drift. `NavigationProbe.is_solid` is impossible on a concave collider -- a point
## deep in the rock touches no triangle, so `shape_fits` says it fits and `clearance_at`
## returns the ceiling -- which is why the prototype bakes through `NavigationSource` with
## `use_flood` on. See `creature_nav_source_demo_map.gd`, which exists to demonstrate
## exactly that failure.
##
## EVERY BORE'S CENTRE LINE IS ON EVEN WORLD COORDINATES, AND THAT IS THE TRAP IN THIS FILE.
## Section 12.1's candidate lattice snaps to world-space multiples of `candidate_spacing`
## (2 m), and the flood steps between adjacent lattice cells. A passage whose centre line
## misses the lattice contains no candidate and DOES NOT EXIST to the graph; a bore under
## about 4 m running diagonally contains no two consecutive lattice points and the flood
## cannot follow it. Moving a tunnel by one metre is how you delete it.
##
## THE FOUR PASSAGE CLASSES, measured against the shipped `ClearanceProfile`:
##
##     swim tunnel    4 m bore   normal body needs 2.5 m; 10-ray fan reads 0.70 enclosure
##     squeeze        2 m bore   squeezed body needs 1.5 m, normal body needs 2.5 m
##     player shaft   1 m bore   below the squeezed body's 1.5 m, above the hull's 0.8 m
##     caverns        40 m       big enough that crossing one is a leap, not a crawl
##
## 4 M IS THE RIGHT SWIM BORE AND 6 M IS NOT, which is the opposite of what the shipped
## demo cave suggests. `tunnel_enclosure_reach` is 3 m and the fan is ten rays
## (`crawl_surface_ray_count`), so a 4 m bore encloses 7 of 10 against a 0.60 enter
## threshold. At 6 m the lateral rays sit exactly at the reach limit and enclosure collapses
## to 0.40 -- `nav_local_planner.gd` documents a body found stalled at (17, 7, 9) because of
## it, and the demo only swims at all through the refused-every-candidate fallback. The
## docstring on `tunnel_enclosure_reach` still describes a six-ray fan and is stale.
##
## THE CAVERNS CARRY PILLARS AND A BRIDGE, and they are not decoration. Section 12.2 sorts
## candidates by clearance DESCENDING and `clearance_ceiling` is 6 m, so every point more
## than 6 m from a wall ties and decimation scatters nodes through the empty middle of a
## 40 m sphere. The centre is 20 m from any wall against a `crawl_surface_reach` of 3.5, so
## a route across the void has nothing to hold. The columns and the bridge give the crawler
## surface within a short hop of the middle. Crossing a cavern still involves leaping, and
## that is correct for a room this size -- the structure is what keeps it short hops rather
## than one 40 m flight.

## The solid everything is carved out of. Also the flood's fence -- see `bounds()`.
const ROCK_MIN := Vector3(-24.0, -24.0, -24.0)
const ROCK_SIZE := Vector3(108.0, 76.0, 108.0)
const TERRAIN_LAYER: int = 1

const CAVERN_RADIUS: float = 20.0
const DOCK := Vector3(0.0, 0.0, 0.0)
const GALLERY := Vector3(60.0, 0.0, 0.0)
const WARREN := Vector3(0.0, 0.0, 60.0)

## Player-only, and small. Sits above the Dock on the cavern's own axis.
const LOFT := Vector3(0.0, 40.0, 0.0)
const LOFT_RADIUS: float = 6.0

## 4 m bore. Dock to Gallery along +X at y = 0, z = 0.
const SWIM_BORE: float = 2.0
## 2 m bore. Dock to Warren along +Z at x = 0, y = 0.
const SQUEEZE_BORE: float = 1.0
## 1 m bore. Dock to Loft along +Y at x = 0, z = 0. The alien's squeezed body needs 0.75 m
## and does not fit; the player's hull is 0.4 m and does.
const SHAFT_BORE: float = 0.5

## Radius is the CIRCUMradius of the generated polygon, so the usable bore is smaller by
## cos(PI / sides). At 24 sides that is 0.991 -- enough that the 1 m shaft still clears the
## player's 0.4 m hull and the flood's 0.25 m passage probe.
const TUBE_SIDES: int = 24

## Vertical columns, at these offsets from a cavern's centre in the XZ plane.
##
## OFF BOTH TUNNEL AXES BY CONSTRUCTION. A column near x = 0 would plug the Dock's squeeze
## tunnel and one near z = 0 would plug its swim tunnel, and neither failure says anything
## in the log -- the passage simply stops existing.
const COLUMN_OFFSETS: Array[Vector2] = [
	Vector2(8.0, 8.0),
	Vector2(-8.0, 8.0),
	Vector2(8.0, -8.0),
	Vector2(-8.0, -8.0),
]
const COLUMN_RADIUS: float = 3.0
## Horizontal span across a cavern along X, below the swim tunnel's y = 0 so the two never
## meet. This is the only crawlable path straight across a 40 m room.
const BRIDGE_RADIUS: float = 2.5
const BRIDGE_DROP: float = 6.0

## Where the alien idles between investigations. One per cavern it can actually reach, low
## in the chamber so it settles against a surface rather than hanging in the middle.
const NEST_DROP: float = 14.0

## Region ids for `CreatureSuspicion.region_resolver`. Rock is its own id so two hotspots
## either side of a thin wall never merge through it.
const REGION_ROCK: int = -1
const REGION_DOCK: int = 0
const REGION_GALLERY: int = 1
const REGION_WARREN: int = 2
const REGION_LOFT: int = 3

var _cave: CSGCombiner3D = null
var _combiner: CSGCombiner3D = null


## The whole solid, which is also every cubic metre of air the cave can contain. Handed to
## the source as its bake bounds, where it serves as the flood's fence.
static func bounds() -> AABB:
	return AABB(ROCK_MIN, ROCK_SIZE)


## The three caverns the alien can reach, centre and radius.
static func caverns() -> Array[Vector3]:
	return [DOCK, GALLERY, WARREN]


## Points the flood starts from: the centres of the brushes that carved the caverns, which
## are open by construction.
##
## THE LOFT IS DELIBERATELY NOT ONE. Seeding it would fill it whatever the 1 m shaft did,
## and the demonstration is that the flood gets there THROUGH a passage the alien cannot
## use -- so the loft ends up full of perfectly good nodes with no edge reaching any of
## them. Reachability is decided by section 13.2's swept bodies, not by the sampler.
static func air_seeds() -> PackedVector3Array:
	return PackedVector3Array([DOCK, GALLERY, WARREN])


## Where the alien idles when nothing is suspicious. Behaviour picks between these.
static func nests() -> PackedVector3Array:
	var found := PackedVector3Array()
	for centre: Vector3 in caverns():
		found.append(centre - Vector3(0.0, NEST_DROP, 0.0))
	return found


## Which chamber a point is in, for hotspot merge gating. Returns REGION_ROCK for anything
## outside every chamber, including inside the tunnels -- a noise heard in a tunnel should
## not pull two chambers' beliefs together.
static func region_id_at(point: Vector3) -> int:
	if point.distance_to(DOCK) <= CAVERN_RADIUS:
		return REGION_DOCK
	if point.distance_to(GALLERY) <= CAVERN_RADIUS:
		return REGION_GALLERY
	if point.distance_to(WARREN) <= CAVERN_RADIUS:
		return REGION_WARREN
	if point.distance_to(LOFT) <= LOFT_RADIUS:
		return REGION_LOFT
	return REGION_ROCK


## The hull, for the ant-farm camera to swap the material on. Null before `_ready`.
func hull() -> CSGCombiner3D:
	return _combiner


func _ready() -> void:
	_combiner = CSGCombiner3D.new()
	_combiner.name = "Terrain"
	# The collider is the CSG trimesh itself, generated from the same brushes as the visual.
	_combiner.use_collision = true
	_combiner.collision_layer = TERRAIN_LAYER
	# Terrain collides with nothing; things collide with terrain.
	_combiner.collision_mask = 0
	# `material_override`, not `material`: CSGCombiner3D is not a CSGPrimitive3D and has no
	# `material` of its own. Overriding on the root is what gives the whole cave one surface.
	_combiner.material_override = rock_material()
	add_child(_combiner)

	var rock := CSGBox3D.new()
	rock.size = ROCK_SIZE
	rock.position = ROCK_MIN + ROCK_SIZE * 0.5
	rock.operation = CSGShape3D.OPERATION_UNION
	_combiner.add_child(rock)

	# Nested, so every carve is one subtraction from the rock rather than a chain of them.
	# Only the ROOT combiner generates collision, which is what makes the whole cave one
	# trimesh instead of one per brush.
	_cave = CSGCombiner3D.new()
	_cave.name = "Cave"
	_cave.operation = CSGShape3D.OPERATION_SUBTRACTION
	_combiner.add_child(_cave)

	for centre: Vector3 in caverns():
		_cave.add_child(_ball(centre, CAVERN_RADIUS))
	_cave.add_child(_ball(LOFT, LOFT_RADIUS))
	_cave.add_child(_tube(DOCK, GALLERY, SWIM_BORE))
	_cave.add_child(_tube(DOCK, WARREN, SQUEEZE_BORE))
	_cave.add_child(_tube(DOCK, LOFT, SHAFT_BORE))

	# AFTER the subtraction, so these put solid back INSIDE the carved caverns. A union
	# listed before the subtraction would simply be carved away again.
	var structure := CSGCombiner3D.new()
	structure.name = "Structure"
	structure.operation = CSGShape3D.OPERATION_UNION
	_combiner.add_child(structure)
	for centre: Vector3 in caverns():
		for offset: Vector2 in COLUMN_OFFSETS:
			var foot := centre + Vector3(offset.x, -CAVERN_RADIUS, offset.y)
			var head := centre + Vector3(offset.x, CAVERN_RADIUS, offset.y)
			structure.add_child(_tube(foot, head, COLUMN_RADIUS))
		var west := centre + Vector3(-CAVERN_RADIUS, -BRIDGE_DROP, 0.0)
		var east := centre + Vector3(CAVERN_RADIUS, -BRIDGE_DROP, 0.0)
		structure.add_child(_tube(west, east, BRIDGE_RADIUS))


## Shared with the ant-farm camera, which needs a copy it can set `cull_mode` on.
static func rock_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.34, 0.32, 0.31)
	material.roughness = 0.95
	# Generated CSG carries no UVs worth speaking of, and triplanar is what keeps a carved
	# sphere from reading as a smear.
	material.uv1_triplanar = true
	material.uv1_scale = Vector3(0.25, 0.25, 0.25)
	return material


func _ball(at: Vector3, radius: float) -> CSGSphere3D:
	var ball := CSGSphere3D.new()
	ball.radius = radius
	ball.radial_segments = TUBE_SIDES
	ball.rings = TUBE_SIDES / 2
	ball.operation = CSGShape3D.OPERATION_UNION
	ball.position = at
	return ball


## A tube between two points. CSGCylinder3D runs along its own +Y, so the basis is built
## from the segment rather than from an Euler angle nobody can check.
func _tube(from: Vector3, to: Vector3, radius: float) -> CSGCylinder3D:
	var tube := CSGCylinder3D.new()
	tube.radius = radius
	tube.height = from.distance_to(to)
	tube.sides = TUBE_SIDES
	tube.operation = CSGShape3D.OPERATION_UNION
	var along: Vector3 = (to - from).normalized()
	# Any reference that is not parallel to the segment. UP fails for a vertical shaft.
	var reference: Vector3 = Vector3.RIGHT if absf(along.dot(Vector3.UP)) > 0.9 else Vector3.UP
	var side: Vector3 = reference.cross(along).normalized()
	tube.transform = Transform3D(Basis(side, along, side.cross(along)), from.lerp(to, 0.5))
	return tube
