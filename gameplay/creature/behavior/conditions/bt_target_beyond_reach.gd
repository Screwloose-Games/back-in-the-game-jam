class_name BtTargetBeyondReach
extends BtCondition

## Does the creature believe the target went somewhere it cannot follow?
##
## Pure: reads two bools, writes nothing.

var memory: HuntingMemory = null


func _init(p_memory: HuntingMemory) -> void:
	node_name = &"target_beyond_reach"
	memory = p_memory


func _check(_ctx) -> bool:
	return memory != null and memory.has_target_estimate and memory.beyond_reach
