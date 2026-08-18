extends "res://gameplay/creature/suspicion/tests/suspicion_test_case.gd"

## Hotspot formation, identity and movement (suspicion.md, "Suspicion Hotspots").
##
## The property that matters most here is the one nothing else can test: that a
## hotspot KEEPS ITS ID while its position, radius and suspicion are recomputed from
## scratch several times a second. Without it, `hotspot_created` fires forever and
## Behavior can never tell a new lead from a recomputation of an old one.


func test_one_noise_forms_one_hotspot_and_announces_it() -> void:
	var hotspot: SuspicionHotspot = _hotspot_from_one_noise()

	assert_not_null(hotspot)
	assert_eq(_created.size(), 1)
	assert_eq(_created[0], hotspot.id)
	assert_gt(hotspot.suspicion, 0.0)
	assert_lt(hotspot.suspicion, 1.0, "one noise is not certainty")


## Suspicion is spatial, not a meter. Two things happening in different places have to
## stay two beliefs -- the creature must not have to forget the eastern tunnel because
## the generator room just got interesting.
func test_distant_evidence_forms_separate_simultaneous_hotspots() -> void:
	_suspicion.submit_evidence(_hear(Vector3.ZERO, 0.9))
	_suspicion.submit_evidence(_hear(Vector3(40, 0, 0), 0.6))
	_settle()

	var hotspots: Array[SuspicionHotspot] = _suspicion.get_hotspots()
	assert_eq(hotspots.size(), 2)
	assert_gt(hotspots[0].suspicion, hotspots[1].suspicion, "get_hotspots is strongest-first")


func test_nearby_evidence_accumulates_into_one_stronger_hotspot() -> void:
	_suspicion.submit_evidence(_hear(Vector3.ZERO, 0.5))
	_settle()
	var alone: float = _suspicion.get_strongest_hotspot().suspicion

	_suspicion.submit_evidence(_hear(Vector3(2, 0, 0), 0.5))
	_settle()

	assert_eq(_suspicion.get_hotspots().size(), 1, "two metres apart is one place")
	assert_gt(_suspicion.get_strongest_hotspot().suspicion, alone)


func test_evidence_further_apart_than_the_merge_distance_does_not_combine() -> void:
	_config.hotspot_merge_distance = 3.0
	_suspicion.submit_evidence(_hear(Vector3.ZERO, 0.9))
	_suspicion.submit_evidence(_hear(Vector3(10, 0, 0), 0.9))
	_settle()

	assert_eq(_suspicion.get_hotspots().size(), 2)


## The whole reason hotspots are matched by shared evidence rather than rebuilt fresh.
func test_a_hotspots_id_survives_many_rebuilds() -> void:
	var first: int = _hotspot_from_one_noise().id

	_advance(2.0)

	assert_eq(_suspicion.get_strongest_hotspot().id, first)
	assert_eq(_created.size(), 1, "120 rebuilds, one creation")
	assert_gt(_updated.size(), 60, "and it reported itself updated throughout")
	assert_eq(_resolved.size(), 0)


func test_a_new_hotspot_gets_a_new_id_rather_than_reusing_a_resolved_one() -> void:
	var first: int = _hotspot_from_one_noise().id
	_advance_coarse(200.0)
	assert_eq(_resolved, [first] as Array[int])

	_suspicion.submit_evidence(_hear(Vector3(60, 0, 0), 0.9))
	_settle()

	assert_ne(_suspicion.get_strongest_hotspot().id, first)


## Suspicion.md's "hotspot shifts" diagram, literally.
func test_new_evidence_drags_a_hotspot_toward_itself_rather_than_teleporting_it() -> void:
	_suspicion.submit_evidence(_hear(Vector3.ZERO, 0.9, 2.0))
	_settle()
	var started: Vector3 = _suspicion.get_strongest_hotspot().position

	_suspicion.submit_evidence(_hear(Vector3(5, 0, 0), 0.9, 2.0))
	_settle()
	var after_one_update: Vector3 = _suspicion.get_strongest_hotspot().position

	_advance(1.0)
	var settled: Vector3 = _suspicion.get_strongest_hotspot().position

	assert_gt(after_one_update.x, started.x, "it moved")
	assert_lt(after_one_update.x, 2.4, "but not all the way to the new centroid in one update")
	assert_almost_eq(settled.x, 2.5, 0.2, "and it does arrive")


## A hotspot has to cover everywhere the evidence says the activity might have been.
## Sized to the reported positions alone, it would tell Behavior to search a point when
## what perception actually said was "somewhere in this twelve-metre sphere".
func test_a_hotspot_is_at_least_as_wide_as_the_uncertainty_that_formed_it() -> void:
	var vague: SuspicionHotspot = _hotspot_from_one_noise(Vector3.ZERO, 11.0)
	assert_almost_eq(vague.radius, 11.0, 0.5)

	before_each()
	var precise: SuspicionHotspot = _hotspot_from_one_noise(Vector3.ZERO, 1.0)
	assert_lt(precise.radius, 2.0, "a clear observation must not produce a huge search area")


