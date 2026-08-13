class_name NavGraphBuilder
extends RefCounted

## Turns terrain into a sparse topology graph (navigation.md sections 12, 13).
##
## A RESUMABLE JOB, NOT A FUNCTION. Section 32 caps the whole navigation budget at
## 10 ms and asks for expensive work to be "distributed over frames"; a bake that
## returns a finished graph cannot be distributed over anything. `step()` spends a
## query budget and returns whether it is done, so the caller owns the pacing and the
## same object serves both a one-shot headless bake and a live game.
##
## The pipeline is section 4's, with one documented substitution:
##
##     candidate lattice          section 12.1
##       -> clearance sample      section 5, SPARSE -- see below
##       -> clearance-priority decimation   section 12.2
##       -> swept-shape edge validation     section 13.2
##
## Section 4 puts a 0.24 m occupancy grid and a 3D distance transform between the first
## two steps. A 30 m cave is roughly two million cells and GDScript cannot walk that
## inside the budget by any route, so clearance is measured only where it is read --
## at the ~3.4k lattice points -- by bisection in NavigationProbe. Section 5.1 permits
## this explicitly: the field "does not need voxel-perfect precision because exact
## traversal feasibility will later be validated by collision shape casts". The two
## consumers that genuinely want a continuous field, medial tunnel centering (section 9)
## and local candidate ranking (section 21), are Phase 3-4 and want it locally around
## the body rather than baked over the cave.
##
## ORDER IS THE POINT OF SECTION 12.2, not an implementation detail. Sorting candidates
## by clearance DESCENDING before the greedy accept is what makes the survivors cluster
## at tunnel centres, chamber centres and large openings -- a rough medial skeleton.
## Accept them in lattice order instead and every number here is identical while the
## graph becomes an arbitrary grid sample that hugs whichever wall the scan hit first.
##
## TWO WAYS TO REACH THE CANDIDATE SET, AND THE SECOND IS THE ONE FOR REAL LEVELS.
## `begin()` walks the whole lattice, which is section 12.1 as written and is correct only
## while terrain is CONVEX. `shape_fits` and `clearance_at` are overlap tests, so a point
## deep inside a concave trimesh -- what CSG and voxel meshing both produce -- touches no
## triangle, "fits", and measures at the clearance ceiling. Those points then sort FIRST in
## section 12.2's clearance-descending order and evict genuine free-space candidates within
## `node_separation`. That is not overlay clutter; it is the sampler preferring rock.
##
## `begin_flood()` asks the other question. Instead of "is this point rock?" -- which
## NavigationProbe.is_solid cannot answer for a trimesh under Jolt, measured and pinned by
## tools/verify_navigation_csg.tscn -- it asks "is this point reachable through air?", and
## floods the lattice outward from seeds known to be open. No solidity oracle is involved,
## so it works on any collider: trimesh, voxel, convex or mixed.
##
## IT IS A CORRECTNESS FIX THAT HAPPENS TO SCALE, NOT AN OPTIMISATION. On a mostly-open
## test cave the flood costs roughly twice the sweep, because it examines each cell from up
## to six directions and the sweep examines it once. It wins where solid dominates, which
## is every real cave: a 200 m level is ~95% rock, and the sweep pays a `shape_fits` per
## cubic lattice cell of it to learn nothing.

enum Stage { IDLE, SEEDING, SAMPLING, DECIMATING, CONNECTING, DONE }

## Hard ceiling on lattice points, so a caller that passes the whole level as a region
## cannot wedge the frame budget forever. Exceeding it is REPORTED, not silently
## truncated -- a bake that quietly covered a third of the cave looks exactly like a
## bake that found a third as many routes.
const MAX_LATTICE_SAMPLES: int = 500000
## The six face directions a flood may step in.
##
## SIX, NOT TWENTY-SIX, and the reason is leakage rather than cost. A face step is exactly
## `candidate_spacing`; a corner step is 1.73 times that, so 26-connectivity reaches through
## walls 73% thicker -- 3.46 m at the shipped 2 m pitch. It buys nothing back: a region that
## is 26-connected but not 6-connected touches only at a lattice corner, which is a passage
## narrower than the lattice diagonal and one `shape_fits(squeezed_body)` rejects at both
## ends anyway. It would also cost 4.3x the passage tests.
const FLOOD_NEIGHBOURS: Array[Vector3i] = [
	Vector3i(1, 0, 0),
	Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0),
	Vector3i(0, -1, 0),
	Vector3i(0, 0, 1),
	Vector3i(0, 0, -1),
]

