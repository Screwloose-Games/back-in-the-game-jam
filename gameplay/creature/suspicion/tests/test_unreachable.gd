extends "res://gameplay/creature/suspicion/tests/suspicion_test_case.gd"

## `mark_unreachable`: the creature could not get there, so stop offering it.
##
## THE POINT OF EVERY ASSERTION HERE IS WHAT DOES **NOT** CHANGE. This is not a
## disconfirmation and must never behave like one. A disconfirmation says "I looked and there
## was nothing", lowers the belief, and therefore lowers what every consumer sees. This says "I
## could not walk there", and the creature goes on being exactly as afraid of the place as it
## was -- which is what keeps hunt sustain and the Director's pressure model honest, and what
## makes this a legitimate third door rather than the `mark_investigation_complete()` that
## suspicion.md bans outright.
##
## So it hides the place from `get_strongest_hotspot` and `get_hotspots_above` -- the two
## queries Behavior picks somewhere to walk from -- and from nothing else.
##
## THE SUPPRESSION IS KEYED BY POSITION, NOT BY ID, and the last two cases are why. Hotspot
## identity is carried by shared contributing evidence, so a lead that decays out and re-forms
## from the next noise is a NEW id at the same spot. An id-keyed suppression would lift itself
## the moment the player made another sound -- which is precisely the loop it exists to break.

const HERE := Vector3(10.0, 0.0, 0.0)
const ELSEWHERE := Vector3(-30.0, 0.0, 0.0)


func before_each() -> void:
	super()
	# Short, so the expiry case does not have to outrun the evidence decay that would have
	# resolved the hotspot on its own and proved nothing.
	_config.unreachable_suppression_s = 5.0


func test_an_unreachable_lead_stops_being_offered() -> void:
	var hotspot: SuspicionHotspot = _hotspot_from_one_noise(HERE)

	_suspicion.mark_unreachable(hotspot.id)

	assert_null(_suspicion.get_strongest_hotspot(), "the creature was offered it again")
	assert_eq(_suspicion.get_hotspots_above(0.0), [] as Array[SuspicionHotspot])


## The half that matters. Nothing about the belief moved.
func test_it_lowers_nothing() -> void:
	var hotspot: SuspicionHotspot = _hotspot_from_one_noise(HERE)
	var before: float = _suspicion.get_overall_suspicion()
	var near_before: float = _suspicion.get_suspicion_near(HERE, 8.0)

	_suspicion.mark_unreachable(hotspot.id)

	assert_eq(_suspicion.get_overall_suspicion(), before, "overall suspicion moved")
	assert_eq(_suspicion.get_suspicion_near(HERE, 8.0), near_before, "local suspicion moved")
	assert_not_null(_suspicion.get_hotspot(hotspot.id), "the hotspot itself was dropped")
	assert_eq(_suspicion.get_hotspots().size(), 1, "the hotspot vanished from the raw list")


## It is a place, not a board. Another lead somewhere else is untouched.
func test_only_that_place_is_suppressed() -> void:
	var here: SuspicionHotspot = _hotspot_from_one_noise(HERE)
	_suspicion.submit_evidence(_hear(ELSEWHERE, 0.9))
	_settle()

	_suspicion.mark_unreachable(here.id)

	var offered: Array[SuspicionHotspot] = _suspicion.get_hotspots_above(0.0)
	assert_eq(offered.size(), 1, "the wrong number of leads survived")
	assert_almost_eq(offered[0].position.x, ELSEWHERE.x, 6.0, "the wrong lead survived")


## Bounded, because a creature that can permanently rule places out eventually rules out the
## whole level and stands still. Same reasoning as `searched_area_recovery_rate`.
func test_the_suppression_expires() -> void:
	var hotspot: SuspicionHotspot = _hotspot_from_one_noise(HERE)
	_suspicion.mark_unreachable(hotspot.id)
	assert_null(_suspicion.get_strongest_hotspot(), "the fixture never suppressed anything")

	_advance(_config.unreachable_suppression_s + 1.0)

	assert_not_null(_suspicion.get_strongest_hotspot(), "the creature never tried again")


## THE REASON IT IS POSITIONAL. Fresh noise from the same spot must not hand the lead straight
## back, however the hotspot field chooses to number it.
func test_new_noise_from_the_same_place_is_still_suppressed() -> void:
	var hotspot: SuspicionHotspot = _hotspot_from_one_noise(HERE)
	_suspicion.mark_unreachable(hotspot.id)

	_suspicion.submit_evidence(_hear(HERE, 1.0))
	_settle()

	assert_null(_suspicion.get_strongest_hotspot(), "shouting again lifted the give-up")


func test_an_unknown_id_does_nothing() -> void:
	var hotspot: SuspicionHotspot = _hotspot_from_one_noise(HERE)

	_suspicion.mark_unreachable(9999)

	assert_not_null(_suspicion.get_strongest_hotspot(), "an unknown id suppressed something")
	assert_eq(_suspicion.get_strongest_hotspot().id, hotspot.id)
