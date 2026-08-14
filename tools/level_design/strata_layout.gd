extends RefCounted

## Works out where an anthill's chambers and tunnels go, as plain numbers.
##
## AN ANTHILL IN SECTION, WHICH IS NOT A STACK OF DISCS. A stratum is horizontal
## and nothing about it is flat: its chambers sit on a warped surface rather than
## at one depth, each is a different width and a different thickness, and the plan
## is grown by throwing darts rather than stepped round a ring. Strata stagger
## sideways from one another, and where two of them come close they are joined
## straight through the floor - or, where they come closer still, they simply
## intersect and one cavity spans both.
##
## NOTHING HERE TOUCHES THE SCENE TREE. This returns records; BlockoutScaffold
## turns them into MineSpaces and MineTunnels and decides their tags. Keeping the
## split means the shape can be reasoned about, and re-rolled, without a level
## being built - and it is the one part of a biome worth being able to test on its
## own numbers.
##
## SEEDED, so one spec always produces one layout. Everything is a range drawn
## from `seed`, which is the knob to re-roll when a layout comes out wrong.
##
## NO class_name, DELIBERATELY, for the reason blockout_scaffold.gd gives: tools/
## carries a .gdignore. Callers preload the path and instance it.

## How far apart in the noise field two strata read their surface warp from.
## Large enough that no two of them see a related shape.
const WARP_SAMPLE_REACH := 900.0

## How many rejected darts in a row end a stratum's scatter early. Generous,
## because a nearly full stratum rejects a great many before it finds its last
## gap, and stopping early there costs a chamber nobody asked for.
const SCATTER_FAILURE_BUDGET := 40

## A bore's width as a multiple of the smaller chamber it joins, min and max.
##
## MOST OF THIS RANGE IS WIDE ENOUGH THAT A BORE MERGES WITH ITS CHAMBERS, which
## is what makes a stratum one continuous flat void with pillars standing in it
## rather than a warren of rooms joined by corridors. An anthill's strata are
## continuous; the pillars are what is left of the ground, not what was added.
##
## THE LOW END IS UNDER THE CREATURE'S WIDTH ON PURPOSE - a stratum with no
## squeeze anywhere in it is a stratum with nowhere to hide.
const BORE_WIDTH_PER_RADIUS := Vector2(0.9, 2.6)

## A bore's floor-to-roof as a multiple of the thinner chamber's vertical semi
## axis. Under 2.0, so a bore can never break above the roof of a chamber it runs
## into and the stratum keeps a continuous ceiling.
const BORE_HEIGHT_PER_EXTENT := 1.4

## How far a bore's corner strays sideways, as a fraction of its own length.
const BORE_WANDER_FRACTION := 0.18

## And vertically, in metres. Small and absolute rather than proportional: a bore
## that wandered up and down in step with its length would leave its own stratum.
const BORE_WANDER_VERTICAL := 1.5

## Bores shorter than this run straight. A corner in a 12 m hop reads as a kink.
const BORE_BEND_MIN_LENGTH := 18.0

## How much of two chambers' combined radius may separate them in plan and still
## count as one sitting over the other. A breach is a hole in a floor; anything
## looser would be a shaft cutting diagonally across the level.
const BREACH_PLAN_OVERLAP := 0.9

## The longest spare edge a stratum will add for a loop, as a multiple of the
## scatter's own maximum spacing.
const SPARE_EDGE_REACH := 1.5

var _strata: Dictionary = {}
var _generator := RandomNumberGenerator.new()
var _surface := FastNoiseLite.new()

## Array of strata, each an Array of chamber records.
var _chambers: Array = []

var _bores: Array = []
var _breaches: Array = []
var _long_links: Array = []
var _anchors: Dictionary = {}
var _arrivals: Dictionary = {}
var _merges := 0