var graph: NavGraph = null
var stage: Stage = Stage.IDLE
## Populated by begin() when the config is unusable. Non-empty means nothing was baked.
var failures := PackedStringArray()
## True when the region needed more lattice points than MAX_LATTICE_SAMPLES.
var truncated: bool = false

var samples_taken: int = 0
var candidates_kept: int = 0
var edges_normal: int = 0
var edges_wiggle: int = 0
var pairs_rejected: int = 0
## Flood only. Seeds that landed in open space, and seeds that could not be placed at all.
var seeds_resolved: int = 0
var seeds_rejected: int = 0

var _config: NavigationConfig = null
var _probe: NavigationProbe = null
var _lattice_origin: Vector3 = Vector3.ZERO
var _counts: Vector3i = Vector3i.ZERO
var _sample_total: int = 0
var _sample_index: int = 0
## Each entry is [clearance, position].
var _candidates: Array = []
var _candidate_index: int = 0
var _node_ids: Array = []
var _connect_index: int = 0
## Undirected keys whose swept casts already failed, so the second endpoint does not
## pay for the same rejection again. Roughly halves the cast count in open terrain.
var _rejected: Dictionary = {}
## Section 24.2. Set by begin_patch: the graph is pre-existing, and only the nodes this
## run adds are worth connecting.
var _patching: bool = false
var _added_ids: Array = []
## Set by begin_flood: sample by reachability rather than by walking the lattice.
var _flooding: bool = false
## The flood's fence. Every step outside it is refused, which is the only thing standing
## between one hole in a level's hull and a bake that floods the coordinate space.
var _region: AABB = AABB()
var _seeds := PackedVector3Array()
var _seed_index: int = 0
## Cells enqueued for expansion, oldest first. Drained by index rather than popped, so a
## resumable step never pays a shift over a frontier tens of thousands long.
var _frontier: Array[Vector3i] = []
var _frontier_head: int = 0
var _neighbour_index: int = 0
## MEASUREMENT cache: cell -> clearance, or -1.0 for measured-and-not-a-candidate. Shared
## by every direction that looks at the cell, so a wall costs one `shape_fits` rather than
## one per neighbour.
var _cell_state: Dictionary = {}
## REACHABILITY record: cells the flood has accepted. Deliberately NOT the same dictionary
## as `_cell_state`. A cell whose passage test failed from the north is routinely reachable
## from the south, and one combined "visited" set writes that first refusal down as
## permanent -- a wall-shaped hole in the graph that nothing reports.
var _reached: Dictionary = {}
var _passage_body: SphereShape3D = null


## Prepares a bake over `region`. Nothing is sampled until step() is called.
func begin(region: AABB, config: NavigationConfig, probe: NavigationProbe) -> void:
	_config = config
	_probe = probe
	failures = PackedStringArray()
	truncated = false
	samples_taken = 0
	candidates_kept = 0
	edges_normal = 0
	edges_wiggle = 0
	pairs_rejected = 0
	seeds_resolved = 0
	seeds_rejected = 0
	_candidates = []
	_candidate_index = 0
	_node_ids = []
	_connect_index = 0
	_rejected = {}
	_sample_index = 0
	_patching = false
	_added_ids = []
	_flooding = false
	_region = AABB()
	_seeds = PackedVector3Array()
	_seed_index = 0
	_frontier = []
	_frontier_head = 0
	_neighbour_index = 0
	_cell_state = {}
	_reached = {}
	stage = Stage.IDLE

	if config == null:
		failures.append("no NavigationConfig")
		return
	if probe == null:
		failures.append("no NavigationProbe")
		return
	# A config that violates its own invariants bakes a graph that is wrong in ways the
	# overlay makes look deliberate. Refusing costs one frame and one log line.
	failures = config.invariant_failures()
	if not failures.is_empty():
		return
	if not probe.is_bound():
		failures.append("NavigationProbe is not bound to a World3D")
		return

	graph = NavGraph.new()
	graph.configure(
		maxf(config.node_separation, config.edge_search_radius * 0.5),
		config.chunk_size,
		config.best_seconds_per_metre()
	)
	_plan_lattice(region)
	stage = Stage.SAMPLING


