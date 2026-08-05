class_name PowerTuningPanel
extends PanelContainer

## The bottom-left panel: every lighting and power number, live, while flying.
##
## This prototype exists to settle values that cannot be settled by reading them.
## What shape a beam should be, how hard its edge should be, how far it should
## carry - all of those are judged by looking at the screen, and a judgement that
## costs an edit and a reload gets made from memory instead of from the screen.
## So they are all on sliders.
##
## THE PANEL BUILDS ONLY WHAT IS SWITCHED ON, and every section is gated on a
## constant in PowerKnobs' What is switched on region: BEAM and ROOM on
## SUIT_BEAM_TUNING_ENABLED, SUIT RESPONSE on SUIT_RESPONSE_TUNING_ENABLED, CUBE
## LAMP and CUBE RESPONSE on CUBE_TUNING_ENABLED, the POWER sliders on
## POWER_TUNING_ENABLED, and the state buttons on POWER_ENABLED.
##
## The state buttons are gated apart from the POWER sliders on purpose. They are
## not tuning - they put a battery where you want to look at it - so they outlive
## the section whose numbers they were first there to serve.
##
## Two different reasons to hide a section, and both matter. A slider that moves a
## number nothing is reading is worse than a missing one, because it costs a drag
## and a squint at the screen before it says so. And a slider over a value that is
## already settled invites re-opening an answered question every time the panel is
## opened for something else.
##
## Nothing here is saved. Read the values off the labels and put the ones you
## liked into power_knobs.gd.
##
## THE WHOLE COLUMN SITS IN A SCROLL VIEW, capped at the room left on screen above
## the panel's own corner - see _fit_to_window. Two sections of sliders and two
## curve editors are already taller than a window, and a control that has run off
## the top of the screen is worse than a missing one: it is there, it is doing
## something, and there is no way to find out what.
##
## EVERY CONTROL IN HERE IS FOCUS_NONE, AND THAT IS LOAD-BEARING. A focused
## Button consumes ui_accept - space and enter - whether or not the mouse is
## captured, so the last button you clicked goes on eating SPACE, which is
## thrust_up. You press space to rise and reset the batteries instead. A focused
## HSlider does the same to ui_left/ui_right, i.e. A and D. Neither looks like a
## UI bug from inside the suit; it looks like the controls are broken.
##
## Focus is the only route in, because a captured cursor sits at screen centre
## and cannot click a panel in the corner - so refusing focus outright is the
## whole fix, and it costs only keyboard navigation of a mouse-driven debug
## panel.

const LABEL_COLOR := Color(0.62, 0.74, 0.86, 0.85)
const HEADING_COLOR := Color(0.86, 0.9, 0.96, 0.9)
const HELP_COLOR := Color(0.55, 0.62, 0.70, 0.6)
const DIMMED_ALPHA := 0.35

## How much of the screen the panel leaves alone above itself, in pixels.
##
## The HUD readout lives up there and is left-aligned too, so a panel allowed to
## grow the full height of the window would print sliders over the flight numbers
## rather than run out of room honestly.
const RESERVED_TOP := 300.0

## The gap kept at the bottom, matching the panel's own offset in the .tscn.
const RESERVED_BOTTOM := 16.0

## How short the panel is allowed to get on a small window. Below this it stops
## shrinking and simply overlaps whatever is above it - a scroll view two sliders
## tall is not usable, and a window that small is not what this is for.
const MINIMUM_HEIGHT := 140.0

## One-click states, as the fraction to put each store at. -1.0 leaves a store
## alone.
const STATE_BUTTONS := [
	{"label": "Suit to 10%", "suit": 0.1, "cube": -1.0},
	{"label": "Suit empty", "suit": 0.0, "cube": -1.0},
	{"label": "Cube empty", "suit": -1.0, "cube": 0.0},
	{"label": "Refill both", "suit": 1.0, "cube": 1.0},
]

var _prototype: PowerAndLightingPrototype
var _column: VBoxContainer
var _scroll: ScrollContainer

## The lamp colour is two sliders that have to be recombined into one Color, so
## both values are kept rather than read back off the controls.
var _lamp_hue := 0.0
var _lamp_saturation := 0.0

## The cube's, kept apart from the suit's because both sections can be up at once
## and one pair of fields would have the second section built overwrite the first.
var _cube_hue := 0.0
var _cube_saturation := 0.0

