class_name BtCanAttack
extends BtCondition

## Would a strike connect right now?
##
## READS THE LATCH RATHER THAN RECOMPUTING IT. HuntingState.refresh works the answer out once
## per tick, before the tree, from the estimate, its staleness, `attack_range_m` and the
## cooldown -- and `EncounterReport.attack_window_open` reads the same field. Deciding it
## here instead would let the branch that actually bites and the number the Director prices
## menace from drift apart, and each half would look correct in isolation.
##
## Pure: reads a bool, writes nothing.

var memory: HuntingMemory = null


func _init(p_memory: HuntingMemory) -> void:
	node_name = &"can_attack"
	memory = p_memory


func _check(_ctx) -> bool:
	return memory != null and memory.attack_window_open