## Section 24.2. Identical to `begin()`, except it adds to an existing graph.
##
## THE SAME LATTICE, THE SAME DECIMATION, THE SAME EDGE VALIDATION -- which is section
## 24.3's requirement ("runtime node creation must use approximately the same candidate
## and decimation rules as bake-time generation") satisfied by using literally the same
## code rather than approximately the same code. It is also why section 24.3's other
## instruction, "do not insert the dig centre directly", needs no guard: the only points
## this can ever insert are lattice points, and `_plan_lattice` snaps those to world-space
## multiples of `candidate_spacing`, so a patch's nodes land exactly where the original
## bake's would have.
##
## It never calls `graph.configure()`. Rebucketing a populated graph is unsupported and
## unnecessary -- the patch inherits the settings the graph was built with.
func begin_patch(
	region: AABB, config: NavigationConfig, probe: NavigationProbe, into: NavGraph
) -> void:
	begin(region, config, probe)
	_retarget(into)


## Section 12.1's candidate set, reached by REACHABILITY rather than by walking the lattice.
##
## Identical to `begin()` in every respect except which cells get sampled: the same lattice,
## the same `shape_fits`/`clearance_at` candidate test, the same section 12.2 decimation and
## the same section 13.2 edge validation. Only the enumeration differs, so a graph flooded
## and a graph swept over one connected pocket of air are the same graph -- which is the
## strongest thing tests/test_graph_flood.gd asserts.
##
## `seeds` are points the CALLER knows are in open space. They come from whatever authored
## the level: spawn markers, room centres, the brushes that carved the cave. A seed that
## lands in rock is nudged to a lattice corner and, failing that, reported.
##
## NOTHING REACHED MEANS NOTHING BAKED, LOUDLY. See `_begin_flooding`.
func begin_flood(
	region: AABB, seeds: PackedVector3Array, config: NavigationConfig, probe: NavigationProbe
) -> void:
	begin(region, config, probe)
	if not failures.is_empty():
		return
	_flooding = true
	_region = region
	_seeds = seeds
	# begin() planned a lattice this run will never walk, and `truncated` counts that
	# lattice's VOLUME. A level-sized flood region trips it on volume alone -- every bake
	# would push the "part of the region was not covered" warning while the flood visited
	# three thousand cells. Both numbers are re-earned from what is actually reached.
	truncated = false
	_sample_total = 0
	stage = Stage.SEEDING


## Section 24.2's patch, flooded. See `begin_patch` for what targeting an existing graph
## means, and `begin_flood` for what flooding means; this is exactly the two together.
func begin_patch_flood(
	region: AABB,
	seeds: PackedVector3Array,
	config: NavigationConfig,
	probe: NavigationProbe,
	into: NavGraph
) -> void:
	begin_flood(region, seeds, config, probe)
	_retarget(into)