## The whole layout for one strata spec.
##
## A strata dictionary is:
##
##   prefix               name prefix for every chamber and tunnel.
##   seed                 re-roll for a different layout from the same knobs.
##   center               the point the top stratum is grown around.
##   count                how many strata.
##   top_y                depth of the first one.
##   gap                  Vector2 min/max drop to the next stratum.
##   drift                how far a stratum's centre wanders from the one above.
##                        THIS IS THE STAGGER, and it is why no stratum sits
##                        squarely on its neighbour.
##   spread               plan radius one stratum covers.
##   undulation           metres the stratum surface waves up and down.
##   undulation_scale     metres per wave feature. Near blob_spacing gives a
##                        stratum that rises and falls once or twice across.
##   blobs                Vector2i min/max chambers per stratum.
##   blob_spacing         Vector2 min/max metres between neighbours. The minimum
##                        doubles as the rejection distance when scattering.
##   blob_radius          Vector2 min/max horizontal radius.
##   blob_vertical_scale  Vector2 min/max vertical radius as a fraction of the
##                        horizontal one. Drawn independently of the radius,
##                        WHICH IS WHAT GIVES A STRATUM UNEVEN THICKNESS rather
##                        than one flat gap repeated across it.
##   blob_jitter          extra metres of y wobble on top of the surface.
##   bore_width           Vector2 clamp on the width derived from two chambers.
##   bore_height          Vector2 min/max floor to roof, capped under the
##                        chambers a bore joins.
##   extra_edges          edges beyond the spanning tree, as a fraction of the
##                        chamber count. Zero is a tree and has no loops.
##   breach_gap           metres of rock under which two strata get joined.
##   breach_width         Vector2 min/max across, for those joins.
##   breaches_per_gap     cap, so the stack does not become a colander.
##   long_links           how many tunnels skipping two or more strata.
##   long_link_width      Vector2 min/max across, for those.
##   anchors              name -> {stratum, near: Vector3}. See _place_anchors.
##
## Returns:
##
##   chambers    Array of strata, each an Array of {name, position, radius,
##               vertical_scale, kind}.
##   bores       tunnel records within a stratum.
##   breaches    tunnel records between neighbouring strata. `merged` marks the
##               ones whose two chambers already intersect.
##   long_links  tunnel records skipping two or more strata.
##   anchors     alias -> chamber name.
##   arrivals    chamber name -> how many tunnels reach it.
##   merges      how many breaches were merges.
##
## Tunnel records carry everything BlockoutScaffold._add_tunnel wants except the
## tags, which depend on the level's creature width and on the spec's tag lists.
func build(strata: Dictionary) -> Dictionary:
	_strata = strata
	_generator.seed = strata.get("seed", 0)
	_surface.seed = strata.get("seed", 0)
	_surface.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_surface.frequency = 1.0 / maxf(strata["undulation_scale"], 0.001)

	_scatter_all()
	_place_anchors()
	# Offset from the layout's own seed, so the wiring does not replay the exact
	# sequence of numbers the scatter already drew.
	_generator.seed = int(strata.get("seed", 0)) + 1
	for index: int in _chambers.size():
		_wire_stratum(index)
	for index: int in _chambers.size() - 1:
		_breach_strata(index)
	_add_long_links()

	return {
		"chambers": _chambers,
		"bores": _bores,
		"breaches": _breaches,
		"long_links": _long_links,
		"anchors": _anchors,
		"arrivals": _arrivals,
		"merges": _merges,
	}


