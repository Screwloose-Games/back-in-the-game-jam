class_name PlayerTetherRope
extends RefCounted

## A rope simulated as a chain of Verlet points whose segments refuse to stretch.
## It goes around a pillar because its points cannot get inside one, not because
## anything here reasons about corners; nothing falls, because there is no gravity
## in vacuum. Pass a null space_state to run the constraint solver without physics.

## Extra constraint passes after the rope is lifted clear, so no segment is left
## holding an impossible length in the frame that gets drawn.
const SETTLE_ITERATIONS := 4

## Distance between simulated points, in metres. This is what the rope can wrap.
var segment_spacing := 0.2
## Constraint passes per step. Tension needs several to reach down the chain.
var iterations := 12
## Fraction of a point's speed shed per second, to stop the chain ringing.
var point_damping := 2.0
## How far a segment may close up before it pushes back, as a fraction of rest.
var spread := 0.85
## How far off a surface a point rests, in metres.
var contact_radius := 0.16
## Fraction of along-surface speed a point loses when it scrapes.
var friction := 0.4
## Physics layers the rope collides with. Hull only, or it fights itself.
var collision_layers := 1

var _positions := PackedVector3Array()
var _previous_positions := PackedVector3Array()
var _segment_rest_length := 0.0


## Lays the rope out straight between the anchors, at rest. The point count is
## fixed from here, so a rope already on the line cannot change length.
func reset(object_anchor: Vector3, suit_anchor: Vector3, length: float) -> void:
	var segment_count := maxi(1, int(roundf(length / maxf(segment_spacing, 0.0001))))
	var point_count := segment_count + 1
	_positions.resize(point_count)
	_previous_positions.resize(point_count)
	_segment_rest_length = length / float(segment_count)

	for index: int in range(point_count):
		var along := float(index) / float(point_count - 1)
		var start_position := object_anchor.lerp(suit_anchor, along)
		_positions[index] = start_position
		_previous_positions[index] = start_position


## Advances the rope one step and leaves it pinned to both anchors. Collision is
## settled against the step's own motion before the segments are solved, or a
## constraint pull reads as momentum and pins the rope to the wrong side of what
## it is coming around.
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
	if space_state != null:
		_resolve_collisions(space_state, positions_before_step)

	_pin_ends(object_anchor, suit_anchor)
	for iteration: int in range(iterations):
		_pull_segments_together(iteration % 2 == 0)
	if space_state != null:
		_untangle_segments(space_state)
	for iteration: int in range(SETTLE_ITERATIONS):
		_pull_segments_together(iteration % 2 == 0)
	_pin_ends(object_anchor, suit_anchor)


## Length along the rope's whole shape, so a draped rope has already spent what
## the detour cost.
func measure_length() -> float:
	var total := 0.0
	for index: int in range(_positions.size() - 1):
		total += _positions[index].distance_to(_positions[index + 1])
	return total


## Straight-line distance between the ends, for measuring how much rope is
## going the long way round.
func measure_span() -> float:
	if _positions.size() < 2:
		return 0.0
	return _positions[0].distance_to(_positions[-1])


## The point the object end pulls against — the rope's next link, not the far
## anchor, which is a different direction once the rope is draped.
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
## so moving one by hand also sets what it does next.
func _carry_momentum(delta: float) -> void:
	var retention := clampf(1.0 - point_damping * delta, 0.0, 1.0)
	for index: int in range(_positions.size()):
		var current := _positions[index]
		_positions[index] = current + (current - _previous_positions[index]) * retention
		_previous_positions[index] = current


func _pin_ends(object_anchor: Vector3, suit_anchor: Vector3) -> void:
	_positions[0] = object_anchor
	_positions[-1] = suit_anchor


## One pass of the length constraint. The direction alternates so both ends hear
## about tension within a pass instead of a few segments taking all the stretch.
func _pull_segments_together(from_object_end: bool) -> void:
	var last_index := _positions.size() - 1
	if from_object_end:
		for index: int in range(last_index):
			_pull_segment_together(index, last_index)
		return
	for index: int in range(last_index - 1, -1, -1):
		_pull_segment_together(index, last_index)


## Brings one segment back toward a length it is allowed to have. Stretching is
## resisted outright; closing up is resisted gently and only past `spread`,
## which is what stops all the slack gathering into one place.
func _pull_segment_together(index: int, last_index: int) -> void:
	var offset := _positions[index + 1] - _positions[index]
	var length := offset.length()
	if is_zero_approx(length):
		return

	var target := _segment_rest_length
	var strength := 0.5
	if length > _segment_rest_length:
		strength = 1.0
	elif length < _segment_rest_length * spread:
		target = _segment_rest_length * spread
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


## Lifts any point that moved into the hull back out, taking the into-the-wall
## part of its momentum with it. The ends belong to the anchors and are skipped.
func _resolve_collisions(
	space_state: PhysicsDirectSpaceState3D, positions_before: PackedVector3Array
) -> void:
	for index: int in range(1, _positions.size() - 1):
		if positions_before[index].is_equal_approx(_positions[index]):
			continue
		_lift_point_clear(space_state, positions_before[index], index)


## Walks the rope from each end, casting along every segment and lifting the far
## point out where a segment runs through the hull. Casting from a neighbour
## means the ray always starts somewhere the rope is known to be clear, so the
## fix propagates from the anchors — the two points that are always right.
func _untangle_segments(space_state: PhysicsDirectSpaceState3D) -> void:
	var last_index := _positions.size() - 1
	for index: int in range(last_index - 1):
		_lift_point_clear(space_state, _positions[index], index + 1)
	# Stops at the middle: re-judging the point beside the load from the far side
	# would replace a good answer taken one step from its anchor with a bad one.
	for index: int in range(last_index, last_index / 2, -1):
		_lift_point_clear(space_state, _positions[index], index - 1)


## Casts from a point known to be clear toward one that may not be, and puts the
## second back on the near side of any hull in the way.
func _lift_point_clear(
	space_state: PhysicsDirectSpaceState3D, clear_position: Vector3, index: int
) -> void:
	var query := PhysicsRayQueryParameters3D.create(
		clear_position, _positions[index], collision_layers
	)
	var hit := space_state.intersect_ray(query)
	if hit.is_empty():
		return

	var contact_point: Vector3 = hit["position"]
	var contact_normal: Vector3 = hit["normal"]
	var lifted := contact_point + contact_normal * contact_radius

	# Never put a point further from its judging neighbour than a segment can
	# reach, or a stretched span gets pinned through the very thing it should
	# come round.
	var reach := lifted - clear_position
	if reach.length() > _segment_rest_length:
		lifted = clear_position + reach.normalized() * _segment_rest_length

	var point_velocity := _positions[index] - _previous_positions[index]
	_positions[index] = lifted
	_previous_positions[index] = lifted - point_velocity.slide(contact_normal) * (1.0 - friction)