## Spends up to `query_budget` probe queries. Returns true once the graph is complete.
func step(query_budget: int) -> bool:
	if stage == Stage.IDLE or stage == Stage.DONE:
		return stage == Stage.DONE

	var budget: int = maxi(query_budget, 1)
	var spent: int = 0
	while spent < budget and stage != Stage.DONE:
		var before: int = _probe.queries_spent
		match stage:
			Stage.SEEDING:
				_seed_one()
			Stage.SAMPLING:
				if _flooding:
					_flood_one()
				else:
					_sample_one()
			Stage.DECIMATING:
				_decimate_one()
			Stage.CONNECTING:
				_connect_one()
		# Query-free work still costs a unit. Decimation issues no queries at all, and
		# without this a 20k-candidate pass runs to completion inside one step() call
		# while truthfully reporting that it spent none of the frame budget.
		spent += maxi(_probe.queries_spent - before, 1)
	return stage == Stage.DONE


## Runs to completion. For headless bakes and tests, where frames do not exist.
func build_now() -> NavGraph:
	while stage != Stage.DONE and stage != Stage.IDLE:
		step(MAX_LATTICE_SAMPLES)
	return graph


## Rough 0..1 completion, for the overlay. Stage boundaries are not evenly spaced in
## time; this is a progress bar, not an estimate.
func progress() -> float:
	match stage:
		Stage.SEEDING:
			return 0.0
		Stage.SAMPLING:
			# A flood has no denominator: it does not know how many cells it will reach until
			# it has reached them. Frontier drain is the honest proxy, and it moves BACKWARDS
			# early on, while each expanded cell adds more than one.
			var done: float = float(_frontier_head if _flooding else _sample_index)
			var total: float = float(_frontier.size() if _flooding else _sample_total)
			return 0.6 * (done / maxf(total, 1.0))
		Stage.DECIMATING:
			return 0.6 + 0.1 * (float(_candidate_index) / maxf(float(_candidates.size()), 1.0))
		Stage.CONNECTING:
			return 0.7 + 0.3 * (float(_connect_index) / maxf(float(_node_ids.size()), 1.0))
		Stage.DONE:
			return 1.0
	return 0.0


func stats() -> Dictionary:
	return {
		"stage": stage,
		"samples_taken": samples_taken,
		"candidates_kept": candidates_kept,
		"nodes": 0 if graph == null else graph.node_count(),
		"edges_normal": edges_normal,
		"edges_wiggle": edges_wiggle,
		"pairs_rejected": pairs_rejected,
		"truncated": truncated,
		"flooding": _flooding,
		"seeds_resolved": seeds_resolved,
		"seeds_rejected": seeds_rejected,
	}


# ----- stages -----


## Lattice positions are snapped to world-space multiples of `candidate_spacing`, NOT
## to the region corner. Section 24.2 patches the graph over a small dirty region after
## mining, and a lattice anchored to whatever AABB was passed in would sample different
## points there than the original bake did -- so the patch would fight the surrounding
## graph instead of extending it.
func _plan_lattice(region: AABB) -> void:
	var spacing: float = _config.candidate_spacing
	var start := Vector3(
		ceilf(region.position.x / spacing) * spacing,
		ceilf(region.position.y / spacing) * spacing,
		ceilf(region.position.z / spacing) * spacing
	)
	var span: Vector3 = region.end - start
	_lattice_origin = start
	_counts = Vector3i(
		maxi(int(floorf(span.x / spacing)) + 1, 0),
		maxi(int(floorf(span.y / spacing)) + 1, 0),
		maxi(int(floorf(span.z / spacing)) + 1, 0)
	)
	if _counts.x <= 0 or _counts.y <= 0 or _counts.z <= 0:
		_counts = Vector3i.ZERO
		_sample_total = 0
		return
	var total: int = _counts.x * _counts.y * _counts.z
	if total > MAX_LATTICE_SAMPLES:
		truncated = true
		total = MAX_LATTICE_SAMPLES
	_sample_total = total


func _sample_one() -> void:
	if _sample_index >= _sample_total:
		_begin_decimation()
		return
	var point: Vector3 = _lattice_point(_sample_index)
	_sample_index += 1
	var profile: ClearanceProfile = _config.clearance_profile
	var clearance: float = _measure_cell(
		point, profile.squeezed_body(), profile.min_traversal_clearance()
	)
	if clearance < 0.0:
		return
	_candidates.append([clearance, point])
	candidates_kept += 1


