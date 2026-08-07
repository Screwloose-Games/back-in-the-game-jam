class_name TunnelTuningPanel
extends PrototypeTuningPanel

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
## The sliders, RESET and SAVE all come from PrototypeTuningPanel and are built
## from whatever tunnel_settings.gd exports - including the FOCUS_NONE rule,
## which is load-bearing and explained there. What this file adds is the teleport
## grid, which is an action rather than a value and so has no place in the
## settings resource.

var _prototype: TunnelSystemPrototype


## Takes the prototype as well as the settings, because the teleport stops act on
## the world directly and are not a saved value.
func bind_prototype(prototype: TunnelSystemPrototype, settings: TunnelSettings) -> void:
	_prototype = prototype
	bind(settings)


func build_extras(column: VBoxContainer) -> void:
	column.add_child(_heading("JUMP TO  (widest first)"))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	column.add_child(grid)
	for index: int in TunnelKnobs.TELEPORT_STOPS.size():
		grid.add_child(_stop_button(index))

	column.add_child(HSeparator.new())


func help_text() -> String:
	return (
		"ESC frees the mouse to use this panel.\n"
		+ "Jumps arrive at rest, facing down the tunnel.\n"
		+ "View distance moves fog, lamp and clip together.\n"
		+ "SAVE keeps these values in tunnel_settings.tres.\n"
		+ "RESET goes back to tunnel_knobs.gd."
	)


## The lamp angle is stored as a half-angle because that is what SpotLight3D
## wants, but nobody looks at a cone and thinks "45". Report the spread.
func format_value(property_name: StringName, value: Variant, spec: Dictionary) -> String:
	if property_name == &"helmet_lamp_angle":
		return "%.0f deg cone" % (float(value) * 2.0)
	return super.format_value(property_name, value, spec)


func _stop_button(index: int) -> Button:
	var stop: Dictionary = TunnelKnobs.TELEPORT_STOPS[index]
	var button := Button.new()
	button.text = "%s  %s" % [stop["label"], stop["bore"]]
	button.tooltip_text = "%s bore" % stop["bore"]
	button.add_theme_font_size_override("font_size", 11)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# bind(), not a lambda: lambdas capture locals BY VALUE in GDScript, and a
	# loop variable captured that way is a well-known way to wire every button in
	# a grid to the last index.
	button.pressed.connect(_on_stop_pressed.bind(index))
	return _no_focus(button) as Button


func _on_stop_pressed(index: int) -> void:
	if _prototype != null:
		_prototype.jump_to_stop(index)
