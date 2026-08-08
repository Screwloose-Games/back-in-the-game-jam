class_name PrototypeSettings
extends Resource

## The saved half of one prototype's knobs: the values you moved while playing.
##
## THE KNOBS FILE IS STILL WHERE A DEFAULT LIVES. Every property here is declared
##
##     @export_range(<Knobs>.X_MIN, <Knobs>.X_MAX, step) var x: float = <Knobs>.X
##
## so the const IS the property's default and the const pair IS the slider's
## bounds. Nothing is copied - reset() makes a fresh instance and takes its
## values, which is the same thing as re-reading the consts. Edit the knob,
## re-run, press RESET, and the new number is what you get.
##
## That is what the knobs docstrings were protecting when they said there is no
## exported copy that could drift out of sync. There still isn't one. What is
## saved in the .tres is an OVERRIDE, and it only ever covers the handful of
## values a panel puts a slider on.
##
## @export_range IS THE OPT-IN. PrototypeTuningPanel builds a control for every
## ranged numeric and every bool it finds here, and skips everything else. A
## plain `@export var` with no range hint is how a value lives in this resource
## without becoming a slider.

## The usage bits an exported script variable carries, and the whole filter.
## Resource's own resource_path/resource_name are editor properties but not
## script variables; a plain `var` is a script variable but not an editor one.
## Only an @export is both. (Verified against get_property_list(): an @export
## reports 4102, a bare var reports 4096.)
const TUNABLE_USAGE := PROPERTY_USAGE_SCRIPT_VARIABLE | PROPERTY_USAGE_EDITOR


## Where save() writes.
##
## Subclasses override this with their own SAVE_PATH const rather than leaning on
## resource_path, because a prototype that came up on defaults - fresh clone, no
## .tres yet - holds an instance that was never loaded from anywhere and whose
## resource_path is empty. Pressing SAVE in that state should create the file,
## which is the one moment the path cannot be inferred.
func settings_path() -> String:
	return resource_path


## Every property the panel will build a control for, in declaration order.
##
## The panel, reset() and invariant_failures() all come through here, so there is
## one answer to "what is tunable" instead of three that can disagree.
func tunable_properties() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for property: Dictionary in get_property_list():
		var usage: int = property["usage"]
		# Parenthesised on purpose: & binds tighter than != in GDScript, so the
		# bare form is a silent always-true that would return every property.
		if (usage & TUNABLE_USAGE) != TUNABLE_USAGE:
			continue
		var type: int = property["type"]
		if type == TYPE_BOOL:
			found.append(property)
		elif (type == TYPE_FLOAT or type == TYPE_INT) and not range_spec(property).is_empty():
			found.append(property)
	return found


## min/max/step/suffix off an @export_range, or {} if the property has no range.
##
## The hint string is "min,max,step" followed by any number of trailing flags -
## "15.0,75.0,1.0,suffix:deg". Only the first three fields are ever numbers, so
## the parse is positional and guarded by is_valid_float(); a flag that lands in
## one of those slots is skipped rather than read as a bound.
##
## or_greater and or_less are dropped deliberately. A fixed-width debug slider
## cannot express an open-ended range, so the declared maximum is the maximum.
static func range_spec(property: Dictionary) -> Dictionary:
	if int(property["hint"]) != PROPERTY_HINT_RANGE:
		return {}
	var fields := String(property["hint_string"]).split(",", false)
	if fields.size() < 2:
		return {}
	var spec := {"min": 0.0, "max": 1.0, "step": 0.0, "suffix": ""}
	var keys := ["min", "max", "step"]
	for index: int in fields.size():
		var field := fields[index].strip_edges()
		if index < keys.size() and field.is_valid_float():
			spec[keys[index]] = field.to_float()
		elif field.begins_with("suffix:"):
			spec["suffix"] = field.trim_prefix("suffix:")
	return spec


## The only mutator. Sets and announces in one call, because a caller that sets a
## property and forgets to emit produces a slider that moves and does nothing,
## which reads as a broken control rather than a missing signal.
func set_value(property_name: StringName, value: Variant) -> void:
	if get(property_name) == value:
		return
	set(property_name, value)
	emit_changed()


## Back to the knobs consts.
##
## A fresh instance of this same script has never been through a .tres, so every
## property on it still holds its declared initialiser - which is the knob. Copy
## those across and the override layer is empty again.
func reset() -> void:
	var pristine: PrototypeSettings = (get_script() as GDScript).new()
	for property: Dictionary in tunable_properties():
		set(property["name"], pristine.get(property["name"]))
	emit_changed()


## Writes this resource to its own .tres. Returns OK, or the error to show.
func save() -> Error:
	var path := settings_path()
	if path.is_empty():
		push_error("%s has no settings_path(); nothing to save to." % get_script().get_path())
		return ERR_UNCONFIGURED
	if not OS.has_feature("editor"):
		# res:// is inside the PCK once exported. Prototypes are editor-only, so
		# this is a guard rail rather than a case anyone should hit.
		push_warning("res:// is read-only in an exported build; not saving %s." % path)
		return ERR_FILE_CANT_WRITE
	# Default flags. Not FLAG_CHANGE_PATH (it repoints this live instance), not
	# FLAG_BUNDLE_RESOURCES (it would inline the script), and not
	# FLAG_RELATIVE_PATHS - the only external reference these files hold is their
	# own script, and absolute res:// is the form we want committed. The
	# relative-path trap documented in tools/bake_tunnel_mesh.gd does not apply
	# here because nothing under this resource points at a sibling asset.
	var error := ResourceSaver.save(self, path)
	if error != OK:
		push_error("Could not save %s: %s" % [path, error_string(error)])
	return error


## Values that have drifted outside the bounds their own slider declares.
##
## The drift is real: narrow a knob's MIN/MAX pair after someone has saved a
## value near the old edge, and the committed .tres still holds the out-of-range
## number. The slider clamps how it DISPLAYS that, so the panel looks right while
## the prototype keeps applying a value you can no longer dial back to.
##
## Subclasses override to add cross-knob rules and should append to super()'s
## result rather than replace it.
func invariant_failures() -> PackedStringArray:
	var failures := PackedStringArray()
	for property: Dictionary in tunable_properties():
		var spec := range_spec(property)
		if spec.is_empty():
			continue
		var property_name: StringName = property["name"]
		var value := float(get(property_name))
		if value < spec["min"] or value > spec["max"]:
			failures.append(
				(
					"%s is %s, outside its declared range %s..%s"
					% [property_name, value, spec["min"], spec["max"]]
				)
			)
	return failures
