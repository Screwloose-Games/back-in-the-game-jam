class_name BtHasTargetEstimate
extends BtCondition

## Is there somewhere worth running at?
##
## THE REACH CLAUSE IS WHAT KEEPS CHASE AND LURK APART. fsm.md puts chase above lurk in the
## selector and gives chase no failure clause for a route that stops short, so an estimate the
## creature cannot actually reach would hold the chase branch RUNNING for ever and the lurk
## branch would never be reached -- exactly when there is something to lurk at. Excluding
## `beyond_reach` here makes the two branches complementary by construction, and neither
## condition has to command anything to find that out.
##
## IT DELIBERATELY DOES NOT ASK WHETHER THE ESTIMATE IS FRESH, and it took a sandbox to work
## out why. Gating the walk on freshness leaves a creature that has lost sight of you standing
## exactly where it was, sweeping a region twenty metres away that it is not in -- because
## `search_area` commands no goal and there is no other movement leaf below this one.
## behavior.md section 28 asks for a search "around the target's last credible region", and
## that means going there. So the alien walks to its best guess whatever its age, arrives,
## `chase_target` reports FAILURE, and the sweep below takes the tick. Staleness gates the
## BITE instead, where it belongs: an alien may run at old news; it may not swing at it.
##
## Pure: reads two bools, writes nothing.

var memory: HuntingMemory = null


func _init(p_memory: HuntingMemory) -> void:
	node_name = &"has_target_estimate"
	memory = p_memory


func _check(_ctx) -> bool:
	return memory != null and memory.has_target_estimate and not memory.beyond_reach
