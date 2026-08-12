class_name LevelGraph
extends RefCounted

## The mine level as a plain graph: rooms and junctions are nodes, tunnels are
## edges, and every element keeps the 3D position it was authored at.
##
## No scene tree and no editor dependency. The creature AI and the noise system
## can build one of these and ask it questions without pulling the design-time
## node types in behind them.
##
## EVERY DISTANCE IS METRES, LOUDNESS INCLUDED. A noise source is defined by the
## radius at which it can still be heard, so a noise budget and a tunnel length
## are the same kind of number and propagation is subtraction. Nothing here is in
## decibels, and nothing needs converting.
##
## A TUNNEL'S POLYLINE RUNS CENTRE TO CENTRE, not surface to surface, so the span
## inside a chamber is already carried by the two tunnels that meet there. Room
## radius is therefore NOT added to path cost - charging it as well would bill the
## same metres twice, and would make a hub read as further from its neighbours
## than the tunnel you actually fly down.
##
## SOUND DOES NOT PASS THROUGH ROCK, which is the whole reason this is a graph
## walk rather than a distance check. Two points can be 20 m apart through solid
## asteroid and 180 m apart along the only tunnel joining them.

enum SpaceKind {
	ROOM,  ## Somewhere you can stop, turn around and work.
	JUNCTION,  ## Where tunnels meet. Radius 0 means no chamber at all, just a corner.
	DEAD_END,  ## A pocket with one way in.
}

var spaces: Array[Space] = []
var tunnels: Array[Tunnel] = []

var _space_by_id: Dictionary = {}
var _tunnel_indices_at: Dictionary = {}


func add_space(space: Space) -> Space:
	spaces.append(space)
	_space_by_id[space.id] = space
	return space


func add_tunnel(tunnel: Tunnel) -> Tunnel:
	tunnels.append(tunnel)
	for endpoint: StringName in [tunnel.from_id, tunnel.to_id]:
		var indices: PackedInt32Array = _tunnel_indices_at.get(endpoint, PackedInt32Array())
		indices.append(tunnels.size() - 1)
		_tunnel_indices_at[endpoint] = indices
	return tunnel


func find_space(space_id: StringName) -> Space:
	return _space_by_id.get(space_id, null) as Space


func find_tunnel(tunnel_id: StringName) -> Tunnel:
	for tunnel: Tunnel in tunnels:
		if tunnel.id == tunnel_id:
			return tunnel
	return null


func tunnels_at(space_id: StringName) -> Array[Tunnel]:
	var found: Array[Tunnel] = []
	for index: int in _tunnel_indices_at.get(space_id, PackedInt32Array()) as PackedInt32Array:
		found.append(tunnels[index])
	return found


## How many tunnels meet here. Three or more is a real branch and wants a
## landmark; one is a dead end you are already standing in.
func degree(space_id: StringName) -> int:
	return (_tunnel_indices_at.get(space_id, PackedInt32Array()) as PackedInt32Array).size()


## Total centreline metres across every tunnel.
func total_length() -> float:
	var total := 0.0
	for tunnel: Tunnel in tunnels:
		total += tunnel.length()
	return total


## World box the level occupies, spaces expanded by their own radius.
func bounds() -> AABB:
	var box := AABB()
	var started := false
	for space: Space in spaces:
		var piece := AABB(space.position, Vector3.ZERO).grow(space.radius)
		box = piece if not started else box.merge(piece)
		started = true
	for tunnel: Tunnel in tunnels:
		for point: Vector3 in tunnel.polyline:
			var piece := AABB(point, Vector3.ZERO).grow(tunnel.width * 0.5)
			box = piece if not started else box.merge(piece)
			started = true
	return box


## Ids of every tunnel a creature of `min_width` metres across could fit down.
##
## The threshold is an argument rather than a stored field on purpose: the
## creature's real dimensions are not settled, and a level that baked the answer
## into each tunnel would have to be re-authored every time that number moved.
func passable_tunnel_ids(min_width: float) -> Array[StringName]:
	var found: Array[StringName] = []
	for tunnel: Tunnel in tunnels:
		if tunnel.width >= min_width:
			found.append(tunnel.id)
	return found


