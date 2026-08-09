extends Node

## Headless check that the prototype settings resources still hold up. Run it as:
##
##     godot --headless --path <root> \
##       res://prototypes/tools/verify_prototype_settings.tscn
##
## As a SCENE named on the command line, not as `--script` and not bare. Nodes
## added during SceneTree._initialize() never receive _ready(), and this builds a
## real panel, so a bare script harness would print nothing and exit 0 - which is
## indistinguishable from a pass.
##
## [range] is the check this file exists for. Narrow a knob's MIN/MAX pair after
## somebody saved a value near the old edge and the committed .tres still holds
## the out-of-range number. The slider clamps how it DISPLAYS that, so the panel
## looks correct while the prototype goes on applying a value you can no longer
## dial back to - a drift with no symptom until someone measures it.
##
## [panel] catches the other silent one. A number declared without @export_range
## gets no control, so the knob looks saved and simply never appears; comparing
## the control count against the property count turns that into a failure.

const SETTINGS_SCRIPTS := [
	"res://prototypes/navigation/navigation_settings.gd",
	"res://prototypes/object_carrying/carry_settings.gd",
	"res://prototypes/tunnel_system/tunnel_settings.gd",
	"res://prototypes/tentacle_crawler_chaser/chase_settings.gd",
	"res://prototypes/mineral_discovery/mineral_settings.gd",
]

## Somewhere writable that is not the repo. The round trip has to write a real
## file to be worth anything, but it must not be the committed one - a verifier
## that leaves the tuning at test values is worse than no verifier.
const ROUNDTRIP_PATH := "user://verify_prototype_settings_roundtrip.tres"

var _failures := 0
var _checks := 0


func _ready() -> void:
	for script_path: String in SETTINGS_SCRIPTS:
		if not FileAccess.file_exists(script_path):
			continue
		_verify(script_path)
	_report()


func _verify(script_path: String) -> void:
	var label := script_path.get_file()
	var script: GDScript = load(script_path)
	var defaults: PrototypeSettings = script.new()
	var target := defaults.settings_path()

	_check("%s [path]" % label, not target.is_empty(), "settings_path() is empty")
	if target.is_empty():
		return
	_check(
		"%s [committed]" % label,
		FileAccess.file_exists(target),
		"%s does not exist - run bootstrap_prototype_settings.gd" % target
	)
	if not FileAccess.file_exists(target):
		return

	var saved: PrototypeSettings = ResourceLoader.load(target, "", ResourceLoader.CACHE_MODE_IGNORE)
	_check("%s [loads]" % label, saved != null, "could not load %s" % target)
	if saved == null:
		return

	var failures := saved.invariant_failures()
	_check("%s [range]" % label, failures.is_empty(), "; ".join(failures))

	_verify_reset(label, saved, defaults)
	_verify_signal(label, saved)
	_verify_roundtrip(label, saved)
	_verify_panel(label, saved)


## RESET has to land back on the knobs consts, whatever the .tres held.
func _verify_reset(label: String, saved: PrototypeSettings, defaults: PrototypeSettings) -> void:
	var probe: PrototypeSettings = saved.duplicate()
	probe.reset()
	var drifted := PackedStringArray()
	for property: Dictionary in defaults.tunable_properties():
		var property_name: StringName = property["name"]
		if probe.get(property_name) != defaults.get(property_name):
			drifted.append(
				(
					"%s reset to %s, expected %s"
					% [property_name, probe.get(property_name), defaults.get(property_name)]
				)
			)
	_check("%s [reset]" % label, drifted.is_empty(), "; ".join(drifted))


