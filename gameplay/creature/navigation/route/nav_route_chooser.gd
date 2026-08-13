class_name NavRouteChooser
extends RefCounted

## Picks among plausible routes (navigation.md section 35).
##
## SECTION 35 OPENS BY FORBIDDING THE OBVIOUS IMPLEMENTATION: "do not create
## unpredictability with arbitrary bad decisions". An alien that sometimes takes a
## nonsense route is not unpredictable, it is broken, and players read it as broken
## immediately. What section 35 asks for instead is a choice among routes that are all
## REASONABLE -- compute several, compare their costs, and pick probabilistically between
## the ones worth picking.
##
## THE TOLERANCE BAND IS WHAT MAKES THAT TRUE. Section 35's worked example is 31 / 34 / 38
## / 67, and it says the alien may choose any of the first three and "should almost never
## choose D". Giving D a small weight makes "almost never" a frequency, which means it
## happens on some unlucky playthrough and looks like the bug this section exists to
## prevent. Excluding it outright is a cleaner statement of the same intent: at the
## shipped 0.25 tolerance, D is 2.2x the best and is simply not eligible.
##
## SHARPNESS IS SECTION 35'S INTELLIGENCE DIAL -- "higher intelligence narrows selection
## toward better alternatives; lower intelligence increases variation". High concentrates
## the choice on the best eligible route; low spreads it evenly across the band.
##
## THE RNG IS SEEDED FROM CONFIG AND NEVER FROM THE CLOCK. A route that differs between
## two runs of the same scenario is a bug nobody can reproduce, and this is the only place
## in the module that could produce one. `CreatureHearing.rng` is seeded the same way for
## the same reason.

var rng: RandomNumberGenerator = null


func _init() -> void:
	# RandomNumberGenerator randomises itself on construction, so the seed has to be
	# assigned explicitly by the facade -- leaving it is how a deterministic-looking
	# system turns out not to be.
	rng = RandomNumberGenerator.new()


## Selection weights for a set of costs. Zero for anything outside the tolerance band.
##
## Static and pure, so section 35's own example can be asserted without an instance and
## without a seed.
static func weights(
	costs: PackedFloat32Array, tolerance: float, sharpness: float
) -> PackedFloat32Array:
	var scores := PackedFloat32Array()
	if costs.is_empty():
		return scores
	var best: float = costs[0]
	for cost: float in costs:
		best = minf(best, cost)
	if best <= 0.0:
		best = 0.0001
	var limit: float = best * (1.0 + maxf(tolerance, 0.0))
	for cost: float in costs:
		if cost > limit:
			scores.append(0.0)
			continue
		# Softmax on how much worse than the best this is, in units of the best. Relative
		# rather than absolute, so the same tolerance means the same thing in a 5 m cave
		# and a 50 m one.
		var excess: float = (cost - best) / best
		scores.append(exp(-sharpness * excess))
	return scores


## One route from `routes`, or null if none is usable.
##
## The best route is returned outright when `route_alternatives` is 1, which is what makes
## turning section 35 off a config change rather than a code path.
func choose(routes: Array[NavRoute], config: NavigationConfig) -> NavRoute:
	var usable: Array[NavRoute] = []
	var costs := PackedFloat32Array()
	for route: NavRoute in routes:
		if route == null or not route.is_usable():
			continue
		usable.append(route)
		costs.append(route.cost)
	if usable.is_empty():
		return null
	if usable.size() == 1 or config.route_alternatives <= 1:
		return _cheapest(usable)

	var scores: PackedFloat32Array = weights(
		costs, config.route_tolerance, config.route_selection_sharpness
	)
	var total: float = 0.0
	for score: float in scores:
		total += score
	if total <= 0.0:
		return _cheapest(usable)

	var roll: float = rng.randf() * total
	for index: int in usable.size():
		roll -= scores[index]
		if roll <= 0.0:
			return usable[index]
	return _cheapest(usable)


static func _cheapest(routes: Array[NavRoute]) -> NavRoute:
	var best: NavRoute = routes[0]
	for route: NavRoute in routes:
		if route.cost < best.cost:
			best = route
	return best
