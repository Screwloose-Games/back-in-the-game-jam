class_name TetherRope
extends RefCounted

## A rope simulated as a chain of points, for the tether carry mode.
##
## Each point carries its own momentum and the segments between them refuse to
## stretch past their rest length. That is the whole model - there is no list of
## places the rope is bent and no reasoning about corners. A rope goes around a
## pillar because its points cannot get inside the pillar, which is the same
## reason a real one does.
##
## Nothing here knows about gravity. In vacuum a slack rope is not hanging, it
## is coasting: it keeps whatever motion it was given and trails behind you off
## its own inertia. TETHER_ROPE_DAMPING is the only thing that ever slows it,
## and it exists to stop the chain ringing rather than to model air.
##
## The two ends are pinned to the anchors every step and never simulated. What
## the carrier does with the rope - how hard it hauls, which way, and when it
## parts - is decided from the shape this leaves behind, in carrier_player.gd.

## Passes of the length constraint run after the rope has been lifted clear of
## the hull, so no segment is left holding an impossible length in the frame
## that gets drawn. Lifting a point answers to one neighbour at a time and can
## always leave the segment on its other side stretched; wherever the lifting
## stops, that is where a segment would otherwise be found spanning metres in a
## straight line. What little these push back into the hull is small enough for
## the next step to pick up.
const SETTLE_ITERATIONS := 4

var _positions := PackedVector3Array()
var _previous_positions := PackedVector3Array()
var _segment_rest_length := 0.0


## Lays the rope out straight between the two anchors, at rest. Called when a
## load is taken hold of, so the rope starts the run with no momentum of its
## own and no shape it did not earn.
##
## The length is passed in rather than read from the knobs because it has a
## slider now, and this is the only moment it can be acted on: the point count is
## fixed from here until the next clip, so a rope already on the line cannot
## change length. Unclip and re-clip to pick up a new one.
func reset(object_anchor: Vector3, suit_anchor: Vector3, length: float) -> void:
	var segment_count := maxi(1, int(roundf(length / CarryKnobs.TETHER_ROPE_SEGMENT)))
	var point_count := segment_count + 1
	_positions.resize(point_count)
	_previous_positions.resize(point_count)
	_segment_rest_length = length / float(segment_count)

	for index: int in range(point_count):
		var along := float(index) / float(point_count - 1)
		var start_position := object_anchor.lerp(suit_anchor, along)
		_positions[index] = start_position
		_previous_positions[index] = start_position


## Advances the rope one physics step and leaves it pinned to both anchors.
##
## Order matters here. Collision is settled against the step's own motion and
## nothing else, before the segments are solved, because the two corrections
## mean opposite things: momentum carrying a point into a wall has to be
## stopped, while the segments hauling that same point the long way round a
## pillar is the rope working. Judging a constraint pull by where the point
## started reads the second as the first, and pins the rope to the wrong side
## of whatever it is coming around. What the segments push through is caught
## afterwards by _untangle_segments, which asks the neighbours rather than the
## history.
func step(
	delta: float,
	space_state: PhysicsDirectSpaceState3D,
	object_anchor: Vector3,
	suit_anchor: Vector3
) -> void:
	if _positions.size() < 2:
		return

	var positions_before_step := _positions.duplicate()
	_carry_momentum(delta)
	_resolve_collisions(space_state, positions_before_step)

	_pin_ends(object_anchor, suit_anchor)
	for iteration: int in range(CarryKnobs.TETHER_ROPE_ITERATIONS):
		_pull_segments_together(iteration % 2 == 0)
	_untangle_segments(space_state)
	for iteration: int in range(SETTLE_ITERATIONS):
		_pull_segments_together(iteration % 2 == 0)
	_pin_ends(object_anchor, suit_anchor)


