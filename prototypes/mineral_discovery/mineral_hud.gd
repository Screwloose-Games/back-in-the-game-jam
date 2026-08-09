class_name MineralHud
extends CanvasLayer

## The playtester's readout: a text panel, a crosshair, an extraction bar, and
## the proximity-marker overlay Q4 is about.
##
## The markers are the interesting part. Each non-mined deposit within the tuned
## proximity gets a dot on screen, coloured by whether it sits inside the tether's
## reach of the buoy (green) or past it (amber) - so the "can I get there on the
## leash?" question is answered at a glance. Toggling them off is how a tester
## feels the see-and-decide loop without the assist. Everything reads its state
## off the prototype root each frame; the HUD owns none of the truth.

const REACHABLE_COLOR := Color(0.5, 0.9, 0.55, 0.9)
const RISKY_COLOR := Color(0.95, 0.7, 0.35, 0.9)
const TARGET_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const MARKER_RADIUS := 5.0

var _prototype: MineralDiscoveryPrototype
var _readout: Label
var _marker_layer: Control
var _extract_back: ColorRect
var _extract_fill: ColorRect
var _font: Font


## Points the HUD at the root it reads and builds its controls.
func bind(prototype: MineralDiscoveryPrototype) -> void:
	_prototype = prototype
	_font = ThemeDB.fallback_font
	_build_ui()


func _process(_delta: float) -> void:
	if _prototype == null:
		return
	_readout.text = _compose_readout()
	_update_extract_bar()
	_marker_layer.queue_redraw()


func _build_ui() -> void:
	_readout = Label.new()
	_readout.position = Vector2(16.0, 12.0)
	_readout.add_theme_color_override("font_color", Color(0.72, 0.84, 0.96, 0.9))
	_readout.add_theme_font_size_override("font_size", 14)
	add_child(_readout)

	var crosshair := ColorRect.new()
	crosshair.color = Color(0.78, 0.88, 1.0, 0.55)
	crosshair.size = Vector2(4.0, 4.0)
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position = -crosshair.size * 0.5
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(crosshair)

	_build_extract_bar()

	_marker_layer = Control.new()
	_marker_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_marker_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker_layer.draw.connect(_draw_markers)
	add_child(_marker_layer)


## A slim bar just under the crosshair, shown only while an extraction is running.
func _build_extract_bar() -> void:
	_extract_back = ColorRect.new()
	_extract_back.color = Color(0.1, 0.12, 0.15, 0.7)
	_extract_back.size = Vector2(160.0, 8.0)
	_extract_back.set_anchors_preset(Control.PRESET_CENTER)
	_extract_back.position = Vector2(-80.0, 24.0)
	_extract_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_extract_back.visible = false
	add_child(_extract_back)

	_extract_fill = ColorRect.new()
	_extract_fill.color = Color(0.55, 0.9, 0.6, 0.95)
	_extract_fill.position = Vector2.ZERO
	_extract_fill.size = Vector2(0.0, 8.0)
	_extract_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_extract_back.add_child(_extract_fill)


func _update_extract_bar() -> void:
	var fraction := _prototype.get_extract_fraction()
	_extract_back.visible = fraction > 0.0
	_extract_fill.size = Vector2(_extract_back.size.x * clampf(fraction, 0.0, 1.0), 8.0)


func _compose_readout() -> String:
	var suit := _prototype.get_suit()
	var moored := "MOORED" if _prototype.is_moored() else "UNCLIPPED - draining"
	var power_pct := int(round(_prototype.get_suit_power_fraction() * 100.0))
	var target := _prototype.get_targeted_deposit()
	var target_line := "target: -"
	if target != null:
		target_line = "target: %s ore" % target.get_tier_name()
	return (
		"\n"
		. join(
			[
				"tether: %s" % moored,
				(
					"  distance %.1f m  strain %.1f m"
					% [suit.get_tether_distance(), suit.get_tether_strain()]
				),
				"suit power: %d%%" % power_pct,
				(
					"collected: %d deposits, %d value"
					% [_prototype.get_collected_count(), _prototype.get_collected_value()]
				),
				target_line,
				"[LMB] hold to mine   [T] clip/unclip tether   [ESC] mouse",
			]
		)
	)


## Draws one dot per in-range deposit, plus its distance, coloured by reach. Runs
## from the marker layer's `draw` signal so the draw_* calls land while it paints.
func _draw_markers() -> void:
	var settings := _prototype.get_settings()
	if not settings.markers_enabled:
		return
	var camera := _prototype.get_head_camera()
	if camera == null:
		return
	var suit_position := _prototype.get_suit().global_position
	var buoy_position := _prototype.get_buoy_position()
	var target := _prototype.get_targeted_deposit()
	for deposit: DepositNode in _prototype.get_deposits():
		if deposit.is_mined():
			continue
		var world := deposit.get_marker_position()
		if suit_position.distance_to(world) > settings.marker_proximity:
			continue
		if camera.is_position_behind(world):
			continue
		_draw_one_marker(camera, world, buoy_position, deposit == target)


func _draw_one_marker(
	camera: Camera3D, world: Vector3, buoy_position: Vector3, is_target: bool
) -> void:
	var screen := camera.unproject_position(world)
	var reachable := buoy_position.distance_to(world) <= MineralKnobs.MARKER_REACH_RANGE
	var color := REACHABLE_COLOR if reachable else RISKY_COLOR
	if is_target:
		color = TARGET_COLOR
		_marker_layer.draw_arc(screen, MARKER_RADIUS + 3.0, 0.0, TAU, 24, color, 1.5)
	_marker_layer.draw_circle(screen, MARKER_RADIUS, color)
	var label := "%.0fm%s" % [buoy_position.distance_to(world), "" if reachable else " !"]
	_marker_layer.draw_string(
		_font, screen + Vector2(8.0, 4.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color
	)
