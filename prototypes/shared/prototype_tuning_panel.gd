class_name PrototypeTuningPanel
extends PanelContainer

## A tuning panel built from whatever a PrototypeSettings resource exports.
##
## One slider per ranged number, one switch per bool, in declaration order, plus
## RESET and SAVE. Adding a knob to a prototype's panel is adding an
## @export_range to its settings script - there is no panel code to write per
## value, and no second list of which values are tunable.
##
## RESET returns every value to its knobs const. SAVE writes the .tres, so the
## number you stopped on is still there next run and shows up in git as a diff
## somebody can read.
##
## EVERY CONTROL IN HERE IS FOCUS_NONE, AND THAT IS LOAD-BEARING. A focused
## Button consumes ui_accept - space and enter - whether or not the mouse is
## captured, so the last button you clicked went on eating SPACE, which is
## thrust_up. You press space to rise and teleport instead. A focused HSlider
## does the same to ui_left/ui_right, i.e. A and D. Neither looks like a UI bug
## from inside the suit; it looks like the controls are broken.
##
## Focus is the only route in, because a captured cursor sits at screen centre
## and cannot click a panel in the corner - so refusing focus outright is the
## whole fix, and it costs only keyboard navigation of a mouse-driven debug panel.
##
## This is also why there is no SpinBox for an unranged number. A SpinBox holds a
## LineEdit, a focused LineEdit swallows every key rather than two of them, and
## the failure would look exactly like the game had stopped responding. Unranged
## numbers are skipped and warned about instead.

const LABEL_COLOR := Color(0.62, 0.74, 0.86, 0.85)
const HELP_COLOR := Color(0.55, 0.62, 0.70, 0.6)
const ERROR_COLOR := Color(1.0, 0.55, 0.45, 0.9)
const DIMMED_ALPHA := 0.35
const SLIDER_HEIGHT := 16

var _settings: PrototypeSettings
# Keyed by property name. Untyped Dictionary because gdlint's parser does not
# accept Dictionary[K, V] yet, and the linter is a commit gate.
var _controls := {}
var _value_labels := {}
var _specs := {}
var _status: Label


func _process(_delta: float) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	# The player captures the mouse, so the panel is unclickable until escape
	# releases it. Fading it out is the cheapest way to say so without a line of
	# help text that is wrong half the time.
	modulate.a = DIMMED_ALPHA if captured else 1.0

	# Backstop for the FOCUS_NONE rule in the class docstring. Everything built
	# here refuses focus, so this should never fire - but a control added later
	# without it would silently start eating space, and the symptom shows up as
	# broken flight controls rather than as a panel problem.
	if not captured:
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and is_ancestor_of(focused):
		focused.release_focus()


## Points the panel at the resource it edits and builds the controls.
func bind(settings: PrototypeSettings) -> void:
	_settings = settings
	if not _settings.changed.is_connected(_refresh_controls):
		_settings.changed.connect(_refresh_controls)
	_build()


## Rows a subclass wants above the sliders. Runs first, so the generated controls
## land underneath whatever the prototype adds by hand.
##
## This and the two hooks below are public, not _-prefixed, because gdlint's
## private-method-call rule rejects super._hook() - and an override point a
## subclass cannot chain to is not much of an override point.
func build_extras(_column: VBoxContainer) -> void:
	pass


## The help text at the foot of the panel.
func help_text() -> String:
	return (
		"ESC frees the mouse to use this panel.\n"
		+ "SAVE writes these values to the prototype's .tres.\n"
		+ "RESET goes back to the knobs file defaults."
	)


func _build() -> void:
	for child in get_children():
		child.queue_free()
	_controls.clear()
	_value_labels.clear()
	_specs.clear()

	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 10)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)

	build_extras(column)

	for property: Dictionary in _settings.tunable_properties():
		_add_row(column, property)
	_warn_about_skipped()

	column.add_child(HSeparator.new())

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 4)
	buttons.add_child(_make_button("RESET", _on_reset_pressed))
	buttons.add_child(_make_button("SAVE", _on_save_pressed))
	column.add_child(buttons)

	_status = _help("")
	column.add_child(_status)

	column.add_child(HSeparator.new())
	column.add_child(_help(help_text()))

	_refresh_controls()


func _add_row(column: VBoxContainer, property: Dictionary) -> void:
	var property_name: StringName = property["name"]
	var spec := PrototypeSettings.range_spec(property)
	_specs[property_name] = spec
	var caption := String(property_name).capitalize().to_lower()

	if int(property["type"]) == TYPE_BOOL:
		var toggle := _make_toggle(caption, property_name)
		_controls[property_name] = toggle
		column.add_child(toggle)
		return

	var value_label := _heading("")
	_value_labels[property_name] = value_label
	column.add_child(_slider_row(caption, value_label))
	var slider := _make_slider(property_name, spec)
	_controls[property_name] = slider
	column.add_child(slider)


