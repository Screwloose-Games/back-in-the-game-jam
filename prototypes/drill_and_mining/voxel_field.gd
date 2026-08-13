class_name VoxelField
extends RefCounted

## One ore node's rock, as a signed distance field on a dense grid.
##
## Negative is solid, positive is empty, and the magnitude is roughly the
## distance to the surface in metres. That last part is not decoration: it is
## what lets the escape test ask "is there a tube of radius r clear from here to
## outside" by sampling one number per step instead of tracing a cone.
##
## THE FIELD IS ERODED, NOT SUBTRACTED FROM. A hard sphere subtraction per frame
## would advance the bore by its own radius every frame - metres per second, with
## no way to slow it down that does not also make the hole narrower. Adding a
## small amount to the field instead makes the surface recede at a rate in metres
## per second that is set directly, and the bore's width stays the beam's own.
##
## Values are held at grid CORNERS, not cell centres, because that is what
## surface nets consumes: one vertex per cell whose eight corners do not agree on
## a sign.
##
## Local space throughout. The owning OreNode does the world transform.

## Cells per axis, and the size of one, in metres.
var resolution: int
var voxel_size: float

## Sub-chunks per axis, and how many cells are in one. A carve touches a handful
## of sub-chunks and only those get remeshed.
var subchunks_per_axis: int
var subchunk_cells: int

## Corner values. Length is (resolution + 1) cubed - one more corner than cell
## along each axis.
var _field := PackedFloat32Array()
var _corners_per_axis: int

## Sub-chunks whose field has changed since the last remesh, oldest first.
var _dirty: Array[Vector3i] = []
var _dirty_lookup := {}


func _init(cells_per_axis: int, metres_per_cell: float, cells_per_subchunk: int) -> void:
	resolution = cells_per_axis
	voxel_size = metres_per_cell
	subchunk_cells = cells_per_subchunk
	subchunks_per_axis = int(ceil(float(resolution) / float(subchunk_cells)))
	_corners_per_axis = resolution + 1
	_field.resize(_corners_per_axis * _corners_per_axis * _corners_per_axis)


## Half the grid's extent in metres. The field is centred on the node's origin.
func half_extent() -> float:
	return resolution * voxel_size * 0.5


## Where a corner sits, in local metres.
func corner_position(x: int, y: int, z: int) -> Vector3:
	return (Vector3(x, y, z) - Vector3.ONE * resolution * 0.5) * voxel_size


## The raw corner value. No bounds check - callers walk known ranges.
func corner_value(x: int, y: int, z: int) -> float:
	return _field[x + _corners_per_axis * (y + _corners_per_axis * z)]


## Lays down a rough ball of rock: a sphere of `radius`, with its surface pushed
## in and out by a few octaves of noise so the node is not a billiard ball.
func fill_sphere(radius: float, noise_amplitude: float, rng: RandomNumberGenerator) -> void:
	# Three fixed frequencies with random phases, rather than a FastNoiseLite: the
	# field is only ever evaluated on this grid, the shape wanted is "lumpy ball"
	# rather than anything with a spectrum, and a seeded phase reproduces exactly.
	var phase_a := Vector3(rng.randf(), rng.randf(), rng.randf()) * TAU
	var phase_b := Vector3(rng.randf(), rng.randf(), rng.randf()) * TAU
	for z in _corners_per_axis:
		for y in _corners_per_axis:
			for x in _corners_per_axis:
				var point := corner_position(x, y, z)
				var lumps := (
					sin(point.x * 2.7 + phase_a.x)
					+ sin(point.y * 3.1 + phase_a.y)
					+ sin(point.z * 2.3 + phase_a.z)
				)
				# The high band has to be high. At 0.1 m cells a feature needs a
				# wavelength of about half a metre before the mesher can express
				# it at all, and the first pass at this used frequencies around 7
				# - a metre and a half - which came out as a smooth egg rather
				# than as rock.
				var grain := (
					sin(point.x * 13.1 + phase_b.x)
					+ sin(point.y * 11.7 + phase_b.y)
					+ sin(point.z * 12.3 + phase_b.z)
				)
				var surface := radius + (lumps * 0.55 + grain * 0.45) * noise_amplitude / 3.0
				_field[x + _corners_per_axis * (y + _corners_per_axis * z)] = (
					point.length() - surface
				)
	_mark_all_dirty()