func _scatter_all() -> void:
	var origin: Vector3 = _strata["center"]
	var middle := Vector2(origin.x, origin.z)
	var depth: float = _strata["top_y"]
	var gap: Vector2 = _strata["gap"]
	var drift: float = _strata.get("drift", 0.0)

	for index: int in int(_strata["count"]):
		if index > 0:
			depth -= _generator.randf_range(gap.x, gap.y)
			var heading := _generator.randf_range(0.0, TAU)
			middle += Vector2(cos(heading), sin(heading)) * _generator.randf_range(0.0, drift)
		# EACH STRATUM READS THE NOISE SOMEWHERE ELSE ENTIRELY, or every one of them
		# would rise and fall in step with the one above and the stack would stay as
		# parallel as a flat stack was - waving in unison is still waving in unison.
		# Independent warps are what let two strata converge in one corner of the
		# biome and separate in another, which is what brings them into reach of
		# each other at all.
		var warp := Vector2(
			_generator.randf_range(-WARP_SAMPLE_REACH, WARP_SAMPLE_REACH),
			_generator.randf_range(-WARP_SAMPLE_REACH, WARP_SAMPLE_REACH)
		)
		_chambers.append(_scatter_stratum(warp, middle, depth, index))


## One stratum's chambers, scattered by throwing darts from the ones already
## placed rather than by stepping round a ring.
##
## A DART LANDS AT A RANDOM BEARING FROM A RANDOM CHAMBER ALREADY DOWN, which
## grows the lobed, branching, locally dense plan an anthill has. Rejecting
## anything closer than the minimum spacing is what stops it collapsing into a
## clump; rejecting anything outside `spread` is what keeps a stratum a stratum.
func _scatter_stratum(warp: Vector2, middle: Vector2, depth: float, index: int) -> Array:
	var plan := _throw_darts(middle)
	var radii: Vector2 = _strata["blob_radius"]
	var scales: Vector2 = _strata["blob_vertical_scale"]
	var jitter: float = _strata.get("blob_jitter", 0.0)
	var undulation: float = _strata["undulation"]

	var stratum: Array = []
	for blob: int in plan.size():
		var flat := plan[blob]
		# The shared noise term is what makes a stratum one coherent wavy sheet;
		# the jitter is what stops it reading as a function of position.
		var height := (
			depth
			+ _surface.get_noise_2d(flat.x + warp.x, flat.y + warp.y) * undulation
			+ _generator.randf_range(-jitter, jitter)
		)
		var radius := _generator.randf_range(radii.x, radii.y)
		var record := {
			"name": "%s_s%d_b%02d" % [_strata["prefix"], index, blob],
			"position": Vector3(flat.x, height, flat.y),
			"radius": radius,
			"vertical_scale": _generator.randf_range(scales.x, scales.y),
			"kind": "room" if radius > (radii.x + radii.y) * 0.5 else "junction",
		}
		stratum.append(record)
	return stratum


func _throw_darts(middle: Vector2) -> Array[Vector2]:
	var spacing: Vector2 = _strata["blob_spacing"]
	var spread: float = _strata["spread"]
	var wanted: Vector2i = _strata["blobs"]
	var target := _generator.randi_range(wanted.x, wanted.y)

	var plan: Array[Vector2] = [middle]
	var failures := 0
	while plan.size() < target and failures < SCATTER_FAILURE_BUDGET:
		var anchor: Vector2 = plan[_generator.randi_range(0, plan.size() - 1)]
		var heading := _generator.randf_range(0.0, TAU)
		var reach := _generator.randf_range(spacing.x, spacing.y)
		var candidate := anchor + Vector2(cos(heading), sin(heading)) * reach
		if candidate.distance_to(middle) > spread or _crowds(plan, candidate, spacing.x):
			failures += 1
			continue
		plan.append(candidate)
		failures = 0
	return plan


## Whether a candidate lands close enough to a chamber already placed that the
## two would carve as one blob rather than as two.
func _crowds(plan: Array[Vector2], candidate: Vector2, minimum: float) -> bool:
	for placed: Vector2 in plan:
		if placed.distance_to(candidate) < minimum:
			return true
	return false


