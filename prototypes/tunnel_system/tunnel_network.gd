class_name TunnelNetwork
extends RefCounted

## The tunnel network as data: capsule segments, chamber spheres, the signed
## distance field they define, and the junction graph they form.
##
## No scene-tree side effects and no node creation - it reads Path3D nodes and
## answers questions. The baker, the HUD, the map overlay and the verifier all
## read this one copy, so there is a single implementation of "where is the wall"
## rather than three files that agree until one of them is edited.
##
## SIGN CONVENTION: field() is NEGATIVE inside the tunnel (air) and POSITIVE in
## the rock, with the isosurface at zero. Inside the bore, -field(p) is therefore
## the distance to the nearest wall, which is what the HUD prints as clearance.
##
## The field is a MINIMUM over primitives, which is what makes junctions free. A
## three-way node is not a special case that has to be modelled; it is just where
## three capsules' minima overlap, and the isosurface through it is one smooth
## closed sheet. Dead ends cap themselves, because the end of a capsule is a
## hemisphere. There is no configuration of curves that can produce a hole.

## How close two route endpoints must be to count as the same junction. The
## builder writes them from shared constants so they are bit-identical; this
## tolerance exists so a designer nudging a curve end in the editor by a few
## centimetres does not silently split a junction into two disconnected nodes.
const WELD_DISTANCE := 0.5

## Metadata key on each Path3D holding one radius per curve control point.
##
## NOT Curve3D.tilt, which is tempting because it is a per-point float that
## already round-trips through .tscn and nothing else uses. A designer adding a
## point to a curve gets tilt = 0, which is radius 0, which is a tunnel that
## silently vanishes - in a scene that still bakes, still produces a watertight
## mesh, and still passes every check except "is that corridor still there".
const RADII_META := "bore_radii"

var routes: Array[Dictionary] = []
var chamber_centers := PackedVector3Array()
var chamber_radii := PackedFloat32Array()
var junctions := PackedVector3Array()
var junction_names: Array[String] = []

var _seg_a := PackedVector3Array()
var _seg_ab := PackedVector3Array()
var _seg_inv_len_sq := PackedFloat32Array()
var _seg_r0 := PackedFloat32Array()
var _seg_r1 := PackedFloat32Array()
var _hash: Dictionary = {}
var _adjacency: Array[PackedInt32Array] = []
var _route_edges: Array[Vector2i] = []


## Reads every Path3D under `paths_root` plus every chamber marker, and returns a
## network ready to query. `chamber_root` may be null.
static func from_scene(paths_root: Node, chamber_root: Node) -> TunnelNetwork:
	var network := TunnelNetwork.new()
	if paths_root != null:
		for child: Node in paths_root.get_children():
			var path := child as Path3D
			if path == null:
				continue
			network.add_path(path)
	if chamber_root != null:
		for child: Node in chamber_root.get_children():
			var marker := child as Marker3D
			if marker == null:
				continue
			network.add_chamber(marker.position, marker.get_meta("chamber_radius", 3.0))
	network.build_index()
	network.build_graph()
	return network


## Adds one route from an already-resampled polyline with one radius per point.
func add_polyline(
	route_name: String, points: PackedVector3Array, radii: PackedFloat32Array
) -> void:
	if points.size() < 2:
		push_warning("Route '%s' has fewer than two points; skipped." % route_name)
		return
	routes.append({"name": route_name, "points": points, "radii": radii})
	for i: int in points.size() - 1:
		var a := points[i]
		var ab := points[i + 1] - a
		var len_sq := ab.length_squared()
		if len_sq <= 0.0:
			continue
		_seg_a.append(a)
		_seg_ab.append(ab)
		_seg_inv_len_sq.append(1.0 / len_sq)
		_seg_r0.append(radii[i])
		_seg_r1.append(radii[i + 1])


func add_chamber(center: Vector3, radius: float) -> void:
	chamber_centers.append(center)
	chamber_radii.append(radius)


## Signed distance to the tunnel surface. Negative inside the bore.
func field(point: Vector3) -> float:
	var best := TunnelKnobs.FIELD_TRUNCATE
	var bucket: PackedInt32Array = _hash.get(_key_of(point), PackedInt32Array())
	for encoded: int in bucket:
		var distance := 0.0
		if encoded >= 0:
			var a := _seg_a[encoded]
			var ab := _seg_ab[encoded]
			var t := clampf((point - a).dot(ab) * _seg_inv_len_sq[encoded], 0.0, 1.0)
			distance = point.distance_to(a + ab * t) - lerpf(_seg_r0[encoded], _seg_r1[encoded], t)
		else:
			var sphere := -encoded - 1
			distance = point.distance_to(chamber_centers[sphere]) - chamber_radii[sphere]
		best = minf(best, distance)
	return best