## Length of the rope along its whole shape, in metres. This is what the strain
## on the line is measured from, so a rope draped around a pillar has already
## spent the length the detour cost.
func measure_length() -> float:
	var total := 0.0
	for index: int in range(_positions.size() - 1):
		total += _positions[index].distance_to(_positions[index + 1])
	return total


## Straight-line distance between the two ends. Compared against the length, it
## says how much of the rope is going the long way round.
func measure_span() -> float:
	if _positions.size() < 2:
		return 0.0
	return _positions[0].distance_to(_positions[-1])


## The point the object end pulls against: the rope's own next link, not the
## far anchor. Once the rope is draped over something those are different
## directions, and this is the one the load actually feels.
func read_point_beside_object() -> Vector3:
	return _positions[1]


## The point the suit end pulls against, for the same reason.
func read_point_beside_suit() -> Vector3:
	return _positions[-2]


## The whole rope, for drawing.
func read_points() -> PackedVector3Array:
	return _positions


# --- Simulation ------------------------------------------------------------


## Verlet integration: a point's velocity is implied by where it was last step,
## so moving a point by hand - pinning it, or lifting it out of a wall - also
## sets what it does next. There is no gravity term; nothing falls here.
func _carry_momentum(delta: float) -> void:
	var retention := clampf(1.0 - CarryKnobs.TETHER_ROPE_DAMPING * delta, 0.0, 1.0)
	for index: int in range(_positions.size()):
		var current := _positions[index]
		_positions[index] = current + (current - _previous_positions[index]) * retention
		_previous_positions[index] = current


func _pin_ends(object_anchor: Vector3, suit_anchor: Vector3) -> void:
	_positions[0] = object_anchor
	_positions[-1] = suit_anchor


## One pass of the length constraint, sweeping the rope from one end.
##
## Each pass carries a correction as far as it sweeps, so a pass that always
## started at the same end would take one step per segment to get news of a
## pull to the far end - on a long rope that leaves the far half stretched for
## as many frames. Alternating the direction means both ends hear about tension
## within a pass, which is what keeps segments near their rest length instead
## of a few of them taking all the stretch.
func _pull_segments_together(from_object_end: bool) -> void:
	var last_index := _positions.size() - 1
	if from_object_end:
		for index: int in range(last_index):
			_pull_segment_together(index, last_index)
		return
	for index: int in range(last_index - 1, -1, -1):
		_pull_segment_together(index, last_index)


## Brings one segment back toward a length it is allowed to have. Stretching is
## resisted outright, which is the difference between a rope and a rubber band.
## Closing up is resisted too, but gently and only past TETHER_ROPE_SPREAD,
## which is the difference between a rope and a piece of string with nothing to
## it: rope has thickness, and a chain of points with no floor under its
## segments gathers all its slack into one place and leaves the rest of itself
## as a single straight run.
##
## A segment with a pinned end gives the whole correction to its free end. Half
## of every correction would otherwise be handed to a point that is about to be
## put back where it was, which costs the ends most of their solve.
func _pull_segment_together(index: int, last_index: int) -> void:
	var offset := _positions[index + 1] - _positions[index]
	var length := offset.length()
	if is_zero_approx(length):
		return

	var target := _segment_rest_length
	# Softened, because being crowded is a much weaker thing to a rope than
	# being stretched, and answering it at full strength makes the chain buzz.
	var strength := 0.5
	if length > _segment_rest_length:
		strength = 1.0
	elif length < _segment_rest_length * CarryKnobs.TETHER_ROPE_SPREAD:
		target = _segment_rest_length * CarryKnobs.TETHER_ROPE_SPREAD
	else:
		return

	var correction := offset * ((length - target) / length) * strength
	var pulls_first := index != 0
	var pulls_second := index + 1 != last_index
	if pulls_first and pulls_second:
		_positions[index] += correction * 0.5
		_positions[index + 1] -= correction * 0.5
	elif pulls_first:
		_positions[index] += correction
	elif pulls_second:
		_positions[index + 1] -= correction


