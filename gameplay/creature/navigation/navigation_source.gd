class_name NavigationSource
extends Node3D

This bases the navigation mesh for the leve.
It turns arbitrary terrain collision into a NavGraph.

## To use

- Place into the level

## Notes

## WHAT LIVES HERE               WHAT STAYS ON THE CREATURE
##     the probe binding             its own probe, for locomotion
##     the bake and its budget       the route, the follower, the local planner
##     the patch and its budget      the believed graph and the inspection chain
##     world_graph                   which graph it plans against
##


##
## HOW IT DECIDES WHAT IS AIR. By flooding outward from seeds, not by asking whether a point
## is rock -- see NavGraphBuilder.begin_flood. 

That question has no answer for a concave
## trimesh under Jolt (NavigationProbe.is_solid's docstring, pinned by
## tools/verify_navigation_csg.tscn), and a concave trimesh is what CSG and voxel meshing
## both produce. Reachability needs no solidity oracle, so this works on any collider the
## real level turns out to have.
##
## SO IT NEEDS SEEDS, AND THEY ARE NOT A BURDEN THE LEVEL DOES NOT ALREADY CARRY. A seed is
## any point known to be open, and every level already says where those are: player spawns,
## room markers, the brushes that carved the cave, a voxel generator's room centres. Add
## Marker3D children or fill `air_seeds`.
##
## STREAMING TERRAIN MUST NOT BE BAKED IN ONE GO, and this is the trap worth knowing before
## you meet it. An unloaded chunk has no collider, and no collider is not rock -- it is a
## VACUUM. Every cell in it measures at the clearance ceiling, the free-ball early accept in
## `_passage_open` fires unconditionally, and the flood expands through unloaded space at
## maximum speed and fills it with maximum-clearance candidates, which then sort FIRST in
## section 12.2's decimation. Instead, leave `bake_bounds` at zero and call
## `notify_terrain_changed(block_aabb)` once per chunk as it becomes resident: the graph
## grows with the streamed world, through machinery that is already additive-only
## (Invariant 6) and already frame-budgeted (`patch_queries_per_frame`).

## The bake finished. Carries the graph, so a consumer does not have to guess when to read
## it -- and a creature that attaches later must catch up by reading `world_graph`, because
## this has already fired.
signal graph_baked(graph: NavGraph)
## Section 24.2 finished a local patch. Carries what changed.
signal graph_patched(result: NavPatchResult)

@export var config: NavigationConfig = null
## Bake this region on _ready. Zero size means "wait for an explicit bake() call", which is
## what a streaming level wants -- see the class docstring.
@export var bake_bounds: AABB = AABB()
## Points the level knows are in open space. The global position of every Marker3D child is
## appended to these; see `seeds()`.
@export var air_seeds := PackedVector3Array()
## Sample by reachability rather than by walking the whole lattice.
##
## ON BY DEFAULT, because the sweep is only correct for convex colliders and no real level
## is one. Turn it off to reproduce the phase 1-2 behaviour exactly -- which is what every
## unit test and both runtime verifiers still do, by going through CreatureNavigation
## instead of through this class.
@export var use_flood: bool = true

## Section 26's authoritative terrain graph. Null until the first bake completes.
var world_graph: NavGraph = null
var probe: NavigationProbe = null
var builder: NavGraphBuilder = null
var patcher: NavGraphPatcher = null


func _init() -> void:
	# Built here rather than in _ready(), so a source created with .new() and never added to
	# a tree is fully usable -- which is what lets a headless tool bake without a scene.
	probe = NavigationProbe.new()
	builder = NavGraphBuilder.new()
	patcher = NavGraphPatcher.new()


func _ready() -> void:
	if config == null:
		config = NavigationConfig.new()
		push_warning("NavigationSource has no NavigationConfig; running on script defaults.")
	# The module's second and last get_world_3d. The first is CreatureNavigation's, and
	# verify_navigation_static.gd fails the build if a third appears.
	probe.bind(get_world_3d())
	if bake_bounds.size.length_squared() > 0.0:
		bake(bake_bounds)


func _physics_process(_delta: float) -> void:
	advance()


## One tick of the bake and the patch. Public so a test or a headless tool can drive it
## exactly, and takes no delta because nothing here is timed -- both stages spend a query
## budget rather than a duration.
func advance() -> void:
	_step_bake()
	_step_patch()


## Binds a world explicitly, for headless tools that build a tree by hand.
func bind_world(world: World3D) -> void:
	probe.bind(world)