## Clearance at `point`, or -1.0 if `body` does not fit there or `floor_clearance` is not met.
##
## SHARED BY THE SWEEP AND THE FLOOD, literally rather than approximately, so the two
## enumerations cannot drift into disagreeing about the geometry. THEY DO USE DIFFERENT
## GATES, and that separation is the whole trick -- see `_accept`.
func _measure_cell(point: Vector3, body: Shape3D, floor_clearance: float) -> float:
	samples_taken += 1
	# ONE query rejects solid rock, which is most of a cave by volume. Measuring
	# clearance first instead would spend the full bisection on every cubic metre of
	# stone, for a number that is then discarded.
	var pose := Transform3D(Basis.IDENTITY, point)
	if not _probe.shape_fits(body, pose, _config.world_mask):
		return -1.0

	var clearance: float = _probe.clearance_at(
		point, _config.world_mask, _config.clearance_ceiling, _config.clearance_steps
	)
	# Section 12.1 for the sweep; the leak threshold for the flood.
	if clearance < floor_clearance:
		return -1.0
	return clearance


## One seed per unit of budget. Resolving them eagerly in `begin_flood` would be a frame
## spike for a level that seeds one point per resident terrain block.
func _seed_one() -> void:
	if _seed_index >= _seeds.size():
		_begin_flooding()
		return
	var seed_point: Vector3 = _seeds[_seed_index]
	_seed_index += 1
	if _try_seed(_cell_of(seed_point), seed_point):
		seeds_resolved += 1
		return
	# Rounding moves a seed by up to sqrt(3)/2 of the pitch -- 1.73 m at the shipped 2.0 --
	# which is enough to put a seed taken in a 2 m bore inside its own wall. The eight
	# lattice corners of the cube containing the seed are the only cells that can be nearer
	# than one full pitch, so this is exhaustive rather than a widening search.
	var base: Vector3i = Vector3i((seed_point / _config.candidate_spacing).floor())
	for corner: int in 8:
		var cell: Vector3i = base + Vector3i(corner & 1, (corner >> 1) & 1, (corner >> 2) & 1)
		if _try_seed(cell, seed_point):
			seeds_resolved += 1
			return
	seeds_rejected += 1


## Places one seed on the lattice, or refuses it.
func _try_seed(cell: Vector3i, from_point: Vector3) -> bool:
	if _reached.has(cell):
		return true
	var at: Vector3 = _cell_position(cell)
	if not _region.has_point(at):
		return false
	var clearance: float = _clearance_of(cell, at)
	if clearance < 0.0:
		return false
	# THE SEED'S OWN PASSAGE TEST, AND IT IS NOT BELT AND BRACES. Snapping moves the seed by
	# up to 1.73 m, so a seed taken 0.9 m from a wall can resolve to a lattice cell on the FAR
	# side of it -- and the flood then starts inside the rock the seed was meant to keep it
	# out of, with nothing in the log, because that cell is perfectly open.
	#
	# ALWAYS SWEPT, with no clearance short cut, because the only point here anyone has
	# asserted is air is `from_point`. The candidate CELL's clearance is exactly the untrusted
	# number `_passage_open` refuses to read for the same reason.
	if not _probe.shape_sweep_clear(_passage_shape(), from_point, at, _config.world_mask):
		return false
	_accept(cell, at, clearance)
	return true


func _begin_flooding() -> void:
	if _frontier.is_empty():
		# REFUSED LOUDLY, rather than baking nothing. A cave with no air and a caller who
		# passed the wrong seeds produce the same empty graph, and only one of them is a
		# bug -- so the distinction has to be in `failures`, which both
		# CreatureNavigation.bake and NavGraphPatcher._start_next already push_warning over.
		var counts: Array = [_seeds.size(), seeds_rejected]
		failures.append(
			"no air seed reached open space (%d given, %d rejected); nothing was baked" % counts
		)
		stage = Stage.IDLE
		return
	_frontier_head = 0
	_neighbour_index = 0
	stage = Stage.SAMPLING