## Surface normal facing INTO the bore, which is the only side the player is ever
## on. The field increases into the rock, so the air-facing normal is -gradient.
func air_normal(point: Vector3) -> Vector3:
	var h := TunnelKnobs.CELL_SIZE * 0.5
	var gradient := Vector3(
		field(point + Vector3(h, 0, 0)) - field(point - Vector3(h, 0, 0)),
		field(point + Vector3(0, h, 0)) - field(point - Vector3(0, h, 0)),
		field(point + Vector3(0, 0, h)) - field(point - Vector3(0, 0, h))
	)
	if gradient.length_squared() < 1e-12:
		return Vector3.UP
	return -gradient.normalized()


## Bucket every primitive into the spatial hash. A field query then costs one
## dictionary lookup instead of a scan over several thousand segments - which is
## the difference between a bake measured in seconds and one measured in hours.
func build_index() -> void:
	_hash.clear()
	for i: int in _seg_a.size():
		var a := _seg_a[i]
		var b := a + _seg_ab[i]
		var margin := maxf(_seg_r0[i], _seg_r1[i]) + TunnelKnobs.FIELD_TRUNCATE
		_insert(i, AABB(a, Vector3.ZERO).expand(b).grow(margin))
	for i: int in chamber_centers.size():
		var margin := chamber_radii[i] + TunnelKnobs.FIELD_TRUNCATE
		_insert(-i - 1, AABB(chamber_centers[i], Vector3.ZERO).grow(margin))


## Welds route endpoints into junctions and records which junctions each route
## joins. Two routes that share a junction constant produce endpoints at exactly
## the same coordinate, so they weld into one node and the graph edge is real.
func build_graph() -> void:
	junctions = PackedVector3Array()
	junction_names = []
	_route_edges = []
	for route: Dictionary in routes:
		var points: PackedVector3Array = route["points"]
		var head := _weld(points[0])
		var tail := _weld(points[points.size() - 1])
		_route_edges.append(Vector2i(head, tail))

	_adjacency = []
	for _i: int in junctions.size():
		_adjacency.append(PackedInt32Array())
	for index: int in _route_edges.size():
		var edge := _route_edges[index]
		if edge.x == edge.y:
			continue
		var from_list := _adjacency[edge.x]
		from_list.append(edge.y)
		_adjacency[edge.x] = from_list
		var to_list := _adjacency[edge.y]
		to_list.append(edge.x)
		_adjacency[edge.y] = to_list


## Junction indices reachable from the junction nearest `origin`, by flood fill.
func reachable_junctions(origin: Vector3) -> PackedInt32Array:
	var start := _nearest_junction(origin)
	var seen := PackedInt32Array()
	if start < 0:
		return seen
	var visited := {start: true}
	var queue: Array[int] = [start]
	while not queue.is_empty():
		var current: int = queue.pop_back()
		seen.append(current)
		for neighbour: int in _adjacency[current]:
			if not visited.has(neighbour):
				visited[neighbour] = true
				queue.append(neighbour)
	return seen


## Names of every route that has no junction reachable from `origin`. Empty means
## the network is connected as far as the graph is concerned - which is a weaker
## claim than the verifier's sphere sweep, and deliberately so: this catches a
## typo'd coordinate, that catches a bore too narrow to actually pass through.
func unreachable_routes(origin: Vector3) -> PackedStringArray:
	var reached := {}
	for index: int in reachable_junctions(origin):
		reached[index] = true
	var orphans := PackedStringArray()
	for index: int in _route_edges.size():
		var edge := _route_edges[index]
		if not reached.has(edge.x) and not reached.has(edge.y):
			orphans.append(routes[index]["name"])
	return orphans


## The junction pair each route joins, indexed alongside `routes`.
func route_edges() -> Array[Vector2i]:
	return _route_edges


## How many routes meet at a junction. Three or more makes it a real branch and
## therefore worth a landmark; one is a dead end you are already standing in.
func junction_degree(index: int) -> int:
	if index < 0 or index >= _adjacency.size():
		return 0
	return _adjacency[index].size()


## Total centreline length in metres.
func total_length() -> float:
	var total := 0.0
	for i: int in _seg_ab.size():
		total += _seg_ab[i].length()
	return total


func segment_count() -> int:
	return _seg_a.size()


## World-space box the isosurface can possibly occupy.
func bounds() -> AABB:
	var box := AABB()
	var started := false
	for i: int in _seg_a.size():
		var margin := maxf(_seg_r0[i], _seg_r1[i]) + TunnelKnobs.CELL_SIZE * 2.0
		var a := _seg_a[i]
		var piece := AABB(a, Vector3.ZERO).expand(a + _seg_ab[i]).grow(margin)
		box = piece if not started else box.merge(piece)
		started = true
	for i: int in chamber_centers.size():
		var margin := chamber_radii[i] + TunnelKnobs.CELL_SIZE * 2.0
		var piece := AABB(chamber_centers[i], Vector3.ZERO).grow(margin)
		box = piece if not started else box.merge(piece)
		started = true
	return box


