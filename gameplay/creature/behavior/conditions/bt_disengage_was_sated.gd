class_name BtDisengageWasSated
extends BtCondition

## Did this encounter end because it had delivered, or because it stalled?
##
## director.md's two exits are not cosmetic. SATED is the earned one -- the menace curve
## reached its peak -- and the alien leaves loudly and unhurried so the player gets the
## exhale. STALLED means the hunt ran long with the menace still low: the alien could not
## reach you, or you went quiet somewhere it could not follow, and nothing was earned. Without
## the split a stalemate ends on the same triumphant beat as a real chase, and the game
## congratulates a player who did nothing.
##
## READS THE LATCH ON THE MEMORY, NOT THE LIVE DIRECTIVE. RetreatingState captures the reason
## in `enter()`; the field this would otherwise read has usually reset to NONE by the time the
## tree first runs. See RetreatingMemory.
##
## Pure: reads an enum, writes nothing.

var memory: RetreatingMemory = null


func _init(p_memory: RetreatingMemory) -> void:
	node_name = &"disengage_was_sated"
	memory = p_memory


func _check(_ctx) -> bool:
	return memory != null and memory.disengage_reason == EncounterDirective.Reason.SATED