## Lifts any point that has moved into the hull back out to its surface, and
## takes the into-the-wall part of its momentum with it. What is left is a
## scrape along the face, which is how a rope under tension slides round a
## corner rather than sticking where it first touched.
##
## The ends are skipped: they belong to the anchors, and an anchor that has
## been backed into a wall is the carrier's problem, not the rope's.
func _resolve_collisions(
	space_state: PhysicsDirectSpaceState3D, positions_before: PackedVector3Array
) -> void:
	for index: int in range(1, _positions.size() - 1):
		if positions_before[index].is_equal_approx(_positions[index]):
			continue
		_lift_point_clear(space_state, positions_before[index], index)


## Walks the rope from each end in turn, casting along every segment and
## lifting the far point out whenever a segment runs through the hull.
##
## This is what the per-point pass cannot do on its own. A point only knows
## about geometry it moved into, so two points can end up either side of a
## corner with the rope drawn straight through it, and a point that somehow
## got inside the hull can never see its way out - a ray cast from in there
## finds nothing to hit. Casting from a neighbour instead means the ray always
## starts somewhere the rope is known to be clear, and the fix propagates down
## the chain from the anchors, which are the two points that are always right.
## The sweep from the object end covers the whole rope, so every segment is
## looked at by something. The sweep back from the suit end then goes over its
## own half again, and being second it has the final say there.
##
## Which pass has the final say over a point matters. A pass is only as good as
## the chain of points behind it, and that chain is trustworthy where it starts
## at an anchor. Letting the sweep from the suit end re-judge the point beside
## the load undoes a perfectly good answer taken from the anchor a step away,
## and replaces it with one taken from the point on the far side, which on a
## rope whose slack has gathered elsewhere can be metres off: the point lands
## out there and the segment holding the load spans the room in one straight
## run. Stopping that sweep at the middle fixes it, and running the other one
## the whole way is what keeps the middle itself from becoming a seam that
## nothing checks.
func _untangle_segments(space_state: PhysicsDirectSpaceState3D) -> void:
	var last_index := _positions.size() - 1
	for index: int in range(last_index - 1):
		_lift_point_clear(space_state, _positions[index], index + 1)
	for index: int in range(last_index, last_index / 2, -1):
		_lift_point_clear(space_state, _positions[index], index - 1)


## Casts from a point known to be clear toward one that may not be, and if the
## hull is in the way, puts the second point back on the near side of it.
func _lift_point_clear(
	space_state: PhysicsDirectSpaceState3D, clear_position: Vector3, index: int
) -> void:
	var query := PhysicsRayQueryParameters3D.create(
		clear_position, _positions[index], CarryKnobs.TETHER_ROPE_LAYERS
	)
	var hit := space_state.intersect_ray(query)
	if hit.is_empty():
		return

	var contact_point: Vector3 = hit["position"]
	var contact_normal: Vector3 = hit["normal"]
	var lifted := contact_point + contact_normal * CarryKnobs.TETHER_ROPE_RADIUS

	# Never put a point further from the neighbour it was judged against than a
	# segment can actually reach. A stretched span can have any amount of hull
	# lying across it, and dropping its far point onto whatever surface it
	# happens to meet would pin the stretch there: the length constraint hauls
	# the point back, this pass drags it out again, and the rope sits locked
	# through the very thing it was meant to come round. Anything nearer than a
	# segment's reach is clear ground, since the ray only just found the hull
	# beyond it.
	var reach := lifted - clear_position
	if reach.length() > _segment_rest_length:
		lifted = clear_position + reach.normalized() * _segment_rest_length

	var point_velocity := _positions[index] - _previous_positions[index]
	_positions[index] = lifted
	_previous_positions[index] = (
		lifted - point_velocity.slide(contact_normal) * (1.0 - CarryKnobs.TETHER_ROPE_FRICTION)
	)
