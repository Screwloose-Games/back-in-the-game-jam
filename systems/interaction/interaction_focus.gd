class_name InteractionFocus
extends RefCounted

## The arithmetic of picking what the prompt points at. A pure static scorer, so
## the interactor's Area3D bookkeeping and the selection policy cannot tangle:
## candidates go in as points, one index comes out.
##
## The policy is nearest-wins, bent two ways. Being off your forward axis costs
## extra metres, so of two things at equal distance the one you are looking at
## wins; and the thing already focused gets a discount, so two candidates that
## score alike do not swap the prompt every frame.


## The best candidate's index into `points`, or -1 when nothing qualifies.
##
## `min_facing` is a dot-product cutoff against the head's forward axis: anything
## below it is never addressed, whatever it scores. `facing_weight` is what being
## off-axis costs, as a multiple of true distance at 90 degrees. `stickiness` is
## the discount `current_index` gets, as a fraction of its score.
static func best_candidate(
	head_transform: Transform3D,
	points: PackedVector3Array,
	range_m: float,
	min_facing: float,
	facing_weight: float,
	current_index: int,
	stickiness: float
) -> int:
	var eye := head_transform.origin
	var forward := -head_transform.basis.z
	var best := -1
	var best_score := INF
	for index in points.size():
		var offset := points[index] - eye
		var distance := offset.length()
		if distance > range_m:
			continue
		# Something at the eye itself has no direction to test; it is as faced as
		# anything can be.
		var facing := 1.0
		if distance > 0.0:
			facing = forward.dot(offset / distance)
		if facing < min_facing:
			continue
		# Zero extra dead ahead, `facing_weight` times the true distance at 90
		# degrees, and more again past that -- so selection stays purely nearest
		# when the weight is zero.
		var score := distance * (1.0 + facing_weight * (1.0 - facing))
		if index == current_index:
			score *= 1.0 - stickiness
		if score < best_score:
			best_score = score
			best = index
	return best