## A stable alias for a generated chamber, so something outside the generator can
## name one.
##
## NOTHING ELSE CAN REFER TO A CHAMBER AND STAY CORRECT. A chamber's name carries
## an index that moves the moment the seed is re-rolled, so a hand-written tunnel
## naming `hv_s1_b04` would quietly arrive somewhere else every time the layout
## was retuned. An anchor names a place instead - the chamber in this stratum
## nearest this point - which survives a re-roll.
func _place_anchors() -> void:
	var requests: Dictionary = _strata.get("anchors", {})
	for alias: String in requests:
		var request: Dictionary = requests[alias]
		var index: int = request["stratum"]
		if index < 0 or index >= _chambers.size():
			printerr("Anchor '%s' names stratum %d, which was not built." % [alias, index])
			continue
		var nearest := ""
		var best := INF
		for chamber: Dictionary in _chambers[index] as Array:
			var distance := _plan_distance(chamber["position"], request["near"])
			if distance < best:
				best = distance
				nearest = chamber["name"]
		if nearest.is_empty():
			printerr("Anchor '%s' found no chamber in stratum %d." % [alias, index])
			continue
		_anchors[alias] = nearest


## Every chamber in a stratum joined to its neighbours: a spanning tree first, so
## nothing is stranded, then the shortest few spare edges so there are loops.
##
## A TREE WOULD BE A CORRIDOR WITH ROOMS OFF IT. The loops are what make a stratum
## somewhere you can be lost inside rather than a route you walk back out of.
func _wire_stratum(index: int) -> void:
	var stratum: Array = _chambers[index]
	if stratum.size() < 2:
		return

	var chosen: Dictionary = {}
	for edge: Vector2i in _spanning_edges(stratum):
		chosen[_edge_key(edge)] = edge
	var spacing: Vector2 = _strata["blob_spacing"]
	var wanted := int(round(float(stratum.size()) * float(_strata.get("extra_edges", 0.0))))
	for edge: Vector2i in _spare_edges(stratum, chosen, wanted, spacing.y * SPARE_EDGE_REACH):
		chosen[_edge_key(edge)] = edge

	for key: String in chosen:
		_bores.append(_describe_bore(stratum, chosen[key], index))


## Prim's, scanning for the cheapest crossing edge each round. A stratum is a
## dozen chambers, so a heap would be more machinery than the problem has.
func _spanning_edges(stratum: Array) -> Array[Vector2i]:
	var edges: Array[Vector2i] = []
	var inside: Dictionary = {0: true}
	while inside.size() < stratum.size():
		var best := Vector2i(-1, -1)
		var shortest := INF
		for from_index: int in stratum.size():
			if not inside.has(from_index):
				continue
			for to_index: int in stratum.size():
				if inside.has(to_index):
					continue
				var span := _chamber_distance(stratum, from_index, to_index)
				if span < shortest:
					shortest = span
					best = Vector2i(from_index, to_index)
		if best.x < 0:
			break
		inside[best.y] = true
		edges.append(best)
	return edges


## The `wanted` shortest edges the spanning tree did not already take, ignoring
## anything longer than `cap` - a loop closed across the whole stratum is a
## corridor, not a loop.
func _spare_edges(stratum: Array, chosen: Dictionary, wanted: int, cap: float) -> Array[Vector2i]:
	var spare: Array[Vector2i] = []
	if wanted <= 0:
		return spare
	for from_index: int in stratum.size():
		for to_index: int in range(from_index + 1, stratum.size()):
			var edge := Vector2i(from_index, to_index)
			if chosen.has(_edge_key(edge)):
				continue
			if _chamber_distance(stratum, from_index, to_index) > cap:
				continue
			spare.append(edge)
	spare.sort_custom(
		func(left: Vector2i, right: Vector2i) -> bool:
			return (
				_chamber_distance(stratum, left.x, left.y)
				< _chamber_distance(stratum, right.x, right.y)
			)
	)
	spare.resize(mini(wanted, spare.size()))
	return spare


