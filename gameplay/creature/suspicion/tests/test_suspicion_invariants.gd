extends "res://gameplay/creature/suspicion/tests/suspicion_test_case.gd"

## The design invariants from suspicion.md's closing section, asserted rather than
## written down.
##
## Every one of these describes a change that would make the alien work BETTER in the
## short term while destroying the model. That is exactly the kind of regression no
## behavioural test catches: the creature simply starts finding people, and nobody
## looks for the reason.


## suspicion.md: "Behavior should not call methods such as reduce_suspicion(),
## clear_hotspot(), mark_investigation_complete()." Naming them here is the only way to
## assert their absence, which is why the static verifier excludes tests/.
## `mark_unreachable` is the exception that proves it, and it is not one of these: it lowers
## nothing, and the assertions in tests/test_unreachable.gd are that every reading of the place
## survives it untouched. What it changes is which places Behavior is OFFERED as somewhere to
## walk -- a fact about the creature's legs, not about the world.
func test_belief_cannot_be_written_except_through_evidence() -> void:
	for banned: String in [
		"reduce_suspicion",
		"clear_hotspot",
		"mark_investigation_complete",
		"set_suspicion",
		"increase_suspicion",
		"set_hotspot",
		"resolve_hotspot",
	]:
		assert_false(
			_suspicion.has_method(banned),
			"%s would let Behavior declare a room searched without going there" % banned
		)


## The Director reads. It does not get to decide who the creature suspects.
func test_the_director_has_no_way_to_write_player_suspicion() -> void:
	for banned: String in ["set_player_suspicion", "set_target", "select_target", "blame"]:
		assert_false(_suspicion.has_method(banned))


## suspicion.md is emphatic that this is not an alert meter. Losing the spatial axis is
## the single most likely way this module gets simplified into uselessness.
func test_suspicion_is_spatial_rather_than_a_single_global_float() -> void:
	_suspicion.submit_evidence(_hear(Vector3.ZERO, 0.9))
	_suspicion.submit_evidence(_hear(Vector3(50, 0, 0), 0.9))
	_settle()

	assert_eq(_suspicion.get_hotspots().size(), 2)
	assert_gt(_suspicion.get_suspicion_near(Vector3.ZERO, 4.0), 0.1)
	assert_almost_eq(_suspicion.get_suspicion_near(Vector3(0, 200, 0), 4.0), 0.0, 0.001)


## Overall suspicion has no storage of its own. A separately accumulated counter would
## drift from the hotspots the moment one was searched, leaving the creature alert
## about nowhere in particular -- and no test of either half would notice.
func test_overall_suspicion_is_derived_and_not_accumulated() -> void:
	_hotspot_from_one_noise(Vector3.ZERO, 2.0)
	assert_gt(_suspicion.get_overall_suspicion(), 0.2)

	for _sweep: int in 3:
		_suspicion.submit_disconfirmation(_search(Vector3.ZERO, 6.0))
		_settle()

	assert_eq(_suspicion.get_hotspots().size(), 0)
	assert_eq(
		_suspicion.get_overall_suspicion(), 0.0, "no hotspots means nothing left to be overall"
	)


## Suspicion never inspects the world. Everything it knows arrived through the write
## API, which is what makes the alien's beliefs wrong in the ways the design intends.
func test_suspicion_never_reaches_for_the_world() -> void:
	for banned: String in [
		"get_nodes_in_group", "observe_world", "scan", "look", "raycast", "update_from_world"
	]:
		assert_false(_suspicion.has_method(banned))
	# Asked through ClassDB rather than with `is`, because `_suspicion is Node3D` is a
	# PARSE error today -- the compiler already knows the answer -- and a test that
	# cannot be compiled is not a test that passes.
	assert_false(
		ClassDB.is_parent_class(_suspicion.get_class(), "Node3D"),
		"a transform invites someone to make belief depend on where its node stands"
	)


## Perception, not Suspicion, decides what a sense reports. If a config knob here could
## change what arrives, the two modules would no longer be separable.
func test_the_write_api_is_the_only_way_in() -> void:
	var writes: Array[String] = [
		"submit_evidence", "submit_evidence_batch", "submit_disconfirmation"
	]
	for method: String in writes:
		assert_true(_suspicion.has_method(method))

	# get_script_method_list(), NOT get_method_list(): the latter includes every method
	# Node ever declared, so the sweep would trip on add_child and set_name and say
	# nothing at all about this class.
	#
	# Two named exceptions, and they are named here rather than being allowed to blend in
	# with the reads. `reset` exists for the sandbox and for tests. `mark_unreachable` writes
	# no belief at all -- it says the creature could not GET somewhere, which hides the place
	# from the two lead queries and leaves every number describing it exactly as it was.
	#
	# `mark_` is swept for the same reason `set_` is: it is the prefix the next attempt at
	# mark_investigation_complete() would arrive under, and that one is a fourth door.
	var allowed: Array[String] = ["reset", "mark_unreachable"]
	var suspicious_writers: Array[String] = []
	for entry: Dictionary in _suspicion.get_script().get_script_method_list():
		var method: String = entry["name"]
		if method.begins_with("_") or writes.has(method) or allowed.has(method):
			continue
		for prefix: String in ["set_", "add_", "apply_", "mark_"]:
			if method.begins_with(prefix):
				suspicious_writers.append(method)
				break
	assert_eq(suspicious_writers, [] as Array[String], "belief has exactly three doors")


## Time only enters through advance(). A wall clock would keep belief decaying in a
## paused game and could not be driven from any test.
func test_the_module_has_exactly_one_clock_and_it_is_driven_by_delta() -> void:
	assert_eq(_suspicion.clock, 0.0)
	_suspicion.advance(3.0)
	assert_eq(_suspicion.clock, 3.0, "exactly the delta it was handed, not elapsed real time")
	assert_lt(_suspicion.clock, 1000.0, "seconds since spawn, not milliseconds since boot")


## Behavior interprets suspicion; it does not own it. Nothing here may look like a
## state machine hint.
func test_suspicion_expresses_no_opinion_about_what_to_do() -> void:
	for banned: String in [
		"should_investigate", "should_hunt", "get_state", "transition", "get_next_action"
	]:
		assert_false(_suspicion.has_method(banned))


func test_reset_forgets_everything_including_the_signal_baseline() -> void:
	_hotspot_from_one_noise()
	_suspicion.submit_evidence(_see(Vector3.ZERO, _player("Player1")))
	_settle()
	assert_gt(_suspicion.get_overall_suspicion(), 0.0)

	_suspicion.reset()
	_settle()

	assert_eq(_suspicion.get_overall_suspicion(), 0.0)
	assert_eq(_suspicion.get_hotspots().size(), 0)
	assert_null(_suspicion.get_best_player_candidate())
	assert_eq(_suspicion.memory.records.size(), 0)


## The overlay reads this every frame, and it must never become a cache or a history --
## that is how a module that is supposed to be stateless grows memory by accident.
func test_debug_state_reports_the_live_model_without_storing_anything() -> void:
	_hotspot_from_one_noise()
	var state: Dictionary = _suspicion.debug_state()

	assert_eq(int(state["evidence"]), 1)
	assert_eq((state["hotspots"] as Array).size(), 1)
	assert_almost_eq(float(state["overall"]), _suspicion.get_overall_suspicion(), 0.0001)
	assert_almost_eq(float(state["clock"]), _suspicion.clock, 0.0001)