## Eats away at the field around `centre`, hardest at the middle and tapering to
## nothing at `radius`. `amount` is how far the surface recedes at the centre, in
## metres - so it is (rate per second * delta) and nothing more complicated.
##
## Returns true if anything actually changed, so a beam pointed at a hole it has
## already made does not queue remeshes for nothing.
func erode(centre: Vector3, radius: float, amount: float) -> bool:
	if amount <= 0.0 or radius <= 0.0:
		return false
	var low := _cell_of(centre - Vector3.ONE * radius)
	var high := _cell_of(centre + Vector3.ONE * radius) + Vector3i.ONE
	low = low.clampi(0, resolution)
	high = high.clampi(0, resolution)

	# Above this the field stops being a useful distance and starts being a big
	# number that the escape test would read as a very wide tunnel.
	var ceiling := half_extent()
	var changed := false
	for z in range(low.z, high.z + 1):
		for y in range(low.y, high.y + 1):
			for x in range(low.x, high.x + 1):
				var offset := corner_position(x, y, z) - centre
				var distance := offset.length()
				if distance >= radius:
					continue
				var index := x + _corners_per_axis * (y + _corners_per_axis * z)
				var previous: float = _field[index]
				if previous >= ceiling:
					continue
				# Squared falloff: the middle of the bore cuts fastest, the rim
				# barely at all, which is what rounds the hole instead of
				# stamping a cylinder.
				var taper := 1.0 - distance / radius
				_field[index] = minf(previous + amount * taper * taper, ceiling)
				changed = true

	if changed:
		_mark_dirty_range(low, high)
	return changed


## The field between corners, trilinearly. Outside the grid it reports empty.
func sample(point: Vector3) -> float:
	var grid := point / voxel_size + Vector3.ONE * resolution * 0.5
	if (
		grid.x < 0.0
		or grid.y < 0.0
		or grid.z < 0.0
		or grid.x > resolution
		or grid.y > resolution
		or grid.z > resolution
	):
		return half_extent()
	var base := Vector3i(floori(grid.x), floori(grid.y), floori(grid.z)).clampi(0, resolution - 1)
	var fraction := grid - Vector3(base)
	var x0 := base.x
	var y0 := base.y
	var z0 := base.z
	var lower := lerpf(
		lerpf(corner_value(x0, y0, z0), corner_value(x0 + 1, y0, z0), fraction.x),
		lerpf(corner_value(x0, y0 + 1, z0), corner_value(x0 + 1, y0 + 1, z0), fraction.x),
		fraction.y
	)
	var upper := lerpf(
		lerpf(corner_value(x0, y0, z0 + 1), corner_value(x0 + 1, y0, z0 + 1), fraction.x),
		lerpf(corner_value(x0, y0 + 1, z0 + 1), corner_value(x0 + 1, y0 + 1, z0 + 1), fraction.x),
		fraction.y
	)
	return lerpf(lower, upper, fraction.z)


## Walks a ray until it is inside rock. Returns the distance along it, or -1.
##
## This is what the drill hits, INSTEAD OF A PHYSICS RAYCAST. The collision
## shapes lag the field by design - they are rebuilt on a budget - so a ray cast
## against them would carve at a surface that is a few frames stale. Walking the
## field is exact, always current, and costs nothing worth measuring on a grid
## this size.
func raymarch(origin: Vector3, direction: Vector3, max_distance: float) -> float:
	var step := voxel_size * 0.5
	var travelled := 0.0
	var previous := sample(origin)
	if previous < 0.0:
		return 0.0
	while travelled < max_distance:
		travelled = minf(travelled + step, max_distance)
		var here := sample(origin + direction * travelled)
		if here < 0.0:
			# Bisect back to the crossing. Four rounds puts it inside a
			# sixteenth of a cell, well under what the eye or the carve needs.
			var behind := travelled - step
			for _round in 4:
				var middle := (behind + travelled) * 0.5
				if sample(origin + direction * middle) < 0.0:
					travelled = middle
				else:
					behind = middle
			return travelled
		previous = here
	return -1.0