## One bore between two chambers in the same stratum.
##
## Its width comes from the smaller of the two, so a run between two big rooms is
## a hall and a run out to a small one is a squeeze - which is what replaces the
## single width every layer of the old stack shared. Its floor-to-roof is capped
## under both chambers so a bore never breaks through the roof of what it joins,
## AND THAT CAP IS WHAT KEEPS A STRATUM READING AS FLAT now that the chambers
## themselves are allowed to be large.
func _describe_bore(stratum: Array, edge: Vector2i, index: int) -> Dictionary:
	var from_chamber: Dictionary = stratum[edge.x]
	var to_chamber: Dictionary = stratum[edge.y]

	var limits: Vector2 = _strata["bore_width"]
	var smaller: float = minf(from_chamber["radius"], to_chamber["radius"])
	var spread := _generator.randf_range(BORE_WIDTH_PER_RADIUS.x, BORE_WIDTH_PER_RADIUS.y)

	var heights: Vector2 = _strata["bore_height"]
	var thinnest := minf(_vertical_extent(from_chamber), _vertical_extent(to_chamber))
	var span := _chamber_distance(stratum, edge.x, edge.y)

	_count_arrival(from_chamber["name"])
	_count_arrival(to_chamber["name"])
	return {
		"name": "%s_s%d_bore_%02d_%02d" % [_strata["prefix"], index, edge.x, edge.y],
		"from": from_chamber["name"],
		"to": to_chamber["name"],
		"width": clampf(smaller * spread, limits.x, limits.y),
		"height":
		minf(_generator.randf_range(heights.x, heights.y), thinnest * BORE_HEIGHT_PER_EXTENT),
		"bends": 1 if span > BORE_BEND_MIN_LENGTH else 0,
		"wander": span * BORE_WANDER_FRACTION,
		"wander_vertical": BORE_WANDER_VERTICAL,
		"seed": _generator.randi(),
	}


## Where two strata come close they are joined; where they intersect they are
## already one cavity and the join only tells the graph so.
##
## THIS IS THE ANTHILL'S DEFINING FEATURE. Its strata are not floors with stairs
## between them - they run into one another, and a hole in the floor of one is the
## roof of the next. Both cases fall out of the same clearance measurement, which
## is why they are not two pieces of code.
func _breach_strata(index: int) -> void:
	var candidates := _breach_candidates(index)
	# Shuffled rather than sorted by clearance, so the breaches are not all in the
	# one place where the two strata happen to be closest.
	_shuffle(candidates)

	# NEIGHBOURING STRATA ARE ALWAYS JOINED TO EACH OTHER, even when the layout put
	# nothing within reach. Otherwise crossing that boundary depends on a long link
	# happening to land on both sides of it, and a re-roll that does not produce
	# one leaves a wing of the biome reachable only the long way round.
	if candidates.is_empty():
		var nearest := _nearest_pair(_chambers[index], _chambers[index + 1])
		if nearest.is_empty():
			return
		candidates.append(nearest)

	var widths: Vector2 = _strata["breach_width"]
	var cap: int = _strata.get("breaches_per_gap", 3)
	for chosen: int in mini(cap, candidates.size()):
		var candidate: Dictionary = candidates[chosen]
		if candidate["merged"]:
			_merges += 1
		_count_arrival(candidate["upper"]["name"])
		_count_arrival(candidate["lower"]["name"])
		(
			_breaches
			. append(
				{
					"name": "%s_breach_%d_%d_%d" % [_strata["prefix"], index, index + 1, chosen],
					"from": candidate["upper"]["name"],
					"to": candidate["lower"]["name"],
					"width": _generator.randf_range(widths.x, widths.y),
					"merged": candidate["merged"],
				}
			)
		)


