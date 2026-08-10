extends SceneTree

## Creates any prototype settings .tres that does not exist yet, at knobs
## defaults, plus the index that collects them. Run it with:
##
##     godot --headless --path <root> \
##       --script res://prototypes/tools/bootstrap_prototype_settings.gd
##
## As `--script`, not as a scene: this only touches files, so the "nodes added
## during _initialize() never get _ready()" trap that verify_*.tscn exists to
## dodge does not apply here.
##
## EXISTING FILES ARE LEFT ALONE. The whole point of these resources is to hold
## values somebody tuned by hand, so re-running this can only ever add what is
## missing - it is how you pick up a new prototype, not how you reset one. Use
## the panel's RESET button for that.
##
## Godot writes the uid= attributes itself, which is the reason this is a script
## rather than four hand-authored text files: a real UID cannot be invented.

## Script paths rather than class names, because a class_name that does not exist
## yet is a parse error and this has to run while the set is still being filled in.
const SETTINGS_SCRIPTS := [
	"res://prototypes/navigation/navigation_settings.gd",
	"res://prototypes/object_carrying/carry_settings.gd",
	"res://prototypes/tunnel_system/tunnel_settings.gd",
	"res://prototypes/tentacle_crawler_chaser/chase_settings.gd",
	"res://prototypes/elevator_cutscene/elevator_cutscene_settings.gd",
	"res://prototypes/level_design_01/level_design_01_settings.gd",
	"res://prototypes/drill_and_mining/drill_settings.gd",
]

const INDEX_SCRIPT := "res://prototypes/shared/prototype_settings_index.gd"
const INDEX_PATH := "res://prototypes/prototype_settings.tres"

## Index property name for each settings script, in the order above.
const INDEX_PROPERTIES := [
	"navigation",
	"object_carrying",
	"tunnel_system",
	"tentacle_crawler_chaser",
	"elevator_cutscene",
	"level_design_01",
	"drill_and_mining",
]


func _initialize() -> void:
	var found: Array[String] = []
	for path: String in SETTINGS_SCRIPTS:
		var result := _ensure(path)
		if not result.is_empty():
			found.append(result)
	_ensure_index()
	print("bootstrap_prototype_settings: %d settings resource(s) present" % found.size())
	quit()


## Writes <script_dir>/<script_name>.tres at defaults if it is not there already.
## Returns the .tres path, or "" if the script does not exist yet.
func _ensure(script_path: String) -> String:
	if not FileAccess.file_exists(script_path):
		print("  skipped %s (not written yet)" % script_path.get_file())
		return ""
	var script: GDScript = load(script_path)
	if script == null:
		printerr("  could not load %s" % script_path)
		return ""
	var settings: Resource = script.new()
	var target: String = settings.settings_path()
	if target.is_empty():
		printerr("  %s has no settings_path()" % script_path.get_file())
		return ""
	if FileAccess.file_exists(target):
		print("  kept    %s (already exists)" % target.get_file())
		return target
	var error := ResourceSaver.save(settings, target)
	if error != OK:
		printerr("  FAILED  %s: %s" % [target, error_string(error)])
		return ""
	print("  created %s" % target)
	return target


## Rebuilds the index whenever a child is missing from it.
##
## The index holds references and no values of its own, so rewriting it cannot
## lose anybody's tuning - which is why this one is not skip-if-exists.
func _ensure_index() -> void:
	if not FileAccess.file_exists(INDEX_SCRIPT):
		print("  skipped index (not written yet)")
		return
	var script: GDScript = load(INDEX_SCRIPT)
	var index: Resource = script.new()
	var linked := 0
	for slot: int in SETTINGS_SCRIPTS.size():
		var script_path: String = SETTINGS_SCRIPTS[slot]
		if not FileAccess.file_exists(script_path):
			continue
		var child_script: GDScript = load(script_path)
		var target: String = (child_script.new() as Resource).settings_path()
		if not FileAccess.file_exists(target):
			continue
		index.set(INDEX_PROPERTIES[slot], load(target))
		linked += 1
	var error := ResourceSaver.save(index, INDEX_PATH)
	if error != OK:
		printerr("  FAILED  %s: %s" % [INDEX_PATH, error_string(error)])
		return
	print("  wrote   %s (%d linked)" % [INDEX_PATH, linked])
