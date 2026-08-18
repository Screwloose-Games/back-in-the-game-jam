class_name NavigationConfig
extends Resource

## Every tunable in the navigation module, in one Resource.
##
## Section 4 is explicit that the resolutions are tuning values and "must not be
## hard-coded into algorithms". Nothing outside this file may contain a navigation
## number -- if a spacing, a speed or a radius appears in the builder, the planner or
## the follower, that is a bug even when the value is right, because the sandbox can
## no longer contradict it.
##
## A bare `NavigationConfig.new()` is fully usable, including the one Resource-typed
## field, so tests and a freshly dropped CreatureNavigation both run without a .tres.
##
## THE COSTS ARE IN SECONDS, NOT METRES (section 14). Traversal time plus penalties is
## the whole cost model, and it is what lets a 3 m squeeze lose to a 12 m detour
## without a special case. Anything that mixes a distance into these fields without
## dividing by a speed silently makes the units meaningless, and A* still returns a
## path -- just not the cheapest one.

## Which physics layers count as world geometry. Defaults to bit 1 ("hull" in
## project.godot).
##
## A mask of 0 does not error. Every shape cast then reports clear, every candidate
## reports infinite clearance, and the graph connects every node to every neighbour
## through solid rock -- an alien that fits everywhere, with nothing in the log.
## Asserted in invariant_failures().
const DEFAULT_WORLD_MASK: int = 1

@export_flags_3d_physics var world_mask: int = DEFAULT_WORLD_MASK
## The alien's two collision envelopes. Never null -- see ClearanceProfile.
@export var clearance_profile: ClearanceProfile = ClearanceProfile.new()
## Everything the four locomotion modes steer by. Never null -- see LocomotionProfile.
##
## Split out for the same reason the clearance envelopes were: phases 3-6 add more
## tunables than phases 1-2 held in total, and one Resource containing both the bake
## lattice and the crawl steering weights is a file nobody can navigate.
@export var locomotion_profile: LocomotionProfile = LocomotionProfile.new()

@export_group("Graph generation")
## Section 12.1 candidate lattice pitch.
@export_range(0.25, 10.0, 0.05, "or_greater", "suffix:m") var candidate_spacing: float = 2.0
## Section 12.2 decimation radius. A candidate within this of an accepted node is
## dropped, which is what turns the lattice into a rough medial skeleton.
@export_range(0.25, 20.0, 0.05, "or_greater", "suffix:m") var node_separation: float = 3.0
## Section 13.1 neighbour search radius.
@export_range(1.0, 40.0, 0.1, "or_greater", "suffix:m") var edge_search_radius: float = 8.0
## How many neighbours a node may link to (section 13.1).
##
## TWELVE, NOT THE SPEC'S SIX, and the difference is measured rather than guessed.
## Section 13.1 offers six as "a simple initial implementation" and insists the count
## stay configurable; in the sandbox cave six is not enough. The node at the mouth of
## the 6 m tunnel has ten neighbours nearer than the node 6 m straight down it, so
## nearest-first selection spends the whole budget before reaching the one edge that
## carries the chamber-to-chamber connection at normal body size. The route survives by
## detouring through a low-clearance corner and squeezing twice, through a tunnel the
## alien fits down comfortably:
##
##     max_neighbors    6      8     10     12     16     24
##     route cost   15.87  14.82  14.82   3.82   3.82   3.82   seconds
##     bake             18     18     19     19     23     28   ms
##
## Twelve is where the cost settles, and it costs about a millisecond. Section 13.1's
## own suggested remedy -- directional coverage instead of raw distance -- was tried
## and made no difference here: all eleven candidates already lie in distinct
## directions, so there is nothing for a sector filter to deduplicate. It is still the
## right answer for denser graphs than this one.
@export_range(1, 32, 1) var max_neighbors: int = 12
## Largest clearance the probe bothers to measure.
##
## Clearance has no natural ceiling in a 30 m chamber, and measuring it exactly there
## costs queries to distinguish 14 m of free space from 15 m -- a distinction nothing
## downstream uses. Everything past this reports as this.
@export_range(1.0, 30.0, 0.1, "or_greater", "suffix:m") var clearance_ceiling: float = 6.0
## Binary-search iterations per clearance sample. Each one halves the error, so 6 steps
## resolve a 6 m ceiling to about 9 cm -- far finer than the 0.24 m section 4 asks of
## the field it replaces.
@export_range(1, 12, 1) var clearance_steps: int = 6
## Nav chunk edge length, for section 25 chunk ids and the debug overlay. Independent
## of terrain chunk size on purpose.
@export_range(1.0, 64.0, 1.0, "or_greater", "suffix:m") var chunk_size: float = 16.0
## Radius of the probe swept between adjacent lattice cells during a FLOOD bake
## (NavGraphBuilder.begin_flood). Unused by the section 12.1 lattice sweep.
##
## THIS NUMBER IS THE LEAK THRESHOLD AND NOTHING ELSE. It is emphatically not a body size.
## Whether the alien fits is decided later and twice over -- by `shape_fits` at the cell and
## by the swept ClearanceProfile bodies at the edge -- and this only answers "are these two
## cells the same pocket of air".
##
## SO IT MUST BE SMALL ENOUGH TO FOLLOW AIR THE ALIEN CANNOT USE, which is the opposite of
## the intuition. The sandbox's 1 m slot is the calibration case: section 43's Scenario G
## needs chamber C beyond it FULL of nodes and unreachable through every one of them, and
## `verify_navigation_runtime._check_chamber_c_isolated` fails outright on a chamber C with
## no nodes -- "the slot check above proves nothing". Invariant 5 is a property of edge
## validation, and a flood sized like a body would quietly move it into the sampler.
##
## Large enough, meanwhile, that a hairline seam between two CSG brushes is not a passage.
## At 0.25 the probe needs 0.5 m of clearance: it crosses the 1 m slot and nothing thinner.
@export_range(0.05, 4.0, 0.05, "or_greater", "suffix:m") var flood_passage_radius: float = 0.25