## Name of the route whose centreline passes closest to `point`, for the HUD.
func nearest_route_name(point: Vector3) -> String:
	var best_name := "-"
	var best := INF
	for route: Dictionary in routes:
		for sample: Vector3 in route["points"] as PackedVector3Array:
			var distance := point.distance_squared_to(sample)
			if distance < best:
				best = distance
				best_name = route["name"]
	return best_name


## Adds one route by resampling a Path3D's curve at SEGMENT_STEP, reading its
## per-control-point radii metadata and interpolating them against arc length.
func add_path(path: Path3D) -> void:
	var curve := path.curve
	if curve == null or curve.point_count < 2:
		push_warning("Path3D '%s' has no usable curve; skipped." % path.name)
		return

	var control_radii: PackedFloat32Array = path.get_meta(RADII_META, PackedFloat32Array())
	if control_radii.size() != curve.point_count:
		# Never silently default to zero. A zero radius deletes a tunnel, and the
		# network still bakes, still verifies as watertight, and is simply missing
		# a corridor - which is the hardest kind of failure to notice.
		push_warning(
			(
				"Path3D '%s' has %d radii for %d curve points; falling back to %.2f m."
				% [
					path.name,
					control_radii.size(),
					curve.point_count,
					TunnelKnobs.BORE_BRANCH,
				]
			)
		)
		control_radii = PackedFloat32Array()
		for _i: int in curve.point_count:
			control_radii.append(TunnelKnobs.BORE_BRANCH)

	# Where each control point sits along the baked curve, so a radius authored
	# per control point can be interpolated against arc length rather than
	# against point index - which would skew every taper on an uneven polyline.
	var control_offsets := PackedFloat32Array()
	for i: int in curve.point_count:
		control_offsets.append(curve.get_closest_offset(curve.get_point_position(i)))

	var length := curve.get_baked_length()
	var steps := maxi(int(ceil(length / TunnelKnobs.SEGMENT_STEP)), 1)
	var points := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i: int in steps + 1:
		var offset := length * float(i) / float(steps)
		points.append(path.position + curve.sample_baked(offset))
		radii.append(_radius_at(offset, control_offsets, control_radii))
	add_polyline(path.name, points, radii)


func _radius_at(
	offset: float, control_offsets: PackedFloat32Array, control_radii: PackedFloat32Array
) -> float:
	if control_offsets.size() < 2:
		return control_radii[0] if control_radii.size() > 0 else TunnelKnobs.BORE_BRANCH
	for i: int in control_offsets.size() - 1:
		var from := control_offsets[i]
		var to := control_offsets[i + 1]
		if offset > to and i < control_offsets.size() - 2:
			continue
		var span := to - from
		var t := 0.0 if span <= 0.0 else clampf((offset - from) / span, 0.0, 1.0)
		return lerpf(control_radii[i], control_radii[i + 1], t)
	return control_radii[control_radii.size() - 1]


func _insert(encoded: int, box: AABB) -> void:
	var lo := _key_of(box.position)
	var hi := _key_of(box.position + box.size)
	for x: int in range(lo.x, hi.x + 1):
		for y: int in range(lo.y, hi.y + 1):
			for z: int in range(lo.z, hi.z + 1):
				var key := Vector3i(x, y, z)
				var bucket: PackedInt32Array = _hash.get(key, PackedInt32Array())
				bucket.append(encoded)
				_hash[key] = bucket


func _key_of(point: Vector3) -> Vector3i:
	return Vector3i(
		int(floor(point.x / TunnelKnobs.HASH_CELL)),
		int(floor(point.y / TunnelKnobs.HASH_CELL)),
		int(floor(point.z / TunnelKnobs.HASH_CELL))
	)


func _weld(point: Vector3) -> int:
	for i: int in junctions.size():
		if junctions[i].distance_to(point) <= WELD_DISTANCE:
			return i
	junctions.append(point)
	junction_names.append(_name_for(point))
	return junctions.size() - 1


## Junctions authored as named constants get their constant's name back, so the
## verifier can say which one is orphaned instead of printing a coordinate.
func _name_for(point: Vector3) -> String:
	var named := {
		"ENTRANCE": TunnelKnobs.ENTRANCE,
		"HUB_ANTECHAMBER": TunnelKnobs.HUB_ANTECHAMBER,
		"HUB_EAST": TunnelKnobs.HUB_EAST,
		"HUB_WEST": TunnelKnobs.HUB_WEST,
		"HUB_DEEP": TunnelKnobs.HUB_DEEP,
		"CORE_CHAMBER": TunnelKnobs.CORE_CHAMBER,
	}
	for key: String in named:
		if (named[key] as Vector3).distance_to(point) <= WELD_DISTANCE:
			return key
	return "dead_end_%.0f_%.0f_%.0f" % [point.x, point.y, point.z]


func _nearest_junction(point: Vector3) -> int:
	var best := -1
	var best_distance := INF
	for i: int in junctions.size():
		var distance := junctions[i].distance_squared_to(point)
		if distance < best_distance:
			best_distance = distance
			best = i
	return best