## Every pair of chambers, one from each of two neighbouring strata, that sits
## over the other with little enough rock between them to be worth joining.
func _breach_candidates(index: int) -> Array:
	var reach: float = _strata["breach_gap"]
	var candidates: Array = []
	for upper: Dictionary in _chambers[index] as Array:
		var upper_position: Vector3 = upper["position"]
		for lower: Dictionary in _chambers[index + 1] as Array:
			var lower_position: Vector3 = lower["position"]
			var apart: float = float(upper["radius"]) + float(lower["radius"])
			if _plan_distance(upper_position, lower_position) > apart * BREACH_PLAN_OVERLAP:
				continue
			# Upper floor to lower roof. Negative means the two already intersect.
			var clearance := (
				(upper_position.y - _vertical_extent(upper))
				- (lower_position.y + _vertical_extent(lower))
			)
			if clearance > reach:
				continue
			candidates.append({"upper": upper, "lower": lower, "merged": clearance < 0.0})
	return candidates


## The tunnels that skip two or more strata.
##
## THESE ARE WHAT MAKE THE STACK UNTRUSTWORTHY: coming up one of them puts you
## somewhere that looks like where you started and is a long way from it.
func _add_long_links() -> void:
	if _chambers.size() < 3:
		return
	var widths: Vector2 = _strata["long_link_width"]
	for link: int in int(_strata.get("long_links", 0)):
		var from_stratum := _generator.randi_range(0, _chambers.size() - 3)
		var to_stratum := _generator.randi_range(from_stratum + 2, _chambers.size() - 1)
		var from_chamber := _any_chamber(_chambers[from_stratum])
		var to_chamber := _any_chamber(_chambers[to_stratum])
		var span := (from_chamber["position"] as Vector3).distance_to(to_chamber["position"])
		_count_arrival(from_chamber["name"])
		_count_arrival(to_chamber["name"])
		(
			_long_links
			. append(
				{
					"name": "%s_long_%d" % [_strata["prefix"], link],
					"from": from_chamber["name"],
					"to": to_chamber["name"],
					"width": _generator.randf_range(widths.x, widths.y),
					"bends": 3,
					"wander": span * BORE_WANDER_FRACTION,
					"seed": _generator.randi(),
				}
			)
		)


## The two chambers, one from each stratum, that come closest to touching. The
## last resort when nothing in either stratum reached the other.
func _nearest_pair(upper_stratum: Array, lower_stratum: Array) -> Dictionary:
	var nearest: Dictionary = {}
	var shortest := INF
	for upper: Dictionary in upper_stratum:
		for lower: Dictionary in lower_stratum:
			var span := (upper["position"] as Vector3).distance_to(lower["position"])
			if span < shortest:
				shortest = span
				nearest = {"upper": upper, "lower": lower, "merged": false}
	return nearest


func _count_arrival(chamber_name: String) -> void:
	_arrivals[chamber_name] = int(_arrivals.get(chamber_name, 0)) + 1


## Metres from a chamber's centre to its roof.
func _vertical_extent(chamber: Dictionary) -> float:
	return float(chamber["radius"]) * float(chamber["vertical_scale"])


## Distance ignoring depth, which is the measurement that says whether one
## chamber sits over another.
func _plan_distance(first: Vector3, second: Vector3) -> float:
	return Vector2(first.x, first.z).distance_to(Vector2(second.x, second.z))


func _chamber_distance(stratum: Array, from_index: int, to_index: int) -> float:
	return (stratum[from_index]["position"] as Vector3).distance_to(stratum[to_index]["position"])


func _edge_key(edge: Vector2i) -> String:
	return "%d_%d" % [mini(edge.x, edge.y), maxi(edge.x, edge.y)]


func _any_chamber(stratum: Array) -> Dictionary:
	return stratum[_generator.randi_range(0, stratum.size() - 1)]


## Fisher-Yates against this layout's own generator. Array.shuffle draws from the
## global one, which no seed here controls and which would make the layout differ
## between runs.
func _shuffle(entries: Array) -> void:
	for index: int in range(entries.size() - 1, 0, -1):
		var swap := _generator.randi_range(0, index)
		var held: Variant = entries[index]
		entries[index] = entries[swap]
		entries[swap] = held