@export_group("Traversal cost")
## Expected speed over a NORMAL_VOLUME edge, whether crawled or swum. Section 14 leaves
## that choice to the local planner, so the global cost cannot distinguish them.
@export_range(0.1, 30.0, 0.1, "or_greater", "suffix:m/s") var normal_speed: float = 6.0
## Section 10.2: wiggle is "substantially slower".
@export_range(0.05, 30.0, 0.05, "or_greater", "suffix:m/s") var wiggle_speed: float = 1.2
## Flat cost of compressing and decompressing, paid once per WIGGLE edge.
@export_range(0.0, 30.0, 0.1, "suffix:s") var squeeze_transition_penalty: float = 2.0
## Clearance comfort term, as a fraction of the edge's traversal time.
##
## Section 14: clearance "can contribute a moderate comfort/caution penalty but should
## not dominate the entire system". Above ~1.0 it does dominate, and the alien starts
## preferring a long trip down the middle of a chamber to a short one along a wall for
## reasons no player can read. invariant_failures() caps it.
@export_range(0.0, 1.0, 0.01) var clearance_penalty_weight: float = 0.15
## Clearance at or above which an edge carries no comfort penalty at all.
@export_range(0.1, 20.0, 0.1, "or_greater", "suffix:m") var comfortable_clearance: float = 2.5

@export_group("Endpoint attachment")
## Section 16: how many nearby nodes to shape-cast against before giving up. One is
## the bug section 16 exists to prevent -- the nearest node is routinely through a wall.
@export_range(1, 32, 1) var endpoint_candidate_count: int = 6
@export_range(1.0, 60.0, 0.5, "or_greater", "suffix:m") var endpoint_search_radius: float = 12.0

@export_group("Route following")
## Section 19: how many anchors ahead smoothing may look when collapsing a route.
@export_range(1, 16, 1) var smoothing_lookahead: int = 4
## How close the body must get before an anchor counts as reached.
@export_range(0.1, 10.0, 0.1, "or_greater", "suffix:m") var waypoint_arrival_distance: float = 1.5
## Points sampled along a candidate shortcut when checking it for surface continuity.
##
## FIXED, NOT PER METRE, so the cost of smoothing cannot grow with the length of the
## shortcut being considered. Four samples times `crawl_surface_ray_count` rays is the
## whole price of one section 19 surface-crawl check.
@export_range(2, 16, 1) var smoothing_surface_samples: int = 4

