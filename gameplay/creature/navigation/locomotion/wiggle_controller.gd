class_name WiggleController
extends RefCounted

## Compresses the body and works it through a passage the normal body does not fit
## (navigation.md sections 10, 40.2).
##
## DECIDED FROM LOCAL SHAPES, NOT FROM THE ROUTE. Section 10.1 defines wiggle by fit --
## normal shape does not, squeezed shape does -- and asking the geometry rather than the
## edge type is what makes this work in a passage the graph has never heard of, which is
## every passage the player mined since the last patch.
##
## THE SQUEEZE IS A TIMED STATE, NOT A FLAG, and the timing is load-bearing rather than
## decorative. `NavigationConfig.squeeze_transition_penalty` charges A* a flat 2 s for
## every WIGGLE edge; if the body could compress instantly, routing would be paying for
## something that never happens and squeezes would be systematically overpriced. The
## config asserts the penalty covers two transitions, in and out, because both are real.
##
## SECTION 10.3 IS A HARD LIMIT WITH NO SPECIAL CASE. If the squeezed shape does not fit,
## the answer is NO_FIT and there is no smaller body to try. That single fact is the whole
## of Invariant 5: a player-only tunnel needs no flag, no layer and no marker, because it
## is simply a passage narrower than the alien's compressed diameter.
##
## SECTION 40.2 IS THE OTHER HALF OF THAT. A passage the squeezed body fits by a hair is
## one the alien can enter and then fail to make progress in, and "do not merely push
## against collision indefinitely" is the spec's own instruction. Grinding is detected by
## displacement over time and reported, so the layers above can doubt the edge and look
## again rather than leaning on the rock forever.

## Compression, 0 for the normal body and 1 for the squeezed one.
var _squeeze: float = 0.0
var _grind_origin: Vector3 = Vector3.ZERO
var _grind_elapsed: float = 0.0
var _grind_tracking: bool = false
## Last fit test, for the section 39 overlay and for the panel.
var _normal_fits: bool = true
var _squeezed_fits: bool = true


## Section 10.1, as one line so it cannot drift: squeeze exactly when the normal body is
## the thing in the way.
static func squeeze_required(normal_fits: bool, squeezed_fits: bool) -> bool:
	return not normal_fits and squeezed_fits


## Whether the body is compressed enough to be in a crevice.
func is_squeezed() -> bool:
	return _squeeze >= 1.0


## Compression fraction, for the body to scale its collider and mesh by.
func squeeze_fraction() -> float:
	return _squeeze


## Section 40.2. True when the body has spent a whole `grind_window` going nowhere.
##
## MEASURED OVER A WINDOW, NOT PER TICK. A wiggle is slow by design -- 1.2 m/s against a
## crawl's 5 -- so a single tick of small displacement is what success looks like. Only a
## whole window of it distinguishes working a crevice from leaning on it.
func note_progress(at: Vector3, delta: float, profile: LocomotionProfile) -> bool:
	if not _grind_tracking:
		_grind_tracking = true
		_grind_origin = at
		_grind_elapsed = 0.0
		return false
	_grind_elapsed += delta
	if _grind_elapsed < profile.grind_window:
		return false
	var moved: float = _grind_origin.distance_to(at)
	_grind_origin = at
	_grind_elapsed = 0.0
	return moved < profile.grind_progress_threshold


## Forgets the grind window. Called when the body stops trying to squeeze at all, so a
## fresh crevice is judged on its own progress rather than on the last one's.
func reset_progress() -> void:
	_grind_tracking = false
	_grind_elapsed = 0.0


func debug_state() -> Dictionary:
	return {
		"squeeze": _squeeze,
		"normal_fits": _normal_fits,
		"squeezed_fits": _squeezed_fits,
		"grinding_for": _grind_elapsed,
	}


