class_name BtTravelToNest
extends BtAction

## Chooses a nest and walks to it. RUNNING until arrival; FAILURE if the route says
## UNREACHABLE.
##
## THE FAILURE IS NOT A FORMALITY. A nest behind a collapsed passage would otherwise hold the
## alien RUNNING forever against a route that can never complete, and the creature would
## stand at the wall for the rest of the session looking like a pathfinding bug. Failing
## drops the choice, so the next tick scores a different nest -- and the one it just failed
## on is stamped as visited, so it goes to the back of the queue rather than being chosen
## again immediately.
##
## `prefer_distant` is what `retreat_to_nest` will set when it is built; ambient wandering
## wants a near nest and a retreat wants a far one, and fsm.md gives one scoring function for
## both without saying which way the sign goes.

var memory: UnalertedMemory = null
var prefer_distant: bool = false


func _init(p_memory: UnalertedMemory, p_prefer_distant: bool = false) -> void:
	super(&"retreat_to_nest" if p_prefer_distant else &"travel_to_nest")
	memory = p_memory
	prefer_distant = p_prefer_distant


## Gives the goal back, and KEEPS THE CHOSEN NEST.
##
## The abort that fires most often is not an interruption at all -- it is arrival. The
## instant `at_nest` goes true, `idle_at_nest` becomes the running leaf and this node is
## abandoned mid-journey, one tick after it stopped being needed. Clearing `travel_target`
## here therefore destroys exactly the intent the idle branch is about to read: `at_nest`
## goes false again the next tick, travel re-runs, excludes the nest the creature is
## standing in, and with a small nest list finds nowhere to go at all. The alien arrives and
## then stands there having forgotten why.
##
## Re-choosing on a genuine interruption is handled where it belongs -- `UnalertedState`
## forgets the intent on entry, so coming back from an investigation scores the board afresh.
func abort(ctx) -> void:
	ctx.goal.release(self)


func _run(ctx) -> Status:
	if memory == null or memory.nests.is_empty():
		return Status.FAILURE
	if memory.travel_target < 0 and not _choose(ctx):
		return Status.FAILURE

	var destination: Vector3 = memory.nests.position_of(memory.travel_target)
	# The deadband lives in BehaviorGoal, so re-issuing every tick is free and does not reset
	# navigation's stuck watchdog.
	ctx.goal.request(self, destination)

	if ctx.goal.is_unreachable():
		# Stamped so the scoring puts it last, then dropped. Not remembered as "unreachable"
		# -- the alien learns geometry through Spatial Memory, not by blacklisting places
		# here, and a passage that reopens should stop being avoided.
		memory.nests.mark_visited(memory.travel_target, ctx.clock)
		memory.travel_target = -1
		ctx.goal.release(self)
		return Status.FAILURE
	if ctx.goal.is_arrived(ctx.body_position):
		return Status.SUCCESS
	return Status.RUNNING


## Excludes whatever nest the creature is standing in, which is the degenerate half of the
## anti-ping-pong rule; `nest_recent_penalty_s` handles the two-nest shuffle.
func _choose(ctx) -> bool:
	var standing_in: int = memory.nests.nest_within(ctx.body_position, ctx.config.arrive_distance)
	memory.travel_target = memory.nests.choose(
		ctx.body_position, ctx.clock, standing_in, prefer_distant, ctx
	)
	return memory.travel_target >= 0
