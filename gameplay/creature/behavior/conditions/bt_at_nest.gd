class_name BtAtNest
extends BtCondition

## Is the creature at the nest it set out for?
##
## NOT "IS THERE A NEST NEARBY", AND THE DIFFERENCE IS WHAT KEEPS THE STATE MOVING. A
## condition that answered about proximity would still be true the moment a dwell finished
## -- the alien is, after all, still standing in the nest -- so the idle branch would win
## again and re-arm its own timer, forever. Keyed on intent, it goes false the instant
## `idle_at_nest` clears the target, and the selector falls through to choosing another.
##
## Pure: reads a position and an index, writes nothing.

var memory: UnalertedMemory = null


func _init(p_memory: UnalertedMemory) -> void:
	node_name = &"at_nest"
	memory = p_memory


func _check(ctx) -> bool:
	if memory == null or memory.travel_target < 0:
		return false
	var at: Vector3 = memory.nests.position_of(memory.travel_target)
	return ctx.body_position.distance_to(at) <= ctx.config.arrive_distance