## The shadow artefact controls go to the prototype together for the same reason,
## a toggle and a slider rather than two sliders. Seeded from the knobs here
## rather than in the build: a CheckButton emits nothing when its state is set
## before it is connected, so the toggle never gets a chance to say what it is.
var _shadow_normal_bias := PowerKnobs.SHADOW_NORMAL_BIAS
var _shadow_reverse_cull := PowerKnobs.SHADOW_REVERSE_CULL


func _process(_delta: float) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	# The suit captures the mouse, so the panel is unclickable until escape
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


func bind(prototype: PowerAndLightingPrototype) -> void:
	_prototype = prototype
	_build()


func _build() -> void:
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 10)
	add_child(margin)

	_scroll = _build_scroll()
	margin.add_child(_scroll)

	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 4)
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_column)

	if PowerKnobs.POWER_ENABLED:
		_add_section(_build_state_row)
	if PowerKnobs.SUIT_BEAM_TUNING_ENABLED:
		_add_section(_build_beam_section)
		_add_section(_build_room_section)
	if PowerKnobs.LAMP_RESPONDS_TO_POWER and PowerKnobs.SUIT_RESPONSE_TUNING_ENABLED:
		_add_section(_build_response_section.bind("SUIT", _prototype.get_suit_lamp()))
	if PowerKnobs.CUBE_LIGHT_ENABLED and PowerKnobs.CUBE_TUNING_ENABLED:
		_add_section(_build_cube_lamp_section)
		if PowerKnobs.LAMP_RESPONDS_TO_POWER:
			_add_section(_build_response_section.bind("CUBE", _prototype.get_cube_lamp()))
	if PowerKnobs.POWER_ENABLED and PowerKnobs.POWER_TUNING_ENABLED:
		_add_section(_build_power_section)
	_add_section(_build_help)

	_fit_to_window()
	# Both matter. The window can be resized under a built panel, and the column's
	# own minimum can settle a frame or two late once the font has measured its
	# labels - a height taken only once at build would be wrong in both cases.
	get_viewport().size_changed.connect(_fit_to_window)
	_column.minimum_size_changed.connect(_fit_to_window)


## A scroll view sized to the content until the content is taller than the room
## available, and scrolling past that point.
##
## Horizontal scrolling is DISABLED rather than automatic, which is also what
## keeps the panel as wide as its widest slider: a ScrollContainer reports its
## child's minimum size only on the axes it is not scrolling. Vertical is left
## automatic for the same reason in reverse - it must not report the column's full
## height, or the panel would grow to it and there would be nothing to scroll.
func _build_scroll() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.focus_mode = Control.FOCUS_NONE
	# The scrollbar is a control on this panel like any other, and the rule in the
	# class docstring is not softer for being about a bar nobody clicks on purpose.
	scroll.get_v_scroll_bar().focus_mode = Control.FOCUS_NONE
	scroll.get_h_scroll_bar().focus_mode = Control.FOCUS_NONE
	return scroll


## Caps the scroll view at the room left on screen, and lets it be shorter than
## that when the content is.
##
## The height is set on the SCROLL VIEW rather than on the panel, so the panel
## goes on sizing itself to its contents and simply has smaller contents. Setting
## it on the panel would leave a full-height slab of background whatever was in it.
func _fit_to_window() -> void:
	var available := get_viewport_rect().size.y - RESERVED_TOP - RESERVED_BOTTOM
	var wanted := _column.get_combined_minimum_size().y
	_scroll.custom_minimum_size.y = maxf(minf(wanted, available), MINIMUM_HEIGHT)


## Adds one section, with a rule above it unless it is the first thing in the
## panel. Every section goes through here so that none of them carries its own
## separator: a section that did would leave a rule hanging at the top of the
## panel, or two rules together, whenever whatever used to be above it was
## switched off.
func _add_section(builder: Callable) -> void:
	if _column.get_child_count() > 0:
		_column.add_child(HSeparator.new())
	builder.call()