@export_group("Terrain updates")
## Section 32 budget for section 24.2's local patching, per physics frame.
##
## Smaller than the bake's budget on purpose. A bake happens once with nothing else
## running; a patch happens mid-chase, while the alien is also crawling and the player is
## still mining.
@export_range(16, 4096, 16, "or_greater") var patch_queries_per_frame: int = 128
## Re-test WIGGLE edges in a patched region with the normal body, and upgrade the ones
## that now fit.
##
## UPGRADE ONLY, NEVER DOWNGRADE, which is what keeps Invariant 6 true by construction
## rather than by care. Mining is subtractive, so a passage can only ever get easier.
## Without this a widened crevice stays priced as a squeeze forever and Scenario F adds
## nodes without improving a single route.
@export var upgrade_edges_on_patch: bool = true
## Re-sample clearance for existing nodes in a patched region. Clearance only ranks and
## adds a comfort penalty -- it never gates -- so this changes costs, not connectivity.
@export var refresh_clearance_on_patch: bool = true

@export_group("Knowledge")
## Whether the alien starts out believing the whole baked graph (section 27).
##
## TRUE IS THE HONEST DEFAULT FOR A RESIDENT CREATURE. An alien that has lived in this
## cave knows its shape; what it does not know is what the player has changed since. Set
## false for something that has just arrived and must explore.
@export var knowledge_starts_known: bool = true
## How fast belief moves toward an observation's own confidence, per observation.
@export_range(0.0, 1.0, 0.01) var knowledge_learn_rate: float = 0.5
## Confidence multiplier applied when an observation contradicts what was believed.
@export_range(0.0, 1.0, 0.01) var knowledge_contradiction_penalty: float = 0.5
## Confidence at or below which a memory is treated as STALE rather than KNOWN.
@export_range(0.0, 1.0, 0.01) var knowledge_stale_confidence: float = 0.35
## Confidence lost per second of not observing something. Deliberately tiny: terrain does
## not move, so memory of it should decay far more slowly than memory of a player.
@export_range(0.0, 1.0, 0.0001) var knowledge_decay_per_second: float = 0.002
## What a STALE edge costs, relative to its remembered cost.
##
## PROJECTED RATHER THAN DROPPED, and that is a behaviour decision. An alien that refuses
## every doubted route stands still in a cave it has half-forgotten; one that prefers
## certainty but will still try a doubted way reads as an animal. Section 43's Scenario J
## is this number.
@export_range(1.0, 20.0, 0.1, "or_greater") var stale_edge_cost_multiplier: float = 2.5

