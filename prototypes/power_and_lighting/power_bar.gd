class_name PowerBar
extends Control

## The suit's charge, drawn on the HUD.
##
## The counterpart to the cube's gauge and deliberately unlike it: this one is
## always perfectly legible, because it is meant to be the thing you check
## against. If the cube's gauge tells you less than this bar does, that is a
## finding about the cube gauge.
##
## Drawn rather than assembled from ProgressBar and a theme, for the same reason
## every other panel in this repo is built in code: one file to read, and no
## second copy of the colours living in a .tscn.

const FRAME_COLOR := Color(0.62, 0.74, 0.86, 0.5)
const BACKING_COLOR := Color(0.04, 0.05, 0.07, 0.7)
const FRAME_THICKNESS := 1.0
const PADDING := 2.0

## Below this fraction the bar pulses, matching the point at which the lamp's
## flicker becomes hard to miss.
const ALARM_FRACTION := 0.2

## Pulses per second while alarming.
const ALARM_RATE := 2.4

## How far the alarm pulse dims the fill at its lowest.
const ALARM_DEPTH := 0.45

var _fraction := 1.0
var _charging := false
var _elapsed := 0.0


func _process(delta: float) -> void:
	if _fraction >= ALARM_FRACTION or _charging:
		return
	# Only redrawn while alarming. The rest of the time the bar changes when the
	# charge does and not otherwise - see _on_charge_changed.
	_elapsed += delta
	queue_redraw()


func _draw() -> void:
	var full := Rect2(Vector2.ZERO, size)
	draw_rect(full, BACKING_COLOR)
	draw_rect(full, FRAME_COLOR, false, FRAME_THICKNESS)

	var inner := full.grow(-(FRAME_THICKNESS + PADDING))
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return
	inner.size.x *= _fraction
	if inner.size.x <= 0.0:
		return
	draw_rect(inner, _pick_fill_color())


## Sets how full the bar reads, 0 to 1. Connected straight to the suit store's
## charge_changed, so the bar is redrawn when the charge moves rather than on a
## clock.
func show_fraction(fraction: float) -> void:
	_fraction = fraction
	queue_redraw()


## Told separately from the charge, because a suit that is charging should stop
## alarming immediately rather than at whatever moment it climbs back over the
## threshold - the alarm is about being in trouble, and being plugged in is the
## answer to that whatever the gauge currently reads.
func set_charging(charging: bool) -> void:
	if charging == _charging:
		return
	_charging = charging
	_elapsed = 0.0
	queue_redraw()


func _pick_fill_color() -> Color:
	if _charging:
		return PowerKnobs.GAUGE_FULL_COLOR
	var color := PowerKnobs.GAUGE_EMPTY_COLOR.lerp(PowerKnobs.GAUGE_FULL_COLOR, _fraction)
	if _fraction >= ALARM_FRACTION:
		return color
	var pulse := 0.5 + 0.5 * sin(_elapsed * TAU * ALARM_RATE)
	# darkened() rather than a plain multiply, which would take the alpha down
	# with the colour and pulse the bar's opacity instead of its brightness.
	return color.darkened(1.0 - lerpf(ALARM_DEPTH, 1.0, pulse))
