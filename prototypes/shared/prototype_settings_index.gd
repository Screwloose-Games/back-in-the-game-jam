class_name PrototypeSettingsIndex
extends Resource

## Every prototype's saved playtest values, collected in one resource.
##
## Open prototypes/prototype_settings.tres to see and edit every set in the
## inspector at once, and to reset or re-save them together.
##
## NOTHING AT RUNTIME COMES THROUGH HERE. Each prototype scene holds its own
## settings by @export, so a prototype still runs when this file is missing and a
## broken sibling cannot take it down with it. That is the whole reason the index
## is convenience rather than plumbing - it collects, it does not mediate.

const INDEX_PATH := "res://prototypes/prototype_settings.tres"

@export var navigation: NavigationSettings
@export var object_carrying: CarrySettings
@export var tunnel_system: TunnelSettings
@export var tentacle_crawler_chaser: ChaseSettings
@export var elevator_cutscene: ElevatorCutsceneSettings
@export var level_design_01: LevelDesign01Settings
@export var alien_ai_pathfinding: AlienPathfindingSettings
@export var drill_and_mining: DrillSettings
@export var core_loop: CoreLoopSettings


## The children that are actually present, in declaration order.
##
## THIS LIST IS HAND-MAINTAINED AND NOTHING CHECKS IT. Adding an @export above
## without adding it here compiles, saves, and loads - and the new prototype is
## then silently absent from save_all(), reset_all() and invariant_failures().
func all() -> Array[PrototypeSettings]:
	var found: Array[PrototypeSettings] = []
	for child: PrototypeSettings in [
		navigation,
		object_carrying,
		tunnel_system,
		tentacle_crawler_chaser,
		elevator_cutscene,
		level_design_01,
		alien_ai_pathfinding,
		drill_and_mining,
		core_loop,
	]:
		if child != null:
			found.append(child)
	return found


## Saves every child to its own .tres.
##
## THIS FILE IS NEVER WRITTEN. It holds four references and no values, so
## re-saving it can only churn resource ids in git for no gain - and the children
## are separate files held as ExtResource, which is exactly why saving one of them
## does not need the index rewritten.
func save_all() -> Error:
	var first_error := OK
	for child: PrototypeSettings in all():
		var error := child.save()
		if error != OK and first_error == OK:
			first_error = error
	return first_error


## Every child back to its knobs consts. Not saved - press SAVE, or call
## save_all(), if that is what you meant.
func reset_all() -> void:
	for child: PrototypeSettings in all():
		child.reset()


## Every child's failures, each tagged with the prototype it came from.
func invariant_failures() -> PackedStringArray:
	var failures := PackedStringArray()
	for child: PrototypeSettings in all():
		var label := child.settings_path().get_file()
		for failure: String in child.invariant_failures():
			failures.append("%s: %s" % [label, failure])
	return failures