## Only the lines that describe something on the screen. Help text for a slider
## that is not there is how a panel starts lying about what it does.
func _build_help() -> void:
	var lines := PackedStringArray(["ESC frees the mouse to use this panel."])
	if not PowerKnobs.POWER_ENABLED:
		lines.append("Power is off - both batteries are full and stay full.")
	elif not PowerKnobs.POWER_TUNING_ENABLED:
		lines.append("T to charge, hold F to crank. Both rates are settled.")
	if PowerKnobs.SUIT_BEAM_TUNING_ENABLED:
		lines.append("View distance moves fog, lamp throw and clip together.")
		lines.append("Reverse cull and normal bias answer the shadow stripes.")
	if PowerKnobs.CUBE_TUNING_ENABLED:
		lines.append("The helmet lamp is settled - judge the cube against it.")
		lines.append("Hue and glow share a colour, so the cube looks like its own")
		lines.append("light source rather than a box lit by something else.")
	if PowerKnobs.LAMP_RESPONDS_TO_POWER:
		lines.append("Click a curve to add a point, drag it, right-click to drop.")
		lines.append("A dim curve's left end is what an empty battery is left with.")
		lines.append("Zero there is the lamp going out; just above is a reserve.")
		lines.append("Dropouts are Poisson, so the gaps are meant to be uneven.")
	lines.append("Nothing is saved - print the curves, copy the rest off the labels.")
	_column.add_child(_help("\n".join(lines)))