func _make_slider(property_name: StringName, spec: Dictionary) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = spec["min"]
	slider.max_value = spec["max"]
	# A zero step means "continuous" to Range, which is the right reading of an
	# @export_range that gave only two numbers.
	slider.step = spec["step"]
	slider.custom_minimum_size = Vector2(0, SLIDER_HEIGHT)
	# bind(), not a lambda: lambdas capture locals BY VALUE in GDScript, and a
	# loop variable captured that way is a well-known way to wire every control
	# in a list to the last property. bind() APPENDS, so the signal's own value
	# arrives first and the bound name second.
	slider.value_changed.connect(_on_slider_changed.bind(property_name))
	return _no_focus(slider) as HSlider


func _make_toggle(caption: String, property_name: StringName) -> CheckButton:
	var toggle := CheckButton.new()
	toggle.text = caption
	toggle.add_theme_color_override("font_color", LABEL_COLOR)
	toggle.add_theme_font_size_override("font_size", 11)
	toggle.toggled.connect(_on_toggle_changed.bind(property_name))
	return _no_focus(toggle) as CheckButton


func _make_button(text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 11)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(handler)
	return _no_focus(button) as Button


## The one place focus_mode is set, so a control added later cannot miss it.
func _no_focus(control: Control) -> Control:
	control.focus_mode = Control.FOCUS_NONE
	return control


func _slider_row(caption: String, value_label: Label) -> HBoxContainer:
	var row := HBoxContainer.new()
	var name_label := _heading(caption)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	return row


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", LABEL_COLOR)
	label.add_theme_font_size_override("font_size", 11)
	return label


func _help(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", HELP_COLOR)
	label.add_theme_font_size_override("font_size", 10)
	return label


## How a value reads next to its slider. Overridable for the cases where the
## stored number is not the number a player thinks in.
func format_value(_property_name: StringName, value: Variant, spec: Dictionary) -> String:
	var step := float(spec.get("step", 0.0))
	var decimals := 0
	if step > 0.0 and step < 1.0:
		decimals = clampi(int(ceil(-log(step) / log(10.0))), 1, 5)
	var text := String.num(float(value), decimals)
	var suffix := String(spec.get("suffix", ""))
	return text if suffix.is_empty() else "%s %s" % [text, suffix]


## Pushes the resource's values back into the controls.
##
## Connected to Resource.changed, so it covers RESET and anything else that moves
## a value out from under the panel. The no_signal setters are what keep that
## from becoming a loop: the plain ones would re-emit value_changed, write the
## resource, emit changed, and land back here.
func _refresh_controls() -> void:
	if _settings == null:
		return
	for property_name: StringName in _controls:
		var control: Control = _controls[property_name]
		var value: Variant = _settings.get(property_name)
		if control is CheckButton:
			(control as CheckButton).set_pressed_no_signal(bool(value))
			continue
		(control as HSlider).set_value_no_signal(float(value))
		var label := _value_labels.get(property_name) as Label
		if label != null:
			label.text = format_value(property_name, value, _specs[property_name])


## Exported values the panel could not build a control for.
##
## Silence here would read as "that knob isn't saved yet" when the truth is
## "that knob has no @export_range", so it is worth one warning at startup.
func _warn_about_skipped() -> void:
	var built := PackedStringArray()
	for property: Dictionary in _settings.tunable_properties():
		built.append(String(property["name"]))
	var skipped := PackedStringArray()
	for property: Dictionary in _settings.get_property_list():
		var usage: int = property["usage"]
		if (usage & PrototypeSettings.TUNABLE_USAGE) != PrototypeSettings.TUNABLE_USAGE:
			continue
		if String(property["name"]) not in built:
			skipped.append(String(property["name"]))
	if not skipped.is_empty():
		push_warning(
			(
				"%s: no control for %s - a number needs @export_range to get a slider."
				% [_settings.get_script().get_path().get_file(), ", ".join(skipped)]
			)
		)


func _set_status(text: String, failed: bool) -> void:
	if _status == null:
		return
	_status.text = text
	_status.add_theme_color_override("font_color", ERROR_COLOR if failed else HELP_COLOR)


func _on_slider_changed(value: float, property_name: StringName) -> void:
	_settings.set_value(property_name, value)
	_set_status("", false)


func _on_toggle_changed(pressed: bool, property_name: StringName) -> void:
	_settings.set_value(property_name, pressed)
	_set_status("", false)


func _on_reset_pressed() -> void:
	_settings.reset()
	_set_status("reset to knobs defaults - not saved", false)


func _on_save_pressed() -> void:
	var error := _settings.save()
	if error == OK:
		_set_status("saved %s" % _settings.settings_path().get_file(), false)
		return
	_set_status("SAVE FAILED: %s" % error_string(error), true)
