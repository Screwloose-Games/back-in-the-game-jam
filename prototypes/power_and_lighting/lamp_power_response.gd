class_name LampPowerResponse
extends Node

## Drives one Light3D from one PowerStore: it dims as the battery falls, and it
## flickers more often the lower the battery gets.
##
## Two of these run - one on the helmet SpotLight3D, one on the cube's
## OmniLight3D - with their own numbers, so the suit and the cube can be tuned to
## fail in different ways and be told apart by how they die.
##
## FLICKER IS A SCHEDULED DROPOUT, NOT PER-FRAME NOISE. Noise on the energy every
## frame reads as a broken shader; frame rate changes how fast it shimmers, and
## the fog goes with it so the whole image boils. A lamp that cuts out for ninety
## milliseconds and comes back reads as a lamp about to die, at any frame rate.
## The charge level is carried by how often the dropouts land, not by how deep
## they are - a light that fails DEEPER as it drains just looks like the dimming
## already happening, while one that fails MORE OFTEN is a separate signal you
## can read without a gauge.
##
## AND THEY LAND AS A POISSON PROCESS. See _draw_next_threshold: the gaps are
## exponential rather than a jittered interval, which is the difference between a
## lamp that is failing and a lamp keeping time.
##
## Everything is recomputed from the store every frame rather than driven off
## charge_changed. It is a handful of floats, and it has to be that way regardless
## because the flicker schedule advances on its own clock while a full battery
## emits nothing at all.

## What the light looks like at full charge. Held here rather than read off the
## light, because the light is being overwritten every frame and could not be
## asked what it used to be.
var base_energy := 1.0
var base_range := 10.0

## Charge fraction across, fraction of full brightness up. Its value at zero is
## what the lamp is left with on a flat battery.
##
## A Curve rather than a set of numbers copied out of one, because the panel edits
## this resource IN PLACE while the game runs and it is sampled here every frame.
## Nothing has to be pushed anywhere for a drag to take effect.
var dim_curve: Curve

## Charge fraction across, dropouts per second up. Sampled every frame for the
## same reason and edited the same way.
var flicker_curve: Curve

## Throw at zero charge, as a fraction of base_range. Not on the dim curve
## because it is a separate axis - how much the world shrinks against how much it
## darkens. See PowerKnobs.SUIT_LAMP_MIN_RANGE_FRACTION.
var min_range_fraction := 0.3

## Multiplier on the whole flicker curve. 1.0 is the curve as drawn; 0.0 turns
## flicker off outright, which is how the panel's slider disables it.
var flicker_scale := 1.0

## Whether the battery is allowed to affect the light at all. False parks the
## lamp at base_energy and base_range: no curve, no dropouts, nothing moving that
## a slider did not move. See PowerKnobs.LAMP_RESPONDS_TO_POWER.
##
## The light is still written every frame in that state rather than set once and
## left, so this node stays the single owner of light_energy and the light's
## range either way - a tuning setter that had to know which of two things
## currently owned the property it writes is how a value ends up surviving one
## frame and then being overwritten.
var responds_to_charge := true

var _light: Light3D
var _store: PowerStore

## The rate integrated since the last dropout, and the Exp(1) draw this wait ends
## at. Firing when one passes the other is the time-rescaling construction of a
## Poisson process whose rate is allowed to move.
##
## AN INTEGRAL THAT ACCRUES, NOT A WAIT THAT IS DRAWN. Drawing a wait in seconds
## fixes it at the charge level it was drawn at, so a battery emptied during a
## long wait goes on flickering at its old rate until that wait finally expires -
## twenty seconds of a dead lamp behaving like a full one, which is exactly the
## window the panel's state buttons drop you into. Accruing instead means the
## charge sets the rate on the very next frame.
var _flicker_load := 0.0
var _flicker_threshold := 1.0

## Seconds left in the dropout currently running, or zero.
var _flicker_time_left := 0.0

## Its own generator, seeded, so two runs at the same knobs flicker identically
## and the only thing that differs between them is the change being judged.
var _flicker_random := RandomNumberGenerator.new()


func _process(delta: float) -> void:
	if _light == null or _store == null:
		return

	if not responds_to_charge:
		_light.light_energy = base_energy
		_set_light_range(base_range)
		return

	var fraction := _store.get_fraction()
	var level := clampf(dim_curve.sample(fraction), 0.0, 1.0)

	# The throw comes in with the brightness. Left alone, a lamp dimmed to a
	# tenth goes on reaching the far wall and the only thing that has changed is
	# the exposure; pulling the range in is what makes a weak lamp feel like a
	# smaller world rather than a darker one.
	_light.light_energy = base_energy * level * _advance_flicker(delta, fraction)
	_set_light_range(base_range * lerpf(min_range_fraction, 1.0, level))