@export_group("Inspection")
## Section 29's beat between noticing a mismatch and starting to inspect it -- the moment
## the alien stops and orients. Zero here is an alien that absorbs new terrain mid-stride,
## which is exactly what section 29 exists to prevent.
@export_range(0.0, 5.0, 0.05, "suffix:s") var mismatch_pause_time: float = 0.4
## How long an inspection may run before completing itself.
##
## LOAD-BEARING. Section 30 hands the inspection to the behaviour system, which decides
## how it looks and calls back when done. A project with no behaviour system yet -- which
## is every project today -- would otherwise wedge in INSPECTING forever.
@export_range(0.1, 60.0, 0.1, "or_greater", "suffix:s") var inspection_timeout: float = 4.0
## Section 29's RELEARNING beat. Knowledge is applied at the END of it, not on entry:
## that single ordering choice is the whole of "delayed knowledge acquisition".
@export_range(0.0, 10.0, 0.05, "suffix:s") var relearn_time: float = 0.5
## How much of the world graph a completed inspection may copy into knowledge as KNOWN.
@export_range(0.5, 40.0, 0.5, "or_greater", "suffix:m") var relearn_radius: float = 6.0
## How far the same inspection may follow CONNECTED unknown geometry outward from there.
##
## THE ANSWER TO STOPPING SEVEN TIMES IN ONE TUNNEL. `relearn_radius` alone learns a ball,
## so a 20 m passage is discovered a sixth at a time and the alien stops for each sixth --
## which reads as a creature that cannot remember what it looked at ten seconds ago. What
## it learns out here is PARTIALLY_EXPLORED, not KNOWN: it saw down the passage, it did
## not walk it.
@export_range(1.0, 200.0, 1.0, "or_greater", "suffix:m") var relearn_connected_radius: float = 24.0
## Ceiling on how many nodes one connected relearn may learn.
##
## A BUDGET, NOT A BEHAVIOUR KNOB. Mining into an unexplored cave system can put a
## cave-sized component one edge away, and section 32 gives the whole of navigation 10 ms.
## Hitting this sets `NavKnowledgeUpdate.truncated` and costs a second inspection further
## in, which is the right failure.
@export_range(1, 4096, 1, "or_greater") var relearn_max_nodes: int = 512
## Requests within this of the last accepted one are dropped.
##
## NOT AN OPTIMISATION. Without dedupe a route that cannot reach its goal raises a
## STALE_ROUTE request on every replan -- twice a second, forever, at the same spot.
@export_range(0.0, 20.0, 0.1, "or_greater", "suffix:m") var inspection_dedupe_radius: float = 4.0
@export_range(0.0, 60.0, 0.1, "or_greater", "suffix:s") var inspection_dedupe_time: float = 6.0

@export_group("Route selection")
## How many plausible routes section 35 compares before choosing.
@export_range(1, 8, 1) var route_alternatives: int = 3
## How much worse than the best a route may be and still be eligible.
##
## Section 35's worked example is 31 / 34 / 38 / 67: the first three are all reasonable
## and the fourth should essentially never be chosen. At 0.25, D is 2.2x the best and is
## not eligible at all, which is a cleaner statement than giving it a tiny weight.
@export_range(0.0, 2.0, 0.01) var route_tolerance: float = 0.25
## Section 35's intelligence dial. High concentrates the choice on the best eligible
## route; low spreads it. This is where "higher intelligence narrows selection" lives.
@export_range(0.0, 40.0, 0.5, "or_greater") var route_selection_sharpness: float = 6.0
## Seed for route selection. Fixed rather than randomised, because a route that differs
## between two runs of the same scenario is a bug nobody can reproduce.
@export var route_seed: int = 0

@export_group("Replanning")
## Section 31 pursuit timer.
@export_range(0.05, 10.0, 0.05, "suffix:s") var pursuit_interval: float = 0.5
## Section 31: how far the target must move before the route is reconsidered.
@export_range(0.1, 20.0, 0.1, "or_greater", "suffix:m") var target_move_threshold: float = 2.0

@export_group("Local failure")
## Window over which the body's displacement is measured before it counts as wedged.
##
## THE BACKSTOP FOR EVERY FAILURE NOBODY HAS THOUGHT OF YET. Section 40 enumerates six
## local failures and each has its own detector; between them they have twice shipped an
## alien that held a COMPLETE route, reported a plausible mode, and did not move again for
## the rest of the run -- once wedged against a ceiling inside its own planning envelope,
## once floating in open space with every ray missing. Both were invisible to every layer,
## because "moved nowhere" was not a thing anything measured.
##
## Long enough to outlast the legitimate stops: a squeeze transition is 0.6 s, an
## inspection's pause and relearn together are 0.9 s, and a deliberate hold-still is
## excluded outright rather than waited out.
@export_range(0.2, 30.0, 0.1, "suffix:s") var progress_window: float = 2.0
## Metres the body must cover within `progress_window` to count as making progress.
##
## Above the slowest mode's noise and far below its speed. A wiggle at 1.2 m/s covers
## 2.4 m in the window, so this is a fifth of the slowest thing the alien legitimately
## does -- generous enough that grinding forward slowly never trips it.
@export_range(0.0, 20.0, 0.05, "or_greater", "suffix:m") var progress_threshold: float = 0.5

