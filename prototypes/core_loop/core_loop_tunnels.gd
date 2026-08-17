class_name CoreLoopTunnels
extends Node3D

## Carves the tunnel network out of solid rock with CSG.
##
## Every span contributes two brushes: a solid box the size of the hull, and a
## smaller box that hollows the bore out of it. ALL the hull brushes union first,
## then ALL the bore brushes subtract from the result. A bore brush is always
## strictly narrower than its own hull brush, so a span can never carve through to
## the outside whatever angle it sits at - which is what makes the six-way
## junctions here safe. There are no seams to line up, only overlapping volumes.
##
## The technique comes from navigation/corridor_generator.gd by way of
## chase_corridor_generator.gd. ONE THING IS NEW: width is a property of the route
## rather than one constant for the whole network, because the whole point of this
## map is that some of it the creature can get down and some of it it cannot.
## Every overrun is therefore computed per span from that span's own width instead
## of once in _ready.
##
## Nothing about the geometry is described to the navmesh baker. It floods the
## open space with physics queries and finds whatever is actually here, so a route
## added, moved or widened below needs no corresponding change over there - which
## is also what makes this whole node swappable for baked geometry later.

const HULL_MATERIAL := preload("res://prototypes/object_carrying/materials/hull_material.tres")

## Segments on a chamber sphere. Low: these are rock, and a chamber that reads as
## a faceted ball is closer to right than one that reads as a machined dome.
const CHAMBER_SEGMENTS := 12
const CHAMBER_RINGS := 6

## Hue step between consecutive junction beacons. The golden ratio conjugate, so
## sixteen of them stay distinguishable instead of cycling.
const BEACON_HUE_STEP := 0.618034

var _spans: Array[Dictionary] = []


func _ready() -> void:
	_collect_spans()
	_assemble_combiner()
	if CoreLoopKnobs.JUNCTION_BEACONS:
		_build_beacons()


## The volume the network occupies, padded.
##
## The navmesh flood fill uses this as a fence. Without one, a single hole in the
## hull would let the fill escape into the void outside and only stop when it hit
## its cell budget.
func bounds() -> AABB:
	var points := waypoints()
	var box := AABB(points[0], Vector3.ZERO)
	for point: Vector3 in points:
		box = box.expand(point)
	return box.grow(CoreLoopKnobs.NAVMESH_BOUNDS_MARGIN)


## Every waypoint in the layout, routes and chamber centres alike.
func waypoints() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for route: Dictionary in CoreLoopKnobs.ROUTES:
		for point: Vector3 in route["points"] as Array:
			points.append(point)
	for chamber: Dictionary in CoreLoopKnobs.CHAMBERS:
		points.append(chamber["center"] as Vector3)
	return points


## Total metres of centreline, for the HUD.
func network_length() -> float:
	var total := 0.0
	for span: Dictionary in _spans:
		total += span["length"] as float
	return total


## A point on each span of one named route, for the verifier.
##
## Midpoints rather than waypoints: a waypoint shared with a junction sits inside
## a chamber, so probing one would report the chamber's coverage rather than the
## route's - and for the refuge routes that is exactly the wrong answer, since
## their first waypoint IS a hub the creature can reach.
func route_midpoints(route_name: String) -> Array[Vector3]:
	var found: Array[Vector3] = []
	for span: Dictionary in _spans:
		if span["route"] == route_name:
			found.append(((span["start"] as Vector3) + (span["end"] as Vector3)) * 0.5)
	return found


## The narrowest route the creature could still get down, and the widest it could
## not. Reported rather than asserted here - CoreLoopSettings owns the rules.
func width_summary() -> Dictionary:
	var passable := INF
	var blocked := 0.0
	for route: Dictionary in CoreLoopKnobs.ROUTES:
		var width: float = route["width"]
		if width >= 2.0 * CoreLoopKnobs.CREATURE_PROBE_COMFORT:
			passable = minf(passable, width)
		else:
			blocked = maxf(blocked, width)
	return {"narrowest_passable": passable, "widest_blocked": blocked}


# --- Layout ----------------------------------------------------------------


func _collect_spans() -> void:
	for route: Dictionary in CoreLoopKnobs.ROUTES:
		var points: Array = route["points"]
		if points.size() < 2:
			push_warning("Route '%s' needs at least two waypoints; skipped." % route["name"])
			continue
		for index: int in points.size() - 1:
			var span_start: Vector3 = points[index]
			var span_end: Vector3 = points[index + 1]
			if span_start.is_equal_approx(span_end):
				push_warning(
					(
						"Route '%s' has a zero-length span at %v; skipped."
						% [route["name"], span_start]
					)
				)
				continue
			(
				_spans
				. append(
					{
						"route": route["name"],
						"width": route["width"],
						"start": span_start,
						"end": span_end,
						"length": span_start.distance_to(span_end),
						"transform": _make_span_transform(span_start, span_end),
					}
				)
			)