## Ids of every space with no route to `origin_id`, by flood fill. Empty means
## the level is connected. This catches an endpoint pointing at the wrong space,
## which otherwise shows up as a wing of the map nothing can ever reach.
func unreachable_from(origin_id: StringName) -> Array[StringName]:
	var visited := {origin_id: true}
	var queue: Array[StringName] = [origin_id]
	while not queue.is_empty():
		var current: StringName = queue.pop_back()
		for tunnel: Tunnel in tunnels_at(current):
			var other := tunnel.other_end(current)
			if not visited.has(other):
				visited[other] = true
				queue.append(other)
	var orphans: Array[StringName] = []
	for space: Space in spaces:
		if not visited.has(space.id):
			orphans.append(space.id)
	return orphans


## How far a noise of `loudness` metres made in `origin_id` carries through the
## tunnels.
func propagate_from_space(origin_id: StringName, loudness: float) -> SoundField:
	var field := _propagate({origin_id: loudness}, loudness)
	field.origin_description = "space %s" % origin_id
	if find_space(origin_id) != null:
		field.origin_position = find_space(origin_id).position
	return field


## The same, for a noise made partway along a tunnel - which is where a flying
## player usually is. `distance_along` is metres from the tunnel's `from` end.
##
## Seeds both endpoints with what is left of the noise after it has run up the
## tunnel to each of them, then walks the graph from both at once.
func propagate_from_tunnel(
	tunnel_id: StringName, distance_along: float, loudness: float
) -> SoundField:
	var tunnel := find_tunnel(tunnel_id)
	if tunnel == null:
		return SoundField.new()
	var span := clampf(distance_along, 0.0, tunnel.length())
	var seeds := {
		tunnel.from_id: loudness - span,
		tunnel.to_id: loudness - (tunnel.length() - span),
	}
	var field := _propagate(seeds, loudness, tunnel_id, span)
	field.origin_description = "%.0f m along tunnel %s" % [span, tunnel_id]
	field.origin_position = tunnel.point_at(span)
	return field


## What the straight-line model hears: everything inside a sphere, rock included.
##
## Kept alongside the graph walk so the two answers can be shown together. The
## gap between them IS the finding - a source 30 m away through solid asteroid
## and 180 m away along the only tunnel is inaudible in one model and deafening
## in the other.
func straight_line_audible_space_ids(origin: Vector3, loudness: float) -> Array[StringName]:
	var found: Array[StringName] = []
	for space: Space in spaces:
		if origin.distance_to(space.position) - space.radius <= loudness:
			found.append(space.id)
	return found


## The point `distance` metres along a polyline from its start.
static func point_on_polyline(points: PackedVector3Array, distance: float) -> Vector3:
	if points.is_empty():
		return Vector3.ZERO
	var travelled := 0.0
	for index: int in maxi(points.size() - 1, 0):
		var step := points[index].distance_to(points[index + 1])
		if travelled + step >= distance and step > 0.0:
			return points[index].lerp(points[index + 1], (distance - travelled) / step)
		travelled += step
	return points[points.size() - 1]


## The stretch of a polyline between two distances along it, with the cut ends
## interpolated so two adjacent slices meet exactly.
##
## Shared by the 3D view and the map renderer: both have to split a tunnel at the
## edge of what can hear a noise, and two implementations of that would disagree
## about where the quiet starts.
static func slice_polyline(
	points: PackedVector3Array, from_distance: float, to_distance: float
) -> PackedVector3Array:
	var slice := PackedVector3Array()
	if to_distance <= from_distance or points.size() < 2:
		return slice
	slice.append(point_on_polyline(points, from_distance))
	var travelled := 0.0
	for index: int in points.size() - 1:
		var reached := travelled + points[index].distance_to(points[index + 1])
		if reached > from_distance and reached < to_distance:
			slice.append(points[index + 1])
		travelled = reached
	slice.append(point_on_polyline(points, to_distance))
	return slice


