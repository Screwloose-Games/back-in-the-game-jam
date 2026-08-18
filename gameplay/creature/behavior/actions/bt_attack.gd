class_name BtAttack
extends BtAction

## Strikes at the target estimate. SUCCESS either way, per fsm.md's action table.
##
## IT READS `directive.lethality`; IT DOES NOT DECIDE IT. GRACE resolves as a near-miss and
## LETHAL does not, and which one this is depends on session history -- first encounter,
## respawn grace, whether the menace curve has earned its payoff. Only the Director has any of
## that, and director.md's "one near-miss per encounter" latch belongs there too. Behavior
## owns the consequence and none of the judgement.
##
## THE CONSEQUENCE IS A SIGNAL, BECAUSE THERE IS NOTHING TO DAMAGE YET. Nothing in
## `gameplay/` has health, and an action reaching for a player node to call something on it
## would be the decision layer touching the world it is forbidden to read. `attack_landed` is
## relayed by CreatureBehavior alongside `action_changed`, which is where animation already
## hangs; whoever builds damage subscribes to it and nothing here changes.

var memory: HuntingMemory = null


func _init(p_memory: HuntingMemory) -> void:
	super(&"attack")
	memory = p_memory


func _run(ctx) -> Status:
	if memory == null or not memory.attack_window_open:
		return Status.FAILURE

	var target: Node = ctx.directive.target if ctx.directive != null else null
	var lethality: EncounterDirective.Lethality = EncounterDirective.Lethality.LETHAL
	if ctx.directive != null:
		lethality = ctx.directive.lethality
	memory.attack_landed.emit(target, lethality)
	return Status.SUCCESS
