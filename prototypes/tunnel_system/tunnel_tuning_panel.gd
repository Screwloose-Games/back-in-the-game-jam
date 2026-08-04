class_name TunnelTuningPanel
extends PanelContainer

## The bottom-left panel: jump between sizes, and retune the optics while flying.
##
## The prototype's core question is comparative - does 2 m feel different from
## 8 m, and how - and a comparison you have to fly four minutes to make is one you
## end up making from memory. These buttons put the two ends of it half a second
## apart.
##
## The sliders are here for the same reason. Draw distance and lamp cone are the
## two numbers most likely to be wrong, and both are far easier to judge by
## dragging until it looks right than by editing a constant and reloading.
##
## Nothing here is saved. Read the values off the labels and put the ones you
## liked into tunnel_knobs.gd.
##
## EVERY CONTROL IN HERE IS FOCUS_NONE, AND THAT IS LOAD-BEARING. A focused
## Button consumes ui_accept - space and enter - whether or not the mouse is
## captured, so the last stop you clicked went on eating SPACE, which is
## thrust_up. You press space to rise and teleport instead. A focused HSlider
## does the same to ui_left/ui_right, i.e. A and D. Neither looks like a UI bug
## from inside the suit; it looks like the controls are broken.
##
## Focus is the only route in, because a captured cursor sits at screen centre
## and cannot click a panel in the corner - so refusing focus outright is the
## whole fix, and it costs only keyboard navigation of a mouse-driven debug panel.

const LABEL_COLOR := Color(0.62, 0.74, 0.86, 0.85)
const HELP_COLOR := Color(0.55, 0.62, 0.70, 0.6)
const DIMMED_ALPHA := 0.35

var _prototype: TunnelSystemPrototype
var _angle_value: Label
var _view_value: Label


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


func bind(prototype: TunnelSystemPrototype) -> void:
	_prototype = prototype
	_build()


func _build() -> void:
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 10)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)

	column.add_child(_heading("JUMP TO  (widest first)"))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	column.add_child(grid)
	for index: int in TunnelKnobs.TELEPORT_STOPS.size():
		grid.add_child(_stop_button(index))

	column.add_child(HSeparator.new())

	_angle_value = _heading("")
	column.add_child(_slider_row("lamp cone", _angle_value))
	var angle := _slider(
		TunnelKnobs.LAMP_ANGLE_MIN, TunnelKnobs.LAMP_ANGLE_MAX, TunnelKnobs.HELMET_LAMP_ANGLE
	)
	angle.value_changed.connect(_on_angle_changed)
	column.add_child(angle)
	_on_angle_changed(TunnelKnobs.HELMET_LAMP_ANGLE)

	_view_value = _heading("")
	column.add_child(_slider_row("view distance", _view_value))
	var view := _slider(
		TunnelKnobs.VIEW_DISTANCE_MIN, TunnelKnobs.VIEW_DISTANCE_MAX, TunnelKnobs.FOG_DEPTH_END
	)
	view.value_changed.connect(_on_view_changed)
	column.add_child(view)
	_on_view_changed(TunnelKnobs.FOG_DEPTH_END)

	column.add_child(HSeparator.new())
	column.add_child(
		_help(
			(
				"ESC frees the mouse to use this panel.\n"
				+ "Jumps arrive at rest, facing down the tunnel.\n"
				+ "View distance moves fog, lamp and clip together.\n"
				+ "Nothing is saved - copy what you like into the knobs."
			)
		)
	)


func _stop_button(index: int) -> Button:
	var stop: Dictionary = TunnelKnobs.TELEPORT_STOPS[index]
	var button := Button.new()
	button.text = "%s  %s" % [stop["label"], stop["bore"]]
	button.tooltip_text = "%s bore" % stop["bore"]
	button.add_theme_font_size_override("font_size", 11)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	# bind(), not a lambda: lambdas capture locals BY VALUE in GDScript, and a
	# loop variable captured that way is a well-known way to wire every button in
	# a grid to the last index.
	button.pressed.connect(_on_stop_pressed.bind(index))
	return button


func _slider_row(caption: String, value_label: Label) -> HBoxContainer:
	var row := HBoxContainer.new()
	var name_label := _heading(caption)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	return row


func _slider(minimum: float, maximum: float, value: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = 1.0
	slider.value = value
	slider.custom_minimum_size = Vector2(0, 16)
	slider.focus_mode = Control.FOCUS_NONE
	return slider


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", LABEL_COLOR)
	label.add_theme_font_size_override("font_size", 11)
	return label


func _help(text: String) -> Label:
	var label := _help_styled()
	label.text = text
	return label


func _help_styled() -> Label:
	var label := Label.new()
	label.add_theme_color_override("font_color", HELP_COLOR)
	label.add_theme_font_size_override("font_size", 10)
	return label


func _on_stop_pressed(index: int) -> void:
	if _prototype != null:
		_prototype.jump_to_stop(index)


func _on_angle_changed(value: float) -> void:
	_angle_value.text = "%.0f deg cone" % (value * 2.0)
	if _prototype != null:
		_prototype.set_lamp_angle(value)


func _on_view_changed(value: float) -> void:
	_view_value.text = "%.0f m" % value
	if _prototype != null:
		_prototype.set_view_distance(value)