## Order matters: hulls union into one solid, then bores subtract from it.
##
## Chambers go through the same two passes rather than getting their own combiner.
## A chamber cut into a separate solid would leave the corridor's hull standing
## inside it as a wall across the room.
func _assemble_combiner() -> void:
	var combiner := CSGCombiner3D.new()
	combiner.name = "HullCombiner"
	combiner.use_collision = true
	combiner.collision_layer = CoreLoopKnobs.HULL_LAYER
	# Nothing here moves, so nothing needs to detect anything. A mask costs
	# broadphase work for a query that is never asked.
	combiner.collision_mask = 0
	combiner.material_override = HULL_MATERIAL
	add_child(combiner)

	for span: Dictionary in _spans:
		combiner.add_child(_make_span_brush(span, true))
	for chamber: Dictionary in CoreLoopKnobs.CHAMBERS:
		combiner.add_child(_make_chamber_brush(chamber, true))

	for span: Dictionary in _spans:
		combiner.add_child(_make_span_brush(span, false))
	for chamber: Dictionary in CoreLoopKnobs.CHAMBERS:
		combiner.add_child(_make_chamber_brush(chamber, false))


## One span's brush. `is_hull` picks which of the pair, because the two differ
## only in size and operation and writing them apart invites them to drift.
##
## The overruns are what make a junction seamless. A hull brush runs half its own
## width plus the wall past each end, so the hulls of two routes meeting at a
## junction always overlap; a bore brush runs half its width past each end, which
## is far enough for adjoining bores to meet and short enough that it can never
## reach past its own hull.
func _make_span_brush(span: Dictionary, is_hull: bool) -> CSGBox3D:
	var width: float = span["width"]
	var length: float = span["length"]
	var side := width + CoreLoopKnobs.WALL_THICKNESS * 2.0 if is_hull else width
	var overrun := width * 0.5 + CoreLoopKnobs.WALL_THICKNESS if is_hull else width * 0.5

	var brush := CSGBox3D.new()
	brush.size = Vector3(side, side, length + overrun * 2.0)
	brush.operation = CSGShape3D.OPERATION_UNION if is_hull else CSGShape3D.OPERATION_SUBTRACTION
	brush.transform = span["transform"]
	return brush


func _make_chamber_brush(chamber: Dictionary, is_hull: bool) -> CSGSphere3D:
	var radius: float = chamber["radius"]
	var brush := CSGSphere3D.new()
	brush.radius = radius + CoreLoopKnobs.WALL_THICKNESS if is_hull else radius
	brush.radial_segments = CHAMBER_SEGMENTS
	brush.rings = CHAMBER_RINGS
	brush.operation = CSGShape3D.OPERATION_UNION if is_hull else CSGShape3D.OPERATION_SUBTRACTION
	brush.position = chamber["center"]
	return brush


## Builds a basis whose local Z runs along the span, centred on its midpoint.
func _make_span_transform(span_start: Vector3, span_end: Vector3) -> Transform3D:
	var direction := (span_end - span_start).normalized()
	return Transform3D(
		Basis.looking_at(direction, _pick_reference_up(direction)), (span_start + span_end) * 0.5
	)


## Basis.looking_at fails when its up vector is parallel to the direction, and the
## entrance shaft in this network is very nearly vertical.
func _pick_reference_up(direction: Vector3) -> Vector3:
	if absf(direction.dot(Vector3.UP)) > 0.99:
		return Vector3.BACK
	return Vector3.UP


# --- Landmarks -------------------------------------------------------------


## A coloured dot at each junction.
##
## Not decoration, and not on the combiner: these are the only thing standing
## between the player and being lost inside two minutes, which would drown every
## other finding this prototype exists to produce.
func _build_beacons() -> void:
	var beacons := Node3D.new()
	beacons.name = "Beacons"
	add_child(beacons)

	var junctions: Array[Vector3] = [
		CoreLoopKnobs.ENTRANCE,
		CoreLoopKnobs.HUB_ANTECHAMBER,
		CoreLoopKnobs.HUB_EAST,
		CoreLoopKnobs.HUB_WEST,
		CoreLoopKnobs.HUB_DEEP,
		CoreLoopKnobs.CORE_CHAMBER,
	]
	for index: int in junctions.size():
		beacons.add_child(_make_beacon(junctions[index], index))


func _make_beacon(where: Vector3, index: int) -> Node3D:
	var hue := fmod(float(index) * BEACON_HUE_STEP, 1.0)
	var colour := Color.from_hsv(hue, 0.75, 1.0)

	var beacon := Node3D.new()
	beacon.name = "Beacon%02d" % index
	beacon.position = where

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = colour
	material.emission_enabled = true
	material.emission = colour
	material.emission_energy_multiplier = 2.0
	# Fog would swallow the one thing that has to be visible from down the tunnel.
	material.disable_fog = true

	var dot := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = CoreLoopKnobs.BEACON_SIZE
	sphere.height = CoreLoopKnobs.BEACON_SIZE * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	dot.mesh = sphere
	dot.material_override = material
	dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beacon.add_child(dot)

	var glow := OmniLight3D.new()
	glow.light_color = colour
	glow.omni_range = CoreLoopKnobs.BEACON_LIGHT_RANGE
	glow.light_energy = CoreLoopKnobs.BEACON_LIGHT_ENERGY
	# Six more shadow-casting lights in a network this size buys nothing and costs
	# a lot on the compatibility renderer.
	glow.shadow_enabled = false
	beacon.add_child(glow)

	return beacon