## A basis for a bore running along `direction`: local Y is the run, local X is
## horizontal across it, local Z is the up-ish axis.
##
## THE POINT IS THE ROLL. A bore that is wider than it is tall - a hive layer -
## or taller than it is wide - the ravine - only reads that way if the code
## drawing it knows which of the two cross-section axes is vertical. A basis built
## from a bare Quaternion has whatever roll the maths happened to produce, so
## scaling one axis of it would tilt the slot at a different angle down every
## tunnel.
static func bore_basis(direction: Vector3) -> Basis:
	if direction.is_zero_approx():
		return Basis()
	var heading := direction.normalized()
	# Basis.looking_at cannot use an up vector parallel to its direction, and a
	# ravine's connecting shafts and a hive's risers are exactly vertical.
	var reference_up := Vector3.BACK if absf(heading.dot(Vector3.UP)) > 0.999 else Vector3.UP
	var facing := Basis.looking_at(heading, reference_up)
	# looking_at puts the run on -Z, width on X and up on Y. Cylinders run along
	# their own Y, so the axes rotate round one place.
	return Basis(facing.x, -facing.z, facing.y)


## Multi-source Dijkstra over tunnel lengths, maximising the loudness left on
## arrival - which is the same ordering as minimising distance travelled, and
## saves carrying both numbers.
##
## The level is a couple of dozen nodes, so selecting the best unsettled node by
## scanning beats maintaining a heap and is a great deal easier to read.
func _propagate(
	seed_budgets: Dictionary,
	loudness: float,
	origin_tunnel_id: StringName = &"",
	origin_span: float = 0.0
) -> SoundField:
	var field := SoundField.new()
	field.loudness = loudness

	var remaining := {}
	for space_id: StringName in seed_budgets:
		var budget: float = seed_budgets[space_id]
		if budget > 0.0 and _space_by_id.has(space_id):
			remaining[space_id] = budget

	var settled := {}
	while true:
		var current := StringName()
		var best := 0.0
		var found := false
		for space_id: StringName in remaining:
			if settled.has(space_id):
				continue
			var value: float = remaining[space_id]
			if not found or value > best:
				best = value
				current = space_id
				found = true
		if not found or best <= 0.0:
			break

		settled[current] = true
		for tunnel: Tunnel in tunnels_at(current):
			var carried := best - tunnel.length()
			if carried <= 0.0:
				continue
			var other := tunnel.other_end(current)
			if not remaining.has(other) or carried > float(remaining[other]):
				remaining[other] = carried

	field.remaining_at_space = remaining
	field.covered_intervals = _measure_covered_intervals(
		remaining, origin_tunnel_id, origin_span, loudness
	)
	return field


## Which stretches of each tunnel can hear the source, as metres along the
## centreline from the tunnel's `from` end.
##
## A tunnel is not audible-or-not as a unit: a 170 m squeeze with 60 m of noise
## entering one end is loud for its first 60 m and silent for the rest, and where
## the creature happens to be along it decides whether it heard you.
##
## INTERVALS RATHER THAN A REACH PER END, because a source partway along a tunnel
## lights a stretch in the MIDDLE of it, with silence at both ends. Two numbers
## measured inward from the ends cannot express that and would under-report the
## one tunnel the noise was actually made in.
func _measure_covered_intervals(
	remaining: Dictionary, origin_tunnel_id: StringName, origin_span: float, loudness: float
) -> Dictionary:
	var covered := {}
	for tunnel: Tunnel in tunnels:
		var span := tunnel.length()
		var intervals: Array[Vector2] = []

		var from_reach := clampf(float(remaining.get(tunnel.from_id, 0.0)), 0.0, span)
		if from_reach > 0.0:
			intervals.append(Vector2(0.0, from_reach))

		var to_reach := clampf(float(remaining.get(tunnel.to_id, 0.0)), 0.0, span)
		if to_reach > 0.0:
			intervals.append(Vector2(span - to_reach, span))

		if tunnel.id == origin_tunnel_id:
			intervals.append(
				Vector2(maxf(origin_span - loudness, 0.0), minf(origin_span + loudness, span))
			)

		covered[tunnel.id] = _merge_intervals(intervals)
	return covered