## The impure entry point. NULL when this is not a squeeze at all -- the normal body fits
## and is not compressed -- which hands the tick back to crawl or swim.
func steer(
	body: NavBodyState,
	toward: Vector3,
	delta: float,
	probe: NavigationProbe,
	config: NavigationConfig
) -> NavMotionCommand:
	var profile: LocomotionProfile = config.locomotion_profile
	var heading: Vector3 = toward - body.position
	if heading.is_zero_approx():
		heading = body.forward
	heading = heading.normalized()

	var ahead: Vector3 = body.position + heading * profile.crawl_step_distance
	_measure_fit(ahead, probe, config)

	if not _normal_fits and not _squeezed_fits:
		# Section 10.3. There is no third body, so this is where a route stops being a
		# route -- and it is the same answer for a player-only tunnel and for a crevice
		# that turned out too tight, because to navigation they are the same thing.
		#
		# BUT ONLY ONCE THE BODY IS COMMITTED. `_measure_fit` samples ONE point a step
		# ahead, and "the point one step that way does not fit" is true of every wall the
		# alien ever faces -- it is the ordinary case, not a failure. Reporting NO_FIT
		# there stops the alien dead in front of any wall and denies the crawler, which
		# scores nine alternatives, the chance to find one of them. Observed: the creature
		# reached the tunnel mouth, faced the rock beside it, and stalled with a COMPLETE
		# route and eight perfectly good directions unexamined.
		#
		# Section 10.3's real case is a body ALREADY COMPRESSED and part-way in, where the
		# passage genuinely does not continue and there is nothing smaller to try.
		if _squeeze <= 0.0:
			reset_progress()
			return null
		return NavMotionCommand.stalled(NavLocomotion.Mode.WIGGLE, NavMotionCommand.Abort.NO_FIT)

	var needed: bool = squeeze_required(_normal_fits, _squeezed_fits)
	if not needed and _squeeze <= 0.0:
		reset_progress()
		return null

	_advance_squeeze(needed, delta, profile)
	if needed and not is_squeezed():
		return _compressing(body, heading, profile)
	# The speed comes from NavigationConfig rather than LocomotionProfile because it is the
	# same number A* charged for the edge (section 14). A controller with its own wiggle
	# speed would make every squeezed route cost something the alien never pays.
	return _working_through(body, heading, delta, config.wiggle_speed, profile)


# ----- internals -----


func _measure_fit(at: Vector3, probe: NavigationProbe, config: NavigationConfig) -> void:
	var pose := Transform3D(Basis.IDENTITY, at)
	var envelope: ClearanceProfile = config.clearance_profile
	_normal_fits = probe.shape_fits(envelope.normal_body(), pose, config.world_mask)
	# Only worth asking when the normal body has already failed. Two shape tests per tick
	# is the price of section 10.1 being about geometry rather than about edge types, and
	# halving it where the answer cannot matter is free.
	_squeezed_fits = true
	if not _normal_fits:
		_squeezed_fits = probe.shape_fits(envelope.squeezed_body(), pose, config.world_mask)


func _advance_squeeze(needed: bool, delta: float, profile: LocomotionProfile) -> void:
	var seconds: float = maxf(profile.squeeze_transition_time, 0.0001)
	var step: float = delta / seconds
	_squeeze = clampf(_squeeze + (step if needed else -step), 0.0, 1.0)


## Compressing in place. Speed zero on purpose: section 43's Scenario B is "approach,
## squeeze, wiggle, emerge, decompress", and an alien that enters the crevice while still
## expanding is doing the first and third at once.
func _compressing(
	body: NavBodyState, heading: Vector3, profile: LocomotionProfile
) -> NavMotionCommand:
	var command := NavMotionCommand.make(NavLocomotion.Mode.WIGGLE, heading, 0.0, body.position)
	command.squeeze = true
	command.clearance = profile.wiggle_exit_margin
	reset_progress()
	return command


## Moving, compressed. Also where section 40.2's abort is raised, because grinding is only
## meaningful once the body is actually trying to make progress.
func _working_through(
	body: NavBodyState, heading: Vector3, delta: float, speed: float, profile: LocomotionProfile
) -> NavMotionCommand:
	if is_squeezed() and note_progress(body.position, delta, profile):
		reset_progress()
		return NavMotionCommand.stalled(
			NavLocomotion.Mode.WIGGLE, NavMotionCommand.Abort.CREVICE_GRIND
		)
	var command := NavMotionCommand.make(NavLocomotion.Mode.WIGGLE, heading, speed, body.position)
	command.squeeze = _squeeze > 0.0
	command.preferred_forward = heading
	command.preferred_up = body.up
	return command