## ONE NEIGHBOUR PER UNIT OF WORK, not one frontier cell.
##
## `step()` only checks its budget between these calls, and expanding all six neighbours in
## one would cost up to 6 x (2 passage + 1 fit + 1 + clearance_steps) ~ 60 queries in a
## single indivisible lump -- a 16% overshoot on the shipped 384-query frame budget, and
## unbounded the moment anyone raises `clearance_steps`. Carrying `_neighbour_index` keeps
## the worst case at 10, the same order as one `_sample_one`.
func _flood_one() -> void:
	if _frontier_head >= _frontier.size():
		_begin_decimation()
		return
	_expand(_frontier[_frontier_head], FLOOD_NEIGHBOURS[_neighbour_index])
	_neighbour_index += 1
	if _neighbour_index >= FLOOD_NEIGHBOURS.size():
		_neighbour_index = 0
		_frontier_head += 1


func _expand(from_cell: Vector3i, step_by: Vector3i) -> void:
	var to_cell: Vector3i = from_cell + step_by
	if _reached.has(to_cell):
		return
	var to: Vector3 = _cell_position(to_cell)
	if not _region.has_point(to):
		return
	# MEASURE BEFORE SWEEPING. A wall cell then costs one `shape_fits` shared by all six of
	# its open neighbours, instead of six sphere sweeps that all report the same wall.
	var clearance: float = _clearance_of(to_cell, to)
	if clearance < 0.0:
		return
	if not _passage_open(from_cell, to_cell):
		# NOT RECORDED. A failed passage says something about this one step and nothing about
		# the cell; another direction may well succeed. See `_reached` on why writing it down
		# here is a wall-shaped hole in the graph that nothing reports.
		return
	_accept(to_cell, to, clearance)


## Whether two adjacent lattice cells are the same pocket of air.
##
## NOT WHETHER THE ALIEN FITS BETWEEN THEM. That is decided twice already -- by `_measure_cell`
## at each end and by section 13.2's swept ClearanceProfile bodies at the edge -- and moving
## it here would quietly relocate Invariant 5 into the sampler. Section 43's Scenario G needs
## chamber C, behind a 1 m slot, FULL of nodes and reachable through none of them.
func _passage_open(from_cell: Vector3i, to_cell: Vector3i) -> bool:
	# THE FREE-BALL EARLY ACCEPT, AND IT COSTS NOTHING. `clearance_at` bisects on a sphere
	# that fits with no overlap, so it UNDERSTATES the distance to the nearest solid and the
	# open ball of that radius is provably empty of terrain. A face step is exactly one pitch
	# long, so a ball reaching the neighbour proves the whole segment is air. At the shipped
	# 6 m ceiling and 2 m pitch this fires everywhere further than 2 m from a wall -- most of
	# a chamber -- leaving the sweep to be paid only in the boundary shell, where it is
	# actually deciding something.
	#
	# ONLY THE `FROM` CELL'S BALL, NEVER THE `TO` CELL'S, AND THE ASYMMETRY IS THE WHOLE
	# CORRECTNESS ARGUMENT. `from` has already been accepted, so by induction it is in the
	# same pocket of air as a seed, and a clearance measured from air is honest -- the growing
	# sphere meets the triangles that bound the air. `to` has not been validated, and on a
	# CONCAVE TRIMESH a cell inside the rock touches no triangle at all and reports the
	# clearance ceiling. Trusting that number lets a single step short-circuit straight
	# through a wall, and once one rock cell is accepted every cell around it early-accepts
	# too and the flood fills the stone. Measured, on the CSG demo cave: 16 027 of 16 335
	# lattice cells reached, 2 645 of 2 949 nodes buried.
	if float(_cell_state[from_cell]) >= _config.candidate_spacing:
		return true
	# A SWEPT SPHERE, NOT A RAY, for the reason `shape_sweep_clear`'s own docstring gives: a
	# ray is a zero-radius body, and it threads straight through the hairline seam between
	# two CSG brushes that a flood must treat as solid.
	return _probe.shape_sweep_clear(
		_passage_shape(), _cell_position(from_cell), _cell_position(to_cell), _config.world_mask
	)