## Sorts by start and folds overlapping or touching spans together, so a caller
## drawing the lit stretches never draws one twice.
func _merge_intervals(intervals: Array[Vector2]) -> Array[Vector2]:
	if intervals.is_empty():
		return intervals
	intervals.sort_custom(func(left: Vector2, right: Vector2) -> bool: return left.x < right.x)
	var merged: Array[Vector2] = [intervals[0]]
	for index: int in range(1, intervals.size()):
		var current := intervals[index]
		var last: Vector2 = merged[merged.size() - 1]
		if current.x <= last.y:
			merged[merged.size() - 1] = Vector2(last.x, maxf(last.y, current.y))
		else:
			merged.append(current)
	return merged


## One node: a room, a junction, or a dead-end pocket.
class Space:
	extends RefCounted

	var id: StringName
	var kind: LevelGraph.SpaceKind = LevelGraph.SpaceKind.ROOM
	var position := Vector3.ZERO

	## Metres. Zero is legal and means a junction with no chamber cut at it - two
	## tunnels simply meeting at a corner.
	var radius := 0.0

	var tags: Array[StringName] = []
	var notes := ""


## One edge: a tunnel joining two spaces, bending through any waypoints between.
class Tunnel:
	extends RefCounted

	var id: StringName
	var from_id: StringName
	var to_id: StringName

	## Centre to centre, both endpoints included. Bends are extra points in here
	## and are deliberately NOT graph nodes - a corner you fly round is not a
	## place where a decision gets made.
	var polyline := PackedVector3Array()

	## Metres across. What decides whether the creature fits.
	var width := 0.0

	## Metres floor to roof. Zero means "same as width", which is every tunnel a
	## machine cut.
	##
	## Width still decides creature fit and still drives the width colour mode.
	## Height is shape only: it is what makes the ravine a tall slot and a hive
	## layer a flat one, and a creature that fits through the width of a 24 x 5
	## layer is not helped by it being 24 wide.
	var height := 0.0

	var tags: Array[StringName] = []
	var notes := ""

	var _length := -1.0

	## Metres floor to roof, resolved. Square unless something said otherwise.
	func bore_height() -> float:
		return height if height > 0.0 else width

	func length() -> float:
		if _length < 0.0:
			_length = 0.0
			for index: int in maxi(polyline.size() - 1, 0):
				_length += polyline[index].distance_to(polyline[index + 1])
		return _length

	func other_end(space_id: StringName) -> StringName:
		return to_id if space_id == from_id else from_id

	## The point `distance` metres along the centreline from the `from` end.
	func point_at(distance: float) -> Vector3:
		return LevelGraph.point_on_polyline(polyline, distance)


## The result of one noise event: what is left of it everywhere it reached.
class SoundField:
	extends RefCounted

	var origin_description := ""
	var origin_position := Vector3.ZERO

	## Metres of carrying power the source started with.
	var loudness := 0.0

	## space id -> metres of loudness still in hand on arrival. A space absent
	## from this map never heard it at all.
	var remaining_at_space: Dictionary = {}

	## tunnel id -> Array[Vector2] of (start, end) metres along that tunnel's
	## centreline from its `from` end. Sorted and non-overlapping. An empty array
	## means no part of that tunnel heard anything.
	var covered_intervals: Dictionary = {}

	func can_hear_space(space_id: StringName) -> bool:
		return remaining_at_space.has(space_id)

	## Metres of this tunnel that can hear the source.
	func covered_length(tunnel_id: StringName) -> float:
		var total := 0.0
		for interval: Vector2 in covered_intervals.get(tunnel_id, [] as Array[Vector2]):
			total += interval.y - interval.x
		return total

	## Whether any part of this tunnel can hear the source.
	func can_hear_anywhere_in_tunnel(tunnel_id: StringName) -> bool:
		return not (covered_intervals.get(tunnel_id, [] as Array[Vector2]) as Array).is_empty()

	## Whether every part of this tunnel can hear it, given its length.
	func can_hear_throughout_tunnel(tunnel_id: StringName, tunnel_length: float) -> bool:
		return covered_length(tunnel_id) >= tunnel_length - 0.001