## set_value announces exactly once, and says nothing when nothing moved.
##
## A silent set is a slider that moves and does nothing; a set that fires on an
## unchanged value re-applies the whole scene on every mouse-move frame.
func _verify_signal(label: String, saved: PrototypeSettings) -> void:
	var probe: PrototypeSettings = saved.duplicate()
	var tunables := probe.tunable_properties()
	if tunables.is_empty():
		_check("%s [signal]" % label, false, "no tunable properties at all")
		return
	var property: Dictionary = tunables[0]
	var property_name: StringName = property["name"]
	var counter := {"count": 0}
	probe.changed.connect(func() -> void: counter["count"] += 1)

	var current: Variant = probe.get(property_name)
	var moved: Variant = not current if property["type"] == TYPE_BOOL else float(current) + 1.0
	probe.set_value(property_name, moved)
	_check(
		"%s [signal]" % label, counter["count"] == 1, "expected 1 emit, got %s" % counter["count"]
	)
	probe.set_value(property_name, moved)
	_check(
		"%s [signal-idempotent]" % label,
		counter["count"] == 1,
		"re-setting the same value emitted again (%s)" % counter["count"]
	)


## Every tunable property survives a write to disk and a read back.
func _verify_roundtrip(label: String, saved: PrototypeSettings) -> void:
	var probe: PrototypeSettings = saved.duplicate()
	for property: Dictionary in probe.tunable_properties():
		var property_name: StringName = property["name"]
		if property["type"] == TYPE_BOOL:
			probe.set(property_name, not probe.get(property_name))
			continue
		var spec := PrototypeSettings.range_spec(property)
		# Midpoint, so the written value is inside the range whatever it is and
		# differs from a default sitting at either end.
		probe.set(property_name, (float(spec["min"]) + float(spec["max"])) * 0.5)

	var error := ResourceSaver.save(probe, ROUNDTRIP_PATH)
	_check("%s [save]" % label, error == OK, "ResourceSaver: %s" % error_string(error))
	if error != OK:
		return
	var reloaded: PrototypeSettings = ResourceLoader.load(
		ROUNDTRIP_PATH, "", ResourceLoader.CACHE_MODE_IGNORE
	)
	var lost := PackedStringArray()
	for property: Dictionary in probe.tunable_properties():
		var property_name: StringName = property["name"]
		if reloaded.get(property_name) != probe.get(property_name):
			lost.append(
				(
					"%s wrote %s, read back %s"
					% [property_name, probe.get(property_name), reloaded.get(property_name)]
				)
			)
	_check("%s [roundtrip]" % label, lost.is_empty(), "; ".join(lost))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ROUNDTRIP_PATH))


## The panel builds a control per tunable property, and refuses focus on all of
## them - see the FOCUS_NONE docstring on PrototypeTuningPanel for why that one
## matters more than it looks.
func _verify_panel(label: String, saved: PrototypeSettings) -> void:
	var panel := PrototypeTuningPanel.new()
	add_child(panel)
	panel.bind(saved.duplicate())

	var expected := saved.tunable_properties().size()
	var sliders := 0
	var focusable := PackedStringArray()
	for control: Control in _descendants(panel):
		if control is HSlider or control is CheckButton:
			sliders += 1
		if control.focus_mode != Control.FOCUS_NONE:
			focusable.append(control.get_class())
	_check(
		"%s [panel]" % label,
		sliders == expected,
		"%d controls for %d tunable properties" % [sliders, expected]
	)
	_check("%s [focus]" % label, focusable.is_empty(), "focusable: %s" % ", ".join(focusable))
	panel.queue_free()


func _descendants(node: Node) -> Array[Control]:
	var found: Array[Control] = []
	for child in node.get_children():
		if child is Control:
			found.append(child as Control)
		found.append_array(_descendants(child))
	return found


func _check(name: String, passed: bool, detail: String) -> void:
	_checks += 1
	if passed:
		print("  PASS  %s" % name)
		return
	_failures += 1
	printerr("  FAIL  %s: %s" % [name, detail])


func _report() -> void:
	print("%d checks, %d failures" % [_checks, _failures])
	if _checks == 0:
		printerr("no settings resources found - nothing was actually verified")
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failures > 0 else 0)