## Records a cell as flooded, and offers it as a section 12.1 candidate only if it also
## clears the candidate gate.
##
## THE TWO GATES ARE DIFFERENT ON PURPOSE, AND CONFLATING THEM BREAKS SCENARIO G. A cell is
## FLOODABLE if a `flood_passage_radius` sphere fits -- the question "is this the same pocket
## of air". It is a CANDIDATE if the squeezed body fits with `min_traversal_clearance` to
## spare -- the question "could the alien stand here". The sandbox's 1 m slot has 0.5 m of
## clearance, so it is the first and not the second: the flood passes through it and leaves
## no node in it, chamber C beyond gets its nodes, and section 13.2 then refuses every edge
## across the slot. Gate the flood on candidacy instead and chamber C is never reached at
## all -- which passes the slot check for entirely the wrong reason, and
## `verify_navigation_runtime._check_chamber_c_isolated` exists to say so.
func _accept(cell: Vector3i, at: Vector3, clearance: float) -> void:
	_reached[cell] = true
	_frontier.append(cell)
	if clearance >= _config.clearance_profile.min_traversal_clearance():
		_candidates.append([clearance, at])
		candidates_kept += 1
	if _reached.size() >= MAX_LATTICE_SAMPLES:
		# Reported rather than silently truncated, exactly as `_plan_lattice` does it. Draining
		# the frontier sends the next `_flood_one` straight to decimation with what it has.
		truncated = true
		_frontier_head = _frontier.size()


func _clearance_of(cell: Vector3i, at: Vector3) -> float:
	if _cell_state.has(cell):
		return _cell_state[cell]
	var clearance: float = _measure_cell(at, _passage_shape(), _config.flood_passage_radius)
	_cell_state[cell] = clearance
	return clearance


## Reused across calls. A fresh SphereShape3D per neighbour test would allocate one resource
## per lattice step, and a level-sized flood takes hundreds of thousands of them.
func _passage_shape() -> SphereShape3D:
	if _passage_body == null:
		_passage_body = SphereShape3D.new()
	_passage_body.radius = _config.flood_passage_radius
	return _passage_body


## ABSOLUTE, not relative to the region.
##
## `_plan_lattice`'s origin is already an exact multiple of `candidate_spacing`, so absolute
## keys land on the same lattice while being independent of whatever AABB was passed in --
## which is precisely what section 24.2's patch needs, and it makes "every node sits on the
## candidate lattice" a global property rather than a per-region one.
func _cell_of(point: Vector3) -> Vector3i:
	return Vector3i((point / _config.candidate_spacing).round())


func _cell_position(cell: Vector3i) -> Vector3:
	return Vector3(cell) * _config.candidate_spacing


## begin() built a fresh graph as its last act; discard it and target the live one.
## Reusing begin() rather than duplicating its guards keeps ONE list of reasons a bake
## can refuse, so a patch cannot quietly accept a config a bake would have rejected.
func _retarget(into: NavGraph) -> void:
	if not failures.is_empty() or into == null:
		return
	graph = into
	_patching = true
	_added_ids = []


func _begin_decimation() -> void:
	# Ties broken on position, so two candidates measured at the same clearance always
	# resolve the same way. Without it the graph differs run to run and every geometric
	# assertion in the suite becomes flaky rather than wrong.
	_candidates.sort_custom(
		func(a: Array, b: Array) -> bool:
			if not is_equal_approx(a[0], b[0]):
				return a[0] > b[0]
			var left: Vector3 = a[1]
			var right: Vector3 = b[1]
			if left.x != right.x:
				return left.x < right.x
			if left.y != right.y:
				return left.y < right.y
			return left.z < right.z
	)
	_candidate_index = 0
	stage = Stage.DECIMATING