@export_group("Compute budget")
## Section 32: probe queries the bake may spend per physics frame.
##
## The bake is the only thing in the module expensive enough to need this. A* over a
## graph this size is microseconds (section 15), so it runs synchronously.
@export_range(16, 8192, 16, "or_greater") var bake_queries_per_frame: int = 384
## How far `NavigationProbe.is_solid` casts looking for its first face.
##
## Must exceed the thickest wall anything will ever ask about, or a point in the middle of
## a very deep mass reports open because the ray ran out before reaching a surface.
@export_range(1.0, 1024.0, 1.0, "or_greater", "suffix:m") var solidity_probe_distance: float = 128.0


## Traversal time for a distance at the mode's speed, before penalties (section 14).
func normal_travel_time(distance: float) -> float:
	return distance / normal_speed


func wiggle_travel_time(distance: float) -> float:
	return distance / wiggle_speed + squeeze_transition_penalty


## The section 14 comfort term. Zero at or above `comfortable_clearance`, rising to
## `clearance_penalty_weight` of the edge's travel time as clearance approaches nothing.
func clearance_penalty(travel_time: float, min_clearance: float) -> float:
	if clearance_penalty_weight <= 0.0 or comfortable_clearance <= 0.0:
		return 0.0
	var discomfort: float = clampf(1.0 - min_clearance / comfortable_clearance, 0.0, 1.0)
	return travel_time * clearance_penalty_weight * discomfort


## The cheapest possible seconds-per-metre, for the A* heuristic.
##
## MUST BE THE FASTEST SPEED IN THE MODEL, not the typical one. A* is admissible only
## while the heuristic never overestimates remaining cost; using a slower speed makes
## it overestimate and quietly returns suboptimal routes with no error anywhere.
func best_seconds_per_metre() -> float:
	return 1.0 / maxf(normal_speed, wiggle_speed)


## Section 43's Scenario D and Scenario E, as arithmetic.
##
## THE MOST USEFUL FOUR LINES IN THIS FILE. Section 11.4 asks that a leap become
## attractive at "approximately 10 m" of crawling saved, and leaves the tuning to us --
## which means the only thing standing between `leap_bias` and an alien that leaps across
## every room is somebody's memory. Section 43 already wrote the two cases down:
##
##     Scenario D   crawl 30 m, leap 20 m   -> leap
##     Scenario E   crawl 21 m, leap 18 m   -> crawl
##
## `verify_navigation_static.gd` runs this on a default config, so getting the tuning
## wrong fails the build with the scenario named, rather than producing an alien that is
## merely a bit too keen and passes every test.
func _leap_scenario_failures() -> PackedStringArray:
	var failures := PackedStringArray()
	var leaps_far: float = locomotion_profile.leap_travel_time(20.0)
	var crawls_far: float = normal_travel_time(30.0)
	if leaps_far >= crawls_far:
		var far: Array = [leaps_far, crawls_far]
		failures.append(
			(
				"Scenario D: a 20 m leap costs %.2fs and a 30 m crawl %.2fs, so the alien " % far
				+ "would crawl a route section 43 expects it to leap; lower leap_bias"
			)
		)
	var leaps_near: float = locomotion_profile.leap_travel_time(18.0)
	var crawls_near: float = normal_travel_time(21.0)
	if leaps_near <= crawls_near:
		var near: Array = [leaps_near, crawls_near]
		failures.append(
			(
				"Scenario E: an 18 m leap costs %.2fs and a 21 m crawl %.2fs, so the alien " % near
				+ "would leap a route section 43 expects it to crawl; raise leap_bias"
			)
		)
	return failures


