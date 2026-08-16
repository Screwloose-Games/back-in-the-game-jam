class_name CreatureNestMemory
extends RefCounted

## Which nests the creature knows and when it was last at each, plus the scoring that picks
## the next one (fsm.md, "Action library").
##
## ```text
## nest_score = distance_term + recency_term + directive.roam_bias * proximity_to(roam_anchor)
## ```
##
## THE ROAM TERM IS THE DIRECTOR'S ONLY REACH INTO MOVEMENT, and it is a weighting rather
## than a destination. `roam_anchor` is derived from real player positions, so letting it
## become a goal would hand the alien a position it did not earn. It weights a list of
## nests the creature ALREADY KNOWS: the movement stays explicable in terms of the
## creature's own knowledge, and only the odds changed.
##
## Positions are data, not nodes. The whole thing is testable with three Vector3s.

var positions := PackedVector3Array()

var _visited_at := PackedFloat32Array()


## Higher is better. Pure, so the weighting is checkable without a creature.
##
## `prefer_distant` flips the distance term for retreat, which wants a FAR nest while
## ambient wandering wants a near one. fsm.md gives one formula for both and does not say
## which way the sign goes; roam_bias biases away from the ANCHOR, which is not the same as
## away from the alien, so it cannot serve for this.
static func score(
	travel: float,
	since_visit: float,
	anchor_distance: float,
	roam_bias: float,
	prefer_distant: bool,
	config: BehaviorConfig
) -> float:
	var closeness: float = 1.0 - clampf(travel / maxf(config.nest_distance_span, 0.001), 0.0, 1.0)
	var distance_term: float = (
		config.nest_distance_weight * (-closeness if prefer_distant else closeness)
	)
	var freshness: float = clampf(since_visit / maxf(config.nest_recent_penalty_s, 0.001), 0.0, 1.0)
	var roam_reach: float = (
		1.0 - clampf(anchor_distance / maxf(config.nest_roam_span, 0.001), 0.0, 1.0)
	)
	return distance_term + config.nest_recency_weight * freshness + roam_bias * roam_reach


## Replaces the whole list. Visit stamps are seeded far in the past so a fresh creature has
## no reason to prefer any nest on recency alone.
func remember(p_positions: PackedVector3Array, config: BehaviorConfig) -> void:
	positions = p_positions
	_visited_at = PackedFloat32Array()
	_visited_at.resize(positions.size())
	var penalty: float = config.nest_recent_penalty_s if config != null else 60.0
	_visited_at.fill(-penalty)


func size() -> int:
	return positions.size()


func is_empty() -> bool:
	return positions.is_empty()


func position_of(index: int) -> Vector3:
	if index < 0 or index >= positions.size():
		return Vector3.ZERO
	return positions[index]


func mark_visited(index: int, now: float) -> void:
	if index >= 0 and index < _visited_at.size():
		_visited_at[index] = now


func visited_at(index: int) -> float:
	if index < 0 or index >= _visited_at.size():
		return -INF
	return _visited_at[index]


## The nest the creature is standing in, or -1. Used by the `at_nest` condition, so it
## answers about arrival rather than about intent.
func nest_within(of: Vector3, radius: float) -> int:
	var best: int = -1
	var nearest: float = radius
	for index: int in positions.size():
		var distance: float = of.distance_to(positions[index])
		if distance <= nearest:
			nearest = distance
			best = index
	return best


## The best nest to head for, or -1 when there is nowhere to go.
##
## `exclude` keeps the alien from choosing the nest it is already at, which is the other
## half of the anti-ping-pong rule -- `nest_recent_penalty_s` handles the two-nest shuffle,
## and this handles the degenerate "travel to where I am standing" case.
func choose(from: Vector3, now: float, exclude: int, prefer_distant: bool, ctx) -> int:
	if positions.is_empty():
		return -1
	var directive: EncounterDirective = ctx.directive
	var roam_bias: float = directive.roam_bias if directive != null else 0.0
	var anchor: Vector3 = directive.roam_anchor if directive != null else Vector3.ZERO
	var best: int = -1
	var best_score: float = -INF
	for index: int in positions.size():
		if index == exclude:
			continue
		var at: Vector3 = positions[index]
		var value: float = score(
			from.distance_to(at),
			now - visited_at(index),
			at.distance_to(anchor),
			roam_bias,
			prefer_distant,
			ctx.config
		)
		if value > best_score:
			best_score = value
			best = index
	return best