## Wires this node to a light and a battery. Every tunable is passed in rather
## than read from PowerKnobs here, because the suit and the cube use the same
## code with different numbers.
func bind(light: Light3D, store: PowerStore) -> void:
	_light = light
	_store = store
	_flicker_random.seed = PowerKnobs.FLICKER_RANDOM_SEED
	_draw_next_threshold()


## Returns the multiplier the flicker is applying to the lamp this frame: 1.0
## normally, PowerKnobs.FLICKER_DEPTH during a dropout.
func _advance_flicker(delta: float, fraction: float) -> float:
	if not PowerKnobs.FLICKER_ENABLED or flicker_scale <= 0.0:
		return 1.0

	if _flicker_time_left > 0.0:
		_flicker_time_left -= delta
		if _flicker_time_left > 0.0:
			return PowerKnobs.FLICKER_DEPTH
		_flicker_load = 0.0
		_draw_next_threshold()
		return 1.0

	# The rate is read off the RAW charge fraction, not off the dimming curve's
	# `level`: how often the lamp stutters and how bright it is are meant to be two
	# readings of the same battery rather than one restated, so bending one curve
	# should not bend the other.
	#
	# At most one dropout can start per frame. At the top of the rate axis and
	# sixty frames a second that is a twentieth of an event per frame, so the
	# events being dropped are the ones that would have landed inside a frame the
	# lamp is already dark for.
	var rate := maxf(flicker_curve.sample(fraction), 0.0)
	_flicker_load += rate * flicker_scale * delta
	if _flicker_load < _flicker_threshold:
		return 1.0
	_flicker_time_left = PowerKnobs.FLICKER_DURATION
	return PowerKnobs.FLICKER_DEPTH


## How much integrated rate this particular wait runs for: an Exp(1) draw, by
## inverse transform.
##
## THIS IS THE WHOLE OF WHAT MAKES THE DROPOUTS POISSON rather than metronomic.
## An exponential gap is memoryless, so a short gap is the commonest outcome of
## all and two dropouts almost on top of each other are perfectly ordinary. A
## uniform draw around a mean - which is what this used to be - can produce
## neither a burst nor a really long quiet stretch, and the eye reads what is left
## as a rhythm however wide the jitter is set.
##
## randf() is [0, 1), so 1 - randf() is (0, 1] and the log is always finite.
func _draw_next_threshold() -> void:
	_flicker_threshold = -log(1.0 - _flicker_random.randf())


## The light's own look, as opposed to what the battery does to it.
##
## These live here rather than on the prototype because this node already owns
## light_energy and the light's range and rewrites both every frame - a second
## owner for the properties sitting next to them is how a value ends up surviving
## exactly one frame. It also means the panel drives the helmet lamp and the
## cube's through one interface, spot and omni alike, so the section that tunes
## one is the section that tunes the other.
func set_color(color: Color) -> void:
	_light.light_color = color


func set_shadows(enabled: bool) -> void:
	_light.shadow_enabled = enabled


## How sharply the light fades with distance. Spelled differently on the two light
## types, like the range is.
func set_distance_falloff(attenuation: float) -> void:
	var spot := _light as SpotLight3D
	if spot != null:
		spot.spot_attenuation = attenuation
		return
	var omni := _light as OmniLight3D
	if omni != null:
		omni.omni_attenuation = attenuation


## Half-angle of the cone in degrees, so 45 is a 90 degree spread. Does nothing on
## an omni light, which has no cone - and the panel builds no cone slider for one.
func set_cone(degrees: float) -> void:
	var spot := _light as SpotLight3D
	if spot != null:
		spot.spot_angle = clampf(degrees, PowerKnobs.LAMP_ANGLE_MIN, PowerKnobs.LAMP_ANGLE_MAX)


## How sharply the beam fades from the centre of the cone to its rim. Spot only,
## for the same reason.
func set_edge_falloff(attenuation: float) -> void:
	var spot := _light as SpotLight3D
	if spot != null:
		spot.spot_angle_attenuation = attenuation


## Builds one of the two curves from a list of seed points.
##
## TANGENT_LINEAR on both sides of every point, so the curve is exactly the
## polyline drawn in the editor rather than a spline through the same points. On a
## brightness curve an overshoot would mean a lamp brighter at 40% charge than at
## 50%, which is not a shape anyone placed and not one they could see they had.
static func build_curve(points: Array[Vector2], maximum: float) -> Curve:
	var curve := Curve.new()
	curve.min_value = 0.0
	curve.max_value = maximum
	for point: Vector2 in points:
		curve.add_point(point, 0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	return curve


## SpotLight3D and OmniLight3D spell their reach differently, and this node has
## to drive both.
func _set_light_range(metres: float) -> void:
	var spot := _light as SpotLight3D
	if spot != null:
		spot.spot_range = metres
		return
	var omni := _light as OmniLight3D
	if omni != null:
		omni.omni_range = metres