func test_hotspot_radius_is_capped() -> void:
	_config.hotspot_max_radius = 5.0
	assert_eq(_hotspot_from_one_noise(Vector3.ZERO, 30.0).radius, 5.0)


func test_a_hotspot_resolves_once_its_evidence_has_decayed() -> void:
	var hotspot_id: int = _hotspot_from_one_noise().id

	_advance_coarse(60.0)

	assert_eq(_resolved, [hotspot_id] as Array[int])
	assert_null(_suspicion.get_strongest_hotspot())
	assert_eq(_suspicion.get_hotspots().size(), 0)


## A hotspot born below the resolved threshold is not news. Announcing it and then
## resolving it in the same tick is churn a listener has to filter out again.
func test_evidence_too_weak_to_be_a_hotspot_is_never_announced() -> void:
	_config.resolved_hotspot_threshold = 0.9
	_suspicion.submit_evidence(_hear(Vector3.ZERO, 0.3))
	_settle()

	assert_eq(_created.size(), 0)
	assert_eq(_resolved.size(), 0)
	assert_eq(_suspicion.get_hotspots().size(), 0)


func test_get_hotspots_above_filters_by_suspicion() -> void:
	_suspicion.submit_evidence(_hear(Vector3.ZERO, 1.0, 2.0, 1.0))
	_suspicion.submit_evidence(_hear(Vector3(40, 0, 0), 0.2, 2.0, 0.5))
	_settle()

	var strong: Array[SuspicionHotspot] = _suspicion.get_hotspots_above(0.4)
	assert_eq(_suspicion.get_hotspots().size(), 2)
	assert_eq(strong.size(), 1)
	assert_gt(strong[0].suspicion, 0.4)


## Overall suspicion is DERIVED. A separately accumulated counter would drift from the
## hotspots the moment one was searched, and the creature would stay alert about
## nowhere in particular.
func test_overall_suspicion_tracks_the_hotspots_it_is_derived_from() -> void:
	assert_eq(_suspicion.get_overall_suspicion(), 0.0)

	_suspicion.submit_evidence(_hear(Vector3.ZERO, 0.9))
	_settle()
	var one_lead: float = _suspicion.get_overall_suspicion()

	_suspicion.submit_evidence(_hear(Vector3(40, 0, 0), 0.9))
	_settle()

	assert_gt(one_lead, 0.0)
	assert_gt(_suspicion.get_overall_suspicion(), one_lead, "two leads are worse than one")
	assert_lte(_suspicion.get_overall_suspicion(), 1.0, "and it never escapes 0..1")


## Suspicion moves every single frame. Without a threshold this signal fires sixty
## times a second forever and every listener does work for a change nothing could act
## on.
func test_overall_suspicion_changed_is_not_emitted_for_imperceptible_drift() -> void:
	_hotspot_from_one_noise()
	var after_the_noise: int = _overall.size()

	_advance(2.0)

	assert_eq(after_the_noise, 1, "the noise itself is worth reporting")
	assert_lt(_overall.size(), 20, "120 ticks of slow decay is not 120 signals")


func test_the_region_resolver_keeps_evidence_on_two_sides_of_a_wall_apart() -> void:
	_config.require_same_spatial_region_for_merge = true
	# Stands in for Spatial Memory: everything with x < 0 is through the wall.
	_suspicion.region_resolver = func(position: Vector3) -> int:
		return 0 if position.x >= 0.0 else 1

	_suspicion.submit_evidence(_hear(Vector3(1, 0, 0), 0.9))
	_suspicion.submit_evidence(_hear(Vector3(-1, 0, 0), 0.9))
	_settle()

	assert_eq(_suspicion.get_hotspots().size(), 2, "two metres apart, but not the same place")


func test_without_a_resolver_the_region_rule_is_a_no_op() -> void:
	_config.require_same_spatial_region_for_merge = true

	_suspicion.submit_evidence(_hear(Vector3(1, 0, 0), 0.9))
	_suspicion.submit_evidence(_hear(Vector3(-1, 0, 0), 0.9))
	_settle()

	assert_eq(_suspicion.get_hotspots().size(), 1, "nothing supplied regions, so there is one")


## Clustering must not depend on the order things were perceived in, or the creature's
## beliefs would differ from an identical creature's for no reason anyone could debug.
func test_clustering_does_not_depend_on_arrival_order() -> void:
	var positions: Array[Vector3] = [
		Vector3.ZERO, Vector3(3, 0, 0), Vector3(5, 0, 1), Vector3(40, 0, 0)
	]
	for position: Vector3 in positions:
		_suspicion.submit_evidence(_hear(position, 0.8))
	_settle()
	var forward: int = _suspicion.get_hotspots().size()
	var forward_strongest: float = _suspicion.get_strongest_hotspot().suspicion

	before_each()
	positions.reverse()
	for position: Vector3 in positions:
		_suspicion.submit_evidence(_hear(position, 0.8))
	_settle()

	assert_eq(_suspicion.get_hotspots().size(), forward)
	assert_almost_eq(_suspicion.get_strongest_hotspot().suspicion, forward_strongest, 0.001)