## Which way the surface faces at a point: out of the rock, or zero where the
## field is flat enough to have no opinion.
##
## THE FIELD IS ITS OWN NORMAL. The gradient of a signed distance field points
## the way the value grows, and the value grows outward, so six samples of
## central differences settle it - no mesh, no triangle lookup, no normal buffer
## to search. That matters here beyond being cheap: it answers for the surface as
## it is this frame, where the mesh is one or two frames behind.
##
## Zero is a real answer and callers have to handle it. Deep inside rock the
## erosion has already bottomed out, every neighbour reads the same, and there is
## no direction to give.
func sample_normal(point: Vector3) -> Vector3:
	var step := voxel_size * 0.5
	var slope := Vector3(
		sample(point + Vector3(step, 0.0, 0.0)) - sample(point - Vector3(step, 0.0, 0.0)),
		sample(point + Vector3(0.0, step, 0.0)) - sample(point - Vector3(0.0, step, 0.0)),
		sample(point + Vector3(0.0, 0.0, step)) - sample(point - Vector3(0.0, 0.0, step))
	)
	if slope.is_zero_approx():
		return Vector3.ZERO
	return slope.normalized()


## The radius of the widest clear tube that fits along a ray, in metres.
##
## THE FIELD ANSWERS THIS IN ONE PASS AND NO SEARCH. Its magnitude at a point is
## the distance to the nearest rock, so the narrowest sample along the ray is
## exactly how wide a tube fits down the whole of it. There is nothing to bisect
## and no cone of rays to trace - which matters, because this runs on every frame
## the beam is cutting.
##
## Negative means the ray starts or passes inside rock.
func narrowest_along(origin: Vector3, direction: Vector3, distance: float) -> float:
	var step := voxel_size
	var travelled := 0.0
	var narrowest := INF
	while travelled <= distance:
		narrowest = minf(narrowest, sample(origin + direction * travelled))
		if narrowest <= 0.0:
			return narrowest
		travelled += step
	return narrowest


## How much of the original rock is left, 0 to 1, by corner count. Approximate
## and cheap - it is a HUD readout, not a measurement.
func solid_fraction(original_solid_corners: int) -> float:
	if original_solid_corners <= 0:
		return 0.0
	return float(count_solid_corners()) / float(original_solid_corners)


func count_solid_corners() -> int:
	var solid := 0
	for index in _field.size():
		if _field[index] < 0.0:
			solid += 1
	return solid


## A detached copy of every field corner, suitable for a late-join snapshot.
## Callers cannot accidentally mutate the live field through the returned array.
func export_values() -> PackedFloat32Array:
	return _field.duplicate()


## Replaces every field corner from a snapshot. A snapshot from a differently
## configured field is rejected without changing this one.
func import_values(values: PackedFloat32Array) -> bool:
	if values.size() != _field.size():
		return false
	for value: float in values:
		if not is_finite(value):
			return false
	_field = values.duplicate()
	_dirty.clear()
	_dirty_lookup.clear()
	_mark_all_dirty()
	return true


## Sub-chunks waiting to be remeshed, oldest first. The caller takes as many as
## its frame budget allows and leaves the rest.
func take_dirty(limit: int) -> Array[Vector3i]:
	var taken: Array[Vector3i] = []
	while not _dirty.is_empty() and taken.size() < limit:
		var subchunk: Vector3i = _dirty.pop_front()
		_dirty_lookup.erase(subchunk)
		taken.append(subchunk)
	return taken


func has_dirty() -> bool:
	return not _dirty.is_empty()


func _cell_of(point: Vector3) -> Vector3i:
	var grid := point / voxel_size + Vector3.ONE * resolution * 0.5
	return Vector3i(floori(grid.x), floori(grid.y), floori(grid.z))


func _mark_all_dirty() -> void:
	for z in subchunks_per_axis:
		for y in subchunks_per_axis:
			for x in subchunks_per_axis:
				_queue(Vector3i(x, y, z))


## Every sub-chunk overlapping a range of corners, plus one either side: a corner
## on a boundary belongs to the cells on both sides of it, and a sub-chunk builds
## its quads from a one-cell skirt around its own territory.
func _mark_dirty_range(low: Vector3i, high: Vector3i) -> void:
	var first := (low - Vector3i.ONE).clampi(0, resolution) / subchunk_cells
	var last := (high + Vector3i.ONE).clampi(0, resolution) / subchunk_cells
	for z in range(first.z, mini(last.z, subchunks_per_axis - 1) + 1):
		for y in range(first.y, mini(last.y, subchunks_per_axis - 1) + 1):
			for x in range(first.x, mini(last.x, subchunks_per_axis - 1) + 1):
				_queue(Vector3i(x, y, z))


func _queue(subchunk: Vector3i) -> void:
	if _dirty_lookup.has(subchunk):
		return
	_dirty_lookup[subchunk] = true
	_dirty.append(subchunk)
