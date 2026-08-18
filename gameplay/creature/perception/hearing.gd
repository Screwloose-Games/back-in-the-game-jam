class_name CreatureHearing
extends RefCounted

## Turns a NoiseEvent the world emitted into evidence this particular creature
## received (perception.md sections 11-12).
##
## Event-driven, never polled. The world pushes noises in; hearing does not go
## looking for them.
##
## THE INTERESTING OUTPUT IS THE UNCERTAINTY, NOT THE STRENGTH. Anyone can attenuate
## a number by distance. What makes the alien beatable is that a faint, distant or
## muffled noise yields a WIDE possible-origin area and a displaced reported point,
## so Suspicion has to reason about a region and the creature has to search it.
##
## Named `CreatureHearing` rather than the doc's `Hearing`: Godot's class_name table
## is global and project-wide, and a collision is a parse failure across the whole
## project rather than a warning. See the module README.

## How much the raw distance term widens uncertainty on top of the clarity term.
##
## Clarity alone is not enough. A very loud noise at the far edge of hearing range
## still arrives strong, and without this the creature would report it as though it
## were next door -- loudness would leak into precision, which is not how ears work.
const DISTANCE_UNCERTAINTY_WEIGHT: float = 0.35

var enabled: bool = true
var config: PerceptionConfig = null
## Seeded by CreaturePerception. Exposed so tests can pin it and get byte-identical
## jitter; see PerceptionConfig.hearing_position_jitter.
var rng: RandomNumberGenerator = null


## Strength this creature receives, 0..1 (section 11's four-term product).
##
##     raw loudness  x  distance attenuation  x  obstruction  x  sensitivity
##
## `obstruction` is 0..1 from PerceptionProbe, not a blocker count -- see the note
## on PerceptionProbe.obstruction_between.
static func received_strength(
	loudness: float, distance: float, obstruction: float, config: PerceptionConfig
) -> float:
	if config == null or config.hearing_max_range <= 0.0:
		return 0.0
	if distance > config.hearing_max_range:
		return 0.0
	var falloff: float = config.distance_falloff(distance / config.hearing_max_range)
	var muffle: float = lerpf(
		1.0, config.hearing_obstruction_multiplier, clampf(obstruction, 0.0, 1.0)
	)
	return clampf(maxf(loudness, 0.0) * falloff * muffle * config.hearing_sensitivity, 0.0, 1.0)


## Radius of the area the noise could have come from, in metres.
##
## Monotonically increasing in distance from both terms at once: a farther noise is
## both quieter (so `clarity` falls) and farther (so `reach` rises). That double
## movement is deliberate -- it means no combination of loudness and distance can
## produce a distant-but-pinpoint reading.
##
## The two terms are BLENDED to a weighted average rather than added. Adding them
## and clamping looked equivalent and was not: the sum crossed
## hearing_max_uncertainty at roughly 60% of hearing range, so every noise beyond
## that reported an identical radius and the creature lost all ability to tell a
## far noise from a very far one. The blend reaches the maximum exactly at maximum
## range, which is the only place it should.
static func estimate_uncertainty(
	received: float, distance: float, config: PerceptionConfig
) -> float:
	if config == null:
		return 0.0
	var clarity: float = clampf(received, 0.0, 1.0)
	var reach: float = 0.0
	if config.hearing_max_range > 0.0:
		reach = clampf(distance / config.hearing_max_range, 0.0, 1.0)
	var vagueness: float = clampf(
		(1.0 - clarity) * (1.0 - DISTANCE_UNCERTAINTY_WEIGHT) + reach * DISTANCE_UNCERTAINTY_WEIGHT,
		0.0,
		1.0
	)
	return lerpf(config.hearing_min_uncertainty, config.hearing_max_uncertainty, vagueness)


## How sure hearing is that anything happened, 0..1. Separate axis from strength:
## a barely-detectable noise is barely believable even if it was a loud one far off.
static func estimate_confidence(received: float, config: PerceptionConfig) -> float:
	if config == null:
		return 0.0
	var floor_strength: float = config.hearing_min_detectable_strength
	if floor_strength >= 1.0:
		return 0.0
	return clampf((clampf(received, 0.0, 1.0) - floor_strength) / (1.0 - floor_strength), 0.0, 1.0)


## The one entry point. Returns null when the noise was not heard at all -- which is
## a real and common answer, not an error.
func perceive_noise(
	event: NoiseEvent, listener: Vector3, obstruction: float, now: float
) -> SuspicionEvidence:
	if not enabled or config == null or not config.hearing_enabled or event == null:
		return null
	var distance: float = listener.distance_to(event.position)
	var received: float = received_strength(event.loudness, distance, obstruction, config)
	if received < config.hearing_min_detectable_strength or received <= 0.0:
		return null

	var uncertainty: float = estimate_uncertainty(received, distance, config)
	var evidence := SuspicionEvidence.make(
		SuspicionEvidence.Sense.HEARING,
		_reported_origin(event.position, uncertainty),
		uncertainty,
		received,
		estimate_confidence(received, config),
		now
	)
	evidence.category = event.category
	# HEARING DOES NOT ATTRIBUTE, even though the NoiseEvent knows exactly who made
	# the noise. Copying source_player through here would hand Behavior a free
	# target identification from a sound in the dark -- section 8's own hearing
	# example reads "source: unknown". Vision and Touch are what attribute.
	return evidence


## Displace the reported origin within the uncertainty disc, so consumers that read
## `position` and ignore `uncertainty_radius` degrade honestly instead of getting
## perfect information for free.
func _reported_origin(true_origin: Vector3, uncertainty: float) -> Vector3:
	if config == null or config.hearing_position_jitter <= 0.0 or uncertainty <= 0.0:
		return true_origin
	if rng == null:
		rng = RandomNumberGenerator.new()
	var offset := Vector3(rng.randfn(0.0, 1.0), rng.randfn(0.0, 1.0) * 0.5, rng.randfn(0.0, 1.0))
	if offset.length_squared() <= 0.0:
		return true_origin
	# Scaled so the typical displacement sits inside the reported radius rather than
	# on it -- an offset that always lands exactly at the rim is a ring, not a disc,
	# and Suspicion would learn to search the edge.
	var spread: float = rng.randf() * uncertainty * config.hearing_position_jitter
	return true_origin + offset.normalized() * spread
