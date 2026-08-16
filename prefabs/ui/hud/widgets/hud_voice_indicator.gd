@tool
class_name HudVoiceIndicator
extends HudWidget

## Whether this suit's microphone is open, and how loud it is hearing you.
##
## Present for the privacy contract rather than for the game. Voice activation is
## the default talk mode, so an enabled microphone is a hot one, and something on
## screen has to say so for as long as that is true.

const DESIGN := Vector2(96.0, 96.0)
const RING_RADIUS := 30.0
const RING_WIDTH := 3.0
const DOT_RADIUS := 7.0
const RING_SEGMENTS := 48
const OFF_COLOUR := Color(1.0, 1.0, 1.0, 0.16)
const LIVE_COLOUR := Color(1.0, 0.68, 0.24, 0.85)
const TRANSMIT_COLOUR := Color(0.42, 0.90, 0.45, 0.95)

## Whether the microphone is open. Driven at runtime; exported for the preview.
@export var live := false:
	set(value):
		if value == live:
			return
		live = value
		queue_redraw()

@export var transmitting := false:
	set(value):
		if value == transmitting:
			return
		transmitting = value
		queue_redraw()

@export_range(0.0, 1.0, 0.01) var loudness := 0.0:
	set(value):
		var next := clampf(value, 0.0, 1.0)
		if is_equal_approx(next, loudness):
			return
		loudness = next
		queue_redraw()


func design_extent() -> Vector2:
	return DESIGN


func bind(state: HudState) -> void:
	if not state.voice_changed.is_connected(show_voice):
		state.voice_changed.connect(show_voice)
	show_voice(state.voice_live, state.voice_transmitting, state.voice_loudness)


func show_voice(is_live: bool, is_transmitting: bool, level: float) -> void:
	live = is_live
	transmitting = is_transmitting
	loudness = level if is_live else 0.0


func _draw() -> void:
	var centre := scaled_vec(DESIGN * 0.5)
	var colour := OFF_COLOUR
	if transmitting:
		colour = TRANSMIT_COLOUR
	elif live:
		colour = LIVE_COLOUR

	draw_arc(centre, scaled(RING_RADIUS), 0.0, TAU, RING_SEGMENTS, colour, scaled(RING_WIDTH), true)
	if not live:
		return

	# The level ring reads as "it is hearing you", which is the part a player
	# actually wants confirmed before they say something private.
	var inner := RING_RADIUS - RING_WIDTH * 2.0
	if loudness > 0.0:
		draw_arc(
			centre,
			scaled(inner),
			-PI * 0.5,
			-PI * 0.5 + TAU * loudness,
			RING_SEGMENTS,
			colour,
			scaled(RING_WIDTH),
			true
		)
	draw_circle(centre, scaled(DOT_RADIUS), colour)


func _validate_property(property: Dictionary) -> void:
	if property["name"] in ["live", "transmitting", "loudness"]:
		property["usage"] = int(property["usage"]) & ~PROPERTY_USAGE_STORAGE