func invariant_failures() -> PackedStringArray:
	var failures := PackedStringArray()
	if world_mask == 0:
		failures.append("world_mask is 0; every shape cast would report clear space")
	if locomotion_profile == null:
		failures.append("locomotion_profile is null")
	else:
		for line: String in locomotion_profile.invariant_failures():
			failures.append("locomotion_profile: " + line)
		for line: String in _leap_scenario_failures():
			failures.append(line)
		if locomotion_profile.crawl_max_speed > normal_speed:
			# Routing charges normal_speed for the edge and the body cannot deliver it, so
			# every route is chosen against a travel time that never happens.
			var crawl: Array = [locomotion_profile.crawl_max_speed, normal_speed]
			failures.append("crawl_max_speed %.2f exceeds routing normal_speed %.2f" % crawl)
		if locomotion_profile.tunnel_max_speed > normal_speed:
			var swim: Array = [locomotion_profile.tunnel_max_speed, normal_speed]
			failures.append("tunnel_max_speed %.2f exceeds routing normal_speed %.2f" % swim)
		if squeeze_transition_penalty < 2.0 * locomotion_profile.squeeze_transition_time:
			# The penalty is paid once per WIGGLE edge and the transition happens twice --
			# in and out -- so routing must charge for both or squeezes look cheap.
			var squeeze: Array = [
				squeeze_transition_penalty, locomotion_profile.squeeze_transition_time
			]
			failures.append(
				"squeeze_transition_penalty %.2fs does not cover two %.2fs transitions" % squeeze
			)
	if clearance_profile == null:
		failures.append("clearance_profile is null")
	else:
		for line: String in clearance_profile.invariant_failures():
			failures.append("clearance_profile: " + line)
		if (
			locomotion_profile != null
			and locomotion_profile.avoidance != null
			and locomotion_profile.avoidance.hold_distance < clearance_profile.normal_clearance()
		):
			# THE LOWER HALF OF THE ADHESION BOUND, and it lives here because this is the
			# only class that sees both resources. A crawler told to hold closer than the
			# shape every swept cast is made with pulls the body inside its own planning
			# envelope; from there the origin-overlap test fails, every candidate in every
			# mode is rejected, and the alien never moves again. That is not hypothetical --
			# it is the freeze documented in creature_nav_demo_creature.gd, arrived at by a
			# collider 0.15 m too small rather than by a knob, but the same pose either way.
			var hold: Array = [
				locomotion_profile.avoidance.hold_distance, clearance_profile.normal_clearance()
			]
			failures.append("avoidance.hold_distance %.2f is inside the body envelope %.2f" % hold)
		if flood_passage_radius > clearance_profile.min_traversal_clearance():
			# A flood tighter than the candidate gate cannot reach every candidate it is
			# supposed to enumerate: the sampler would refuse to step through a gap the alien
			# is allowed to stand in, and the graph loses whatever is beyond it. The flood
			# must always be the more permissive of the two.
			var gates: Array = [flood_passage_radius, clearance_profile.min_traversal_clearance()]
			failures.append(
				"flood_passage_radius %.2f exceeds min_traversal_clearance %.2f" % gates
			)
		if clearance_ceiling < clearance_profile.normal_clearance():
			# Every node then measures tighter than the normal body and the whole graph
			# reads as wiggle-only.
			var caps: Array = [clearance_ceiling, clearance_profile.normal_clearance()]
			failures.append("clearance_ceiling %.2f is below normal body clearance %.2f" % caps)
	if candidate_spacing <= 0.0:
		failures.append("candidate_spacing must be positive")
	if node_separation < candidate_spacing:
		# Decimation would then reject nothing and accept the entire lattice.
		var pitches: Array = [node_separation, candidate_spacing]
		failures.append("node_separation %.2f is below candidate_spacing %.2f" % pitches)
	if edge_search_radius <= node_separation:
		# No accepted node can be within the search radius of another, so no edges.
		var radii: Array = [edge_search_radius, node_separation]
		failures.append("edge_search_radius %.2f does not exceed node_separation %.2f" % radii)
	if flood_passage_radius <= 0.0:
		failures.append("flood_passage_radius must be positive; a zero-radius probe is a ray")
	if flood_passage_radius * 2.0 >= candidate_spacing:
		# A probe wider than the lattice pitch cannot fit between two adjacent cells even in
		# open space, so the flood refuses every step and bakes the seed cells alone -- a
		# three-node graph that looks like a broken builder rather than a bad number.
		var probes: Array = [flood_passage_radius, candidate_spacing]
		failures.append(
			"flood_passage_radius %.2f is not below half of candidate_spacing %.2f" % probes
		)
	if max_neighbors < 1:
		failures.append("max_neighbors must be at least 1")
	if clearance_steps < 1:
		failures.append("clearance_steps must be at least 1")
	if chunk_size <= 0.0:
		failures.append("chunk_size must be positive")
	if normal_speed <= 0.0:
		failures.append("normal_speed must be positive")
	if wiggle_speed <= 0.0:
		failures.append("wiggle_speed must be positive")
	if wiggle_speed >= normal_speed:
		# Section 10.2 requires wiggle to be substantially slower.
		var speeds: Array = [wiggle_speed, normal_speed]
		failures.append("wiggle_speed %.2f is not slower than normal_speed %.2f" % speeds)
	if squeeze_transition_penalty < 0.0:
		failures.append("squeeze_transition_penalty must not be negative")
	if clearance_penalty_weight < 0.0 or clearance_penalty_weight > 1.0:
		failures.append("clearance_penalty_weight must be within 0..1 so it cannot dominate cost")
	if comfortable_clearance <= 0.0:
		failures.append("comfortable_clearance must be positive")
	if endpoint_candidate_count < 1:
		failures.append("endpoint_candidate_count must be at least 1")
	if endpoint_search_radius <= 0.0:
		failures.append("endpoint_search_radius must be positive")
	if smoothing_lookahead < 1:
		failures.append("smoothing_lookahead must be at least 1")
	if waypoint_arrival_distance <= 0.0:
		failures.append("waypoint_arrival_distance must be positive")
	if pursuit_interval <= 0.0:
		failures.append("pursuit_interval must be positive")
	if target_move_threshold <= 0.0:
		failures.append("target_move_threshold must be positive")
	if progress_window <= 0.0:
		failures.append("progress_window must be positive")
	if progress_threshold < 0.0:
		failures.append("progress_threshold must not be negative")
	if locomotion_profile != null and progress_window <= locomotion_profile.squeeze_transition_time:
		# A squeeze legitimately holds the body still for its whole transition. A window
		# shorter than that calls every squeeze a wedge.
		var beats: Array = [progress_window, locomotion_profile.squeeze_transition_time]
		failures.append("progress_window %.2fs does not outlast a %.2fs squeeze" % beats)
	if bake_queries_per_frame < 1:
		failures.append("bake_queries_per_frame must be at least 1")
	if smoothing_surface_samples < 2:
		failures.append("smoothing_surface_samples must be at least 2")
	if solidity_probe_distance <= 0.0:
		failures.append("solidity_probe_distance must be positive")
	if patch_queries_per_frame < 1:
		failures.append("patch_queries_per_frame must be at least 1")
	if knowledge_stale_confidence < 0.0 or knowledge_stale_confidence > 1.0:
		failures.append("knowledge_stale_confidence must be within 0..1")
	if stale_edge_cost_multiplier < 1.0:
		# Below 1 a doubted route becomes CHEAPER than a certain one.
		failures.append("stale_edge_cost_multiplier must be at least 1")
	if inspection_timeout <= mismatch_pause_time + relearn_time:
		# The timeout has to outlast the states it is a backstop for, or an inspection
		# times out before it has begun and nothing is ever learned.
		var beats: Array = [inspection_timeout, mismatch_pause_time + relearn_time]
		failures.append("inspection_timeout %.2fs does not exceed its own beats %.2fs" % beats)
	if relearn_radius <= 0.0:
		failures.append("relearn_radius must be positive")
	if relearn_connected_radius < relearn_radius:
		# The flood starts from the seed ball, so a reach shorter than the ball is a bound
		# that can only ever cut off geometry the inspection already learned.
		var reaches: Array = [relearn_connected_radius, relearn_radius]
		failures.append("relearn_connected_radius %.2f is below relearn_radius %.2f" % reaches)
	if relearn_max_nodes < 1:
		failures.append("relearn_max_nodes must be at least 1")
	if route_alternatives < 1:
		failures.append("route_alternatives must be at least 1")
	if route_tolerance < 0.0:
		failures.append("route_tolerance must not be negative")
	return failures