func _build_state_row() -> void:
	_column.add_child(_heading("JUMP TO A STATE"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	_column.add_child(grid)
	for index: int in STATE_BUTTONS.size():
		grid.add_child(_state_button(index))


## The lamp itself: what shape the light is and what colour.
func _build_beam_section() -> void:
	_column.add_child(_heading("BEAM"))
	_add_slider(
		"cone",
		PowerKnobs.LAMP_ANGLE_MIN,
		PowerKnobs.LAMP_ANGLE_MAX,
		PowerKnobs.HELMET_LAMP_ANGLE,
		1.0,
		_on_cone_changed
	)
	# Two falloffs, and they are not interchangeable however alike the labels
	# read. The edge one decides whether the cone has a rim you can see; the
	# distance one decides how far into the room the beam is still doing work.
	_add_slider(
		"edge falloff",
		PowerKnobs.LAMP_EDGE_FALLOFF_MIN,
		PowerKnobs.LAMP_EDGE_FALLOFF_MAX,
		PowerKnobs.HELMET_LAMP_ANGLE_ATTENUATION,
		0.05,
		_on_edge_falloff_changed
	)
	_add_slider(
		"distance falloff",
		PowerKnobs.LAMP_DISTANCE_FALLOFF_MIN,
		PowerKnobs.LAMP_DISTANCE_FALLOFF_MAX,
		PowerKnobs.HELMET_LAMP_ATTENUATION,
		0.05,
		_on_distance_falloff_changed
	)
	_add_slider(
		"brightness",
		PowerKnobs.LAMP_ENERGY_MIN,
		PowerKnobs.LAMP_ENERGY_MAX,
		PowerKnobs.HELMET_LAMP_ENERGY,
		0.1,
		_on_brightness_changed
	)

	_lamp_hue = PowerKnobs.HELMET_LAMP_COLOR.h
	_lamp_saturation = PowerKnobs.HELMET_LAMP_COLOR.s
	_add_slider(
		"hue", PowerKnobs.LAMP_HUE_MIN, PowerKnobs.LAMP_HUE_MAX, _lamp_hue, 0.01, _on_hue_changed
	)
	_add_slider(
		"saturation",
		PowerKnobs.LAMP_SATURATION_MIN,
		PowerKnobs.LAMP_SATURATION_MAX,
		_lamp_saturation,
		0.01,
		_on_saturation_changed
	)
	# The last three are shadow controls rather than beam controls, and the two
	# artefact ones only mean anything while the first is on. They live in BEAM
	# because a section of their own would imply there is something to tune here,
	# and there is not - see the Shadow artefacts region in power_knobs.gd.
	_column.add_child(_shadow_toggle(_prototype.get_suit_lamp(), PowerKnobs.HELMET_LAMP_SHADOWS))
	_column.add_child(_reverse_cull_toggle())
	_add_slider(
		"normal bias",
		PowerKnobs.SHADOW_NORMAL_BIAS_MIN,
		PowerKnobs.SHADOW_NORMAL_BIAS_MAX,
		PowerKnobs.SHADOW_NORMAL_BIAS,
		0.5,
		_on_shadow_normal_bias_changed
	)


## What the light is falling through and landing on. These belong next to the
## beam sliders rather than in a section of their own: doubling the fog does more
## to how a cone reads than most of what can be done to the cone.
func _build_room_section() -> void:
	_column.add_child(_heading("ROOM"))
	_add_slider(
		"view distance",
		PowerKnobs.VIEW_DISTANCE_MIN,
		PowerKnobs.VIEW_DISTANCE_MAX,
		PowerKnobs.FOG_DEPTH_END,
		1.0,
		_on_view_distance_changed
	)
	_add_slider(
		"fog begins",
		PowerKnobs.FOG_BEGIN_MIN,
		PowerKnobs.FOG_BEGIN_MAX,
		PowerKnobs.FOG_DEPTH_BEGIN,
		0.5,
		_on_fog_begin_changed
	)
	_add_slider(
		"fog density",
		PowerKnobs.FOG_DENSITY_MIN,
		PowerKnobs.FOG_DENSITY_MAX,
		PowerKnobs.FOG_DENSITY,
		0.05,
		_on_fog_density_changed
	)
	_add_slider(
		"ambient",
		PowerKnobs.AMBIENT_MIN,
		PowerKnobs.AMBIENT_MAX,
		PowerKnobs.AMBIENT_ENERGY,
		0.005,
		_on_ambient_changed
	)


## The cube's lamp: the same decisions the helmet lamp has already made, for a
## light that is carried rather than worn.
##
## No cone and no edge falloff - it is an omni light and has neither. What it has
## instead is a glow, because the cube is the only light source in this game you
## can also look at.
func _build_cube_lamp_section() -> void:
	_column.add_child(_heading("CUBE LAMP"))
	var response := _prototype.get_cube_lamp()
	_add_slider(
		"brightness",
		PowerKnobs.CUBE_ENERGY_MIN,
		PowerKnobs.CUBE_ENERGY_MAX,
		response.base_energy,
		0.1,
		_on_cube_energy_changed
	)
	_add_slider(
		"throw",
		PowerKnobs.CUBE_RANGE_MIN,
		PowerKnobs.CUBE_RANGE_MAX,
		response.base_range,
		0.5,
		_on_cube_range_changed
	)
	_add_slider(
		"distance falloff",
		PowerKnobs.LAMP_DISTANCE_FALLOFF_MIN,
		PowerKnobs.LAMP_DISTANCE_FALLOFF_MAX,
		PowerKnobs.CUBE_LIGHT_ATTENUATION,
		0.05,
		_on_cube_falloff_changed
	)

	_cube_hue = PowerKnobs.CUBE_LIGHT_COLOR.h
	_cube_saturation = PowerKnobs.CUBE_LIGHT_COLOR.s
	_add_slider(
		"hue",
		PowerKnobs.LAMP_HUE_MIN,
		PowerKnobs.LAMP_HUE_MAX,
		_cube_hue,
		0.01,
		_on_cube_hue_changed
	)
	_add_slider(
		"saturation",
		PowerKnobs.LAMP_SATURATION_MIN,
		PowerKnobs.CUBE_SATURATION_MAX,
		_cube_saturation,
		0.01,
		_on_cube_saturation_changed
	)
	_add_slider(
		"glow",
		PowerKnobs.CUBE_GLOW_MIN,
		PowerKnobs.CUBE_GLOW_MAX,
		PowerKnobs.CUBE_GLOW,
		0.1,
		_on_cube_glow_changed
	)
	_column.add_child(_shadow_toggle(response, PowerKnobs.CUBE_LIGHT_SHADOWS))


## How one lamp answers its battery. Built for either lamp, because both run the
## same code on their own curves and the panel that tunes them should be the same
## code too - right down to the print button, which names the constants of
## whichever lamp it was built for.
##
## The two curves are handed to the editors LIVE - the editors mutate the same
## resources the response samples every frame, so a drag shows on the lamp before
## the mouse button comes up. Nothing here connects them; that is the point.
func _build_response_section(label: String, response: LampPowerResponse) -> void:
	_column.add_child(_heading("%s RESPONSE" % label))
	_column.add_child(_caption("dim   charge -> brightness"))
	_column.add_child(_curve_editor(response.dim_curve, ""))
	_column.add_child(_caption("flicker   charge -> dropouts/s"))
	_column.add_child(_curve_editor(response.flicker_curve, "/s"))

	_add_slider(
		"flicker rate",
		PowerKnobs.FLICKER_SCALE_MIN,
		PowerKnobs.FLICKER_SCALE_MAX,
		response.flicker_scale,
		0.1,
		_on_flicker_scale_changed.bind(response)
	)
	_add_slider(
		"empty throw",
		PowerKnobs.RANGE_FLOOR_MIN,
		PowerKnobs.RANGE_FLOOR_MAX,
		response.min_range_fraction,
		0.01,
		_on_empty_throw_changed.bind(response)
	)
	_column.add_child(_print_button(label, response))


func _build_power_section() -> void:
	_column.add_child(_heading("POWER"))
	_add_slider(
		"suit capacity",
		PowerKnobs.SUIT_CAPACITY_MIN,
		PowerKnobs.SUIT_CAPACITY_MAX,
		PowerKnobs.SUIT_CAPACITY,
		5.0,
		_on_suit_capacity_changed
	)
	_add_slider(
		"suit drain /s",
		PowerKnobs.SUIT_DRAIN_MIN,
		PowerKnobs.SUIT_DRAIN_MAX,
		PowerKnobs.SUIT_DRAIN_PER_SECOND,
		0.05,
		_on_suit_drain_changed
	)
	_add_slider(
		"tether charge /s",
		PowerKnobs.CHARGE_RATE_MIN,
		PowerKnobs.CHARGE_RATE_MAX,
		PowerKnobs.SUIT_CHARGE_PER_SECOND,
		0.1,
		_on_charge_rate_changed
	)
	_add_slider(
		"cube capacity",
		PowerKnobs.CUBE_CAPACITY_MIN,
		PowerKnobs.CUBE_CAPACITY_MAX,
		PowerKnobs.CUBE_CAPACITY,
		20.0,
		_on_cube_capacity_changed
	)
	_add_slider(
		"crank /s",
		PowerKnobs.CRANK_RATE_MIN,
		PowerKnobs.CRANK_RATE_MAX,
		PowerKnobs.CRANK_PER_SECOND,
		0.5,
		_on_crank_rate_changed
	)


## One labelled slider: caption and live value on one row, the track under it.
##
## The handler is called once here with the starting value, so the label reads
## correctly before anything is dragged and every setter has run at least once -
## which is what keeps the panel and the knobs from disagreeing on frame one.
func _add_slider(
	caption: String, minimum: float, maximum: float, value: float, step: float, handler: Callable
) -> void:
	var value_label := _value_label()
	_column.add_child(_slider_row(caption, value_label))

	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(190, 14)
	slider.focus_mode = Control.FOCUS_NONE
	# The wheel belongs to the scroll view now, and it takes BOTH of these to get
	# it there. `scrollable` off stops the slider nudging its own value, which on a
	# panel this size would mis-tune every slider the pointer crossed on the way
	# down - silently, because the value moves under a pointer that was never
	# aiming at it. MOUSE_FILTER_PASS is what lets the event carry on up to the
	# scroll view afterwards: a control left on STOP ends the walk up the tree, so
	# the wheel would simply do nothing over most of the panel.
	slider.scrollable = false
	slider.mouse_filter = Control.MOUSE_FILTER_PASS
	# bind(), not a lambda: lambdas capture locals BY VALUE in GDScript, and a
	# local captured that way is a well-known way to wire every slider in a
	# column to the last label built.
	slider.value_changed.connect(_on_slider_changed.bind(handler, value_label))
	_column.add_child(slider)

	_on_slider_changed(value, handler, value_label)


func _on_slider_changed(value: float, handler: Callable, value_label: Label) -> void:
	value_label.text = handler.call(value)


func _state_button(index: int) -> Button:
	var state: Dictionary = STATE_BUTTONS[index]
	var button := Button.new()
	button.text = state["label"]
	button.add_theme_font_size_override("font_size", 11)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(_on_state_pressed.bind(index))
	return button


func _on_state_pressed(index: int) -> void:
	if _prototype == null:
		return
	var state: Dictionary = STATE_BUTTONS[index]
	_prototype.set_store_fractions(state["suit"], state["cube"])


# --- Slider handlers -------------------------------------------------------
#
# Each returns the text its own label should show, so the unit a number is
# argued about in lives next to the setter that applies it rather than in a
# parallel table that can drift.


func _on_cone_changed(value: float) -> String:
	_prototype.get_suit_lamp().set_cone(value)
	# The knob is a half-angle and the label is the full spread, because the
	# spread is what anyone arguing about a beam actually means.
	return "%.0f deg" % (value * 2.0)


func _on_edge_falloff_changed(value: float) -> String:
	_prototype.get_suit_lamp().set_edge_falloff(value)
	return "hard edge" if value <= 0.0 else "%.2f" % value


func _on_distance_falloff_changed(value: float) -> String:
	_prototype.get_suit_lamp().set_distance_falloff(value)
	return "%.2f" % value


func _on_shadows_toggled(enabled: bool, response: LampPowerResponse) -> void:
	response.set_shadows(enabled)


func _on_reverse_cull_toggled(enabled: bool) -> void:
	_shadow_reverse_cull = enabled
	_push_shadow_artefact_knobs()


func _on_shadow_normal_bias_changed(value: float) -> String:
	_shadow_normal_bias = value
	_push_shadow_artefact_knobs()
	return "off" if value <= 0.0 else "%.1f texels" % value


func _push_shadow_artefact_knobs() -> void:
	if _prototype != null:
		_prototype.set_shadow_artefact_knobs(_shadow_normal_bias, _shadow_reverse_cull)


func _on_fog_begin_changed(value: float) -> String:
	if _prototype != null:
		_prototype.set_fog_begin(value)
	return "%.1f m" % value


func _on_fog_density_changed(value: float) -> String:
	if _prototype != null:
		_prototype.set_fog_density(value)
	return "clear" if value <= 0.0 else "%.2f" % value


func _on_ambient_changed(value: float) -> String:
	if _prototype != null:
		_prototype.set_ambient_energy(value)
	return "black" if value <= 0.0 else "%.3f" % value


func _on_brightness_changed(value: float) -> String:
	_prototype.get_suit_lamp().base_energy = value
	return "%.1f" % value


func _on_view_distance_changed(value: float) -> String:
	if _prototype != null:
		_prototype.set_view_distance(value)
	return "%.0f m" % value


func _on_hue_changed(value: float) -> String:
	_lamp_hue = value
	_push_lamp_color()
	return "%.2f" % value


func _on_saturation_changed(value: float) -> String:
	_lamp_saturation = value
	_push_lamp_color()
	return "%.2f" % value


## Value is pinned at 1.0: the lamp's brightness is its own slider, and letting
## the colour carry brightness too makes the two fight and makes a dark lamp
## impossible to tell from a black one.
func _push_lamp_color() -> void:
	_prototype.get_suit_lamp().set_color(Color.from_hsv(_lamp_hue, _lamp_saturation, 1.0))


func _on_cube_energy_changed(value: float) -> String:
	_prototype.get_cube_lamp().base_energy = value
	return "out" if value <= 0.0 else "%.1f" % value


func _on_cube_range_changed(value: float) -> String:
	_prototype.get_cube_lamp().base_range = value
	# Against the view distance, because a cube reaching past where you can see is
	# a cube spending power on fog.
	return "%.1f m of %.0f" % [value, PowerKnobs.FOG_DEPTH_END]


func _on_cube_falloff_changed(value: float) -> String:
	_prototype.get_cube_lamp().set_distance_falloff(value)
	return "%.2f" % value


func _on_cube_hue_changed(value: float) -> String:
	_cube_hue = value
	_push_cube_color()
	return "%.2f" % value


func _on_cube_saturation_changed(value: float) -> String:
	_cube_saturation = value
	_push_cube_color()
	return "white" if value <= 0.0 else "%.2f" % value


## Through the prototype rather than the response, unlike every other thing the
## cube's lamp looks like: this colour is the cube's glow as well as its light.
func _push_cube_color() -> void:
	_prototype.set_cube_light_color(Color.from_hsv(_cube_hue, _cube_saturation, 1.0))


func _on_cube_glow_changed(value: float) -> String:
	_prototype.set_cube_glow(value)
	return "dark" if value <= 0.0 else "%.1f" % value


## Per lamp, not global. Each one has its own flicker curve now, and a single
## multiplier over both would mean turning the suit's dropouts off to look at the
## cube's - which is exactly the comparison worth keeping.
func _on_flicker_scale_changed(value: float, response: LampPowerResponse) -> String:
	response.flicker_scale = value
	return "off" if value <= 0.0 else "%.1fx" % value


## Labelled in metres rather than as a fraction, because the question is whether
## you can still see the wall in front of you and nobody thinks in fractions of a
## throw. Off the response's live base_range, so the label stays honest if the
## throw above it is being dragged at the same time.
func _on_empty_throw_changed(value: float, response: LampPowerResponse) -> String:
	response.min_range_fraction = value
	return "%.1f m" % (value * response.base_range)


## The curve equivalent of reading a value off a slider's label. Nothing on this
## panel is saved, and a shape dragged out over five minutes cannot be read off
## the screen and retyped the way one number can - so the only way it survives the
## session is as source, printed in the shape of the constants it replaces.
func _on_print_pressed(label: String, response: LampPowerResponse) -> void:
	print(_describe_curve("%s_DIM_POINTS" % label, response.dim_curve))
	print(_describe_curve("%s_FLICKER_POINTS" % label, response.flicker_curve))


func _describe_curve(constant_name: String, curve: Curve) -> String:
	var lines := PackedStringArray(["const %s: Array[Vector2] = [" % constant_name])
	for index: int in curve.point_count:
		var point := curve.get_point_position(index)
		lines.append("\tVector2(%.3f, %.3f)," % [point.x, point.y])
	lines.append("]")
	return "\n".join(lines)


func _on_suit_capacity_changed(value: float) -> String:
	if _prototype != null:
		_prototype.set_suit_capacity(value)
	return "%.0f" % value


func _on_suit_drain_changed(value: float) -> String:
	if _prototype != null:
		_prototype.set_suit_drain(value)
	return "%.2f" % value


func _on_charge_rate_changed(value: float) -> String:
	if _prototype != null:
		_prototype.set_charge_rate(value)
	return "%.1f" % value


func _on_cube_capacity_changed(value: float) -> String:
	if _prototype != null:
		_prototype.set_cube_capacity(value)
	return "%.0f" % value


func _on_crank_rate_changed(value: float) -> String:
	if _prototype != null:
		_prototype.set_crank_rate(value)
	return "%.1f" % value


# --- Widgets ---------------------------------------------------------------


## A CheckButton rather than a slider, because shadows are a yes or a no and a
## slider that only has two positions is a worse button. FOCUS_NONE for the same
## reason as everything else in here - see the class docstring.
func _shadow_toggle(response: LampPowerResponse, enabled: bool) -> CheckButton:
	var toggle := CheckButton.new()
	toggle.text = "shadows"
	toggle.button_pressed = enabled
	toggle.add_theme_font_size_override("font_size", 11)
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.toggled.connect(_on_shadows_toggled.bind(response))
	return toggle


## Wider than a slider row on purpose: a curve is dragged in two dimensions and a
## point placed inside a 14-pixel strip cannot be placed accurately in the one
## that matters.
func _curve_editor(curve: Curve, units: String) -> LampCurveEditor:
	var editor := LampCurveEditor.new()
	editor.custom_minimum_size = Vector2(190, 84)
	editor.focus_mode = Control.FOCUS_NONE
	editor.bind(curve, units)
	return editor


func _print_button(label: String, response: LampPowerResponse) -> Button:
	var button := Button.new()
	button.text = "Print %s curves" % label.to_lower()
	button.add_theme_font_size_override("font_size", 11)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(_on_print_pressed.bind(label, response))
	return button


## Neither this nor the normal bias slider next to it is worth a drag until the
## stripes are on the screen: both exist to answer the Compatibility renderer's
## shadow artefacts, and off is what the artefact looks like.
func _reverse_cull_toggle() -> CheckButton:
	var toggle := CheckButton.new()
	toggle.text = "reverse cull"
	toggle.button_pressed = PowerKnobs.SHADOW_REVERSE_CULL
	toggle.add_theme_font_size_override("font_size", 11)
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.toggled.connect(_on_reverse_cull_toggled)
	return toggle


func _slider_row(caption: String, value_label: Label) -> HBoxContainer:
	var row := HBoxContainer.new()
	var name_label := _label(caption, LABEL_COLOR, 11)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	row.add_child(value_label)
	return row


func _value_label() -> Label:
	var label := _label("", LABEL_COLOR, 11)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return label


func _heading(text: String) -> Label:
	return _label(text, HEADING_COLOR, 11)


func _caption(text: String) -> Label:
	return _label(text, LABEL_COLOR, 10)


func _help(text: String) -> Label:
	return _label(text, HELP_COLOR, 10)


func _label(text: String, color: Color, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	return label