## Every point this source will flood from: `air_seeds`, plus each Marker3D child.
##
## MARKERS BECAUSE THAT IS ALREADY HOW A LEVEL SAYS "SOMETHING GOES HERE". A designer who
## has placed a spawn point has placed an air seed, and asking them to also type its
## coordinates into an array is how the two drift apart.
func seeds() -> PackedVector3Array:
	var found := PackedVector3Array(air_seeds)
	for child: Node in get_children():
		var marker := child as Marker3D
		if marker != null and marker.is_inside_tree():
			found.append(marker.global_position)
	return found


## Starts a frame-budgeted bake over `region` (sections 12, 13, 32).
func bake(region: AABB) -> void:
	if config == null:
		config = NavigationConfig.new()
	var air: PackedVector3Array = seeds()
	patcher.use_flood = use_flood
	if use_flood:
		if air.is_empty():
			push_warning(
				(
					"NavigationSource has use_flood on and no air seeds, so nothing will be "
					+ "baked. Add Marker3D children, or fill air_seeds."
				)
			)
		builder.begin_flood(region, air, config, probe)
	else:
		builder.begin(region, config, probe)
	_warn_about_failures()


## Bakes to completion on the calling frame. For headless tools and tests, where the section
## 32 frame budget is meaningless because there are no frames. Null means it refused.
func bake_now(region: AABB) -> NavGraph:
	bake(region)
	var built: NavGraph = builder.build_now()
	if builder.stage != NavGraphBuilder.Stage.DONE:
		_warn_about_failures()
		return null
	world_graph = built
	_publish_bake()
	return world_graph


func is_baking() -> bool:
	return (
		builder.stage != NavGraphBuilder.Stage.IDLE and builder.stage != NavGraphBuilder.Stage.DONE
	)


## Section 24.2 step 1. Tell navigation that terrain inside `region` has changed.
##
## THE ONLY WAY TERRAIN CHANGE ENTERS THE MODULE, and it is a notification rather than a
## query: navigation cannot detect mining, and a module that polled for it would be
## re-measuring the whole cave forever on the chance that something moved. For a streaming
## level this is also how the graph learns that a chunk arrived.
##
## `region` MUST BE CENTRED ON THE CHANGE, and that is a contract rather than a convention.
## When a patch flood finds no existing node in the region -- which is the whole point of
## Scenario F, the player breaking into space the bake never saw -- the region's centre is
## the only seed there is, and a flood seeded in rock spreads through rock. Pass the brush's
## own bounds, not a box that merely contains them.
func notify_terrain_changed(region: AABB) -> void:
	if config == null:
		config = NavigationConfig.new()
	patcher.mark_dirty(region, config)


## Everything the section 39 overlay wants to print about the bake, in one call, so a HUD
## does not have to reach through to `builder`.
func stats() -> Dictionary:
	var report: Dictionary = builder.stats()
	report["nodes"] = 0 if world_graph == null else world_graph.node_count()
	report["patch"] = patcher.stats(world_graph)
	return report


func progress() -> float:
	return builder.progress()


# ----- internals -----


func _step_bake() -> void:
	if not is_baking():
		return
	probe.reset_query_count()
	var done: bool = builder.step(config.bake_queries_per_frame)
	if builder.stage == NavGraphBuilder.Stage.IDLE:
		# A FLOOD CAN REFUSE AFTER `bake()` HAS ALREADY RETURNED. `_begin_flooding` appends
		# its reason once every seed has been tried, which is several frames later, so
		# `bake()`'s own log has nothing to say and this is the only place it can be seen.
		_warn_about_failures()
		return
	if done:
		world_graph = builder.graph
		_publish_bake()


## One frame of section 24.2, budgeted separately from the bake.
##
## SKIPPED ENTIRELY WHILE A BAKE IS RUNNING. Both drive a NavGraphBuilder and both spend
## probe queries; letting them overlap means patching a graph that is still being built,
## which is a race with no symptom other than a cave that is subtly wrong.
func _step_patch() -> void:
	if is_baking() or world_graph == null or not patcher.has_work():
		return
	probe.reset_query_count()
	var result: NavPatchResult = patcher.step(
		world_graph, config.patch_queries_per_frame, config, probe
	)
	if result == null:
		return
	graph_patched.emit(result)


func _publish_bake() -> void:
	if builder.truncated:
		push_warning(
			(
				"Navigation bake hit the %d-cell cap; part of the region was not covered."
				% NavGraphBuilder.MAX_LATTICE_SAMPLES
			)
		)
	graph_baked.emit(world_graph)


func _warn_about_failures() -> void:
	for line: String in builder.failures:
		push_warning("NavigationSource cannot bake: %s" % line)