func _decimate_one() -> void:
	if _candidate_index >= _candidates.size():
		_begin_connecting()
		return
	var entry: Array = _candidates[_candidate_index]
	_candidate_index += 1
	# Tested against the LIVE graph, which is what makes section 24.3 true by construction
	# during a patch: a new node has to respect the separation of the nodes already there,
	# exactly as it would during a bake.
	if graph.has_node_within(entry[1], _config.node_separation):
		return
	_added_ids.append(graph.add_node(entry[1], entry[0]))


func _begin_connecting() -> void:
	# A patch connects ONLY what it added. Re-validating the whole cave would spend a
	# swept cast per existing pair to rediscover edges section 24.1 guarantees are still
	# valid, and would turn a local edit into a full rebake wearing a different name.
	_node_ids = _added_ids if _patching else graph.node_ids()
	_node_ids.sort()
	_connect_index = 0
	# Candidates are the bake's largest allocation and nothing reads them again. The flood's
	# three bookkeeping structures are the next largest and are equally spent -- a level-sized
	# flood holds a dictionary entry per lattice cell it touched, rock included.
	_candidates = []
	_frontier = []
	_cell_state = {}
	_reached = {}
	stage = Stage.CONNECTING


func _connect_one() -> void:
	if _connect_index >= _node_ids.size():
		stage = Stage.DONE
		return
	var id: int = _node_ids[_connect_index]
	_connect_index += 1

	var node: NavNode = graph.node_at(id)
	var nearby: PackedInt32Array = graph.find_nearby_nodes(
		node.position, _config.edge_search_radius
	)
	var linked: int = 0
	for other_id: int in nearby:
		if other_id == id:
			continue
		if linked >= _config.max_neighbors:
			break
		# An edge this node's neighbour already made still fills one of its slots.
		# Ignoring that gives well-connected nodes double the intended degree.
		if graph.edge_between(id, other_id) != null:
			linked += 1
			continue
		if _try_connect(node, graph.node_at(other_id)):
			linked += 1


## Section 13.2's classification, and the whole of Invariant 5.
func _try_connect(from: NavNode, to: NavNode) -> bool:
	var key: Vector2i = NavAStar.key_for(from.id, to.id)
	if _rejected.has(key):
		return false

	var profile: ClearanceProfile = _config.clearance_profile
	var mask: int = _config.world_mask
	var edge_type: NavEdge.Type
	if _probe.shape_sweep_clear(profile.normal_body(), from.position, to.position, mask):
		edge_type = NavEdge.Type.NORMAL_VOLUME
	elif _probe.shape_sweep_clear(profile.squeezed_body(), from.position, to.position, mask):
		edge_type = NavEdge.Type.WIGGLE
	else:
		# NO EDGE. Not a expensive edge, not a flagged one. This branch is how a
		# player-only tunnel excludes the alien (sections 10.3, 13.2, Scenario G).
		_rejected[key] = true
		pairs_rejected += 1
		return false

	var distance: float = from.position.distance_to(to.position)
	var min_clearance: float = minf(from.clearance, to.clearance)
	var travel: float = (
		_config.wiggle_travel_time(distance)
		if edge_type == NavEdge.Type.WIGGLE
		else _config.normal_travel_time(distance)
	)
	var cost: float = travel + _config.clearance_penalty(travel, min_clearance)
	graph.add_edge(NavEdge.make(from.id, to.id, edge_type, distance, min_clearance, cost))
	if edge_type == NavEdge.Type.WIGGLE:
		edges_wiggle += 1
	else:
		edges_normal += 1
	return true


func _lattice_point(index: int) -> Vector3:
	var plane: int = _counts.x * _counts.y
	var iz: int = index / plane
	var remainder: int = index % plane
	var iy: int = remainder / _counts.x
	var ix: int = remainder % _counts.x
	return _lattice_origin + Vector3(ix, iy, iz) * _config.candidate_spacing
