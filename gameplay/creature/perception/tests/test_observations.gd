extends GutTest

## The three observation types and NoiseEvent (perception.md sections 8-11).
##
## These are the wire format between perception and everything downstream, so the
## interesting assertions are about what they DON'T do: share state between copies,
## lose fields through a factory, or default to values that read as meaningful.


func test_noise_event_factory_stamps_every_field() -> void:
	var source := Node.new()
	var player := Node.new()
	var event := NoiseEvent.make(Vector3(1, 2, 3), 0.8, &"drill", source, player)

	assert_eq(event.position, Vector3(1, 2, 3))
	assert_eq(event.loudness, 0.8)
	assert_eq(event.category, &"drill")
	assert_same(event.source, source)
	assert_same(event.source_player, player)
	source.free()
	player.free()


func test_noise_event_defaults_are_usable() -> void:
	var event := NoiseEvent.make(Vector3.ZERO, 1.0)
	assert_null(event.source, "an unattributed noise is the normal case")
	assert_null(event.source_player)
	assert_eq(event.category, &"")


func test_evidence_factory_stamps_every_field() -> void:
	var evidence := SuspicionEvidence.make(
		SuspicionEvidence.Sense.VISION, Vector3(4, 0, 9), 0.25, 0.96, 0.98, 12.5
	)

	assert_eq(evidence.sense, SuspicionEvidence.Sense.VISION)
	assert_eq(evidence.position, Vector3(4, 0, 9))
	assert_eq(evidence.uncertainty_radius, 0.25)
	assert_eq(evidence.strength, 0.96)
	assert_eq(evidence.confidence, 0.98)
	assert_eq(evidence.observed_at, 12.5)


func test_evidence_defaults_to_unattributed() -> void:
	var evidence := SuspicionEvidence.make(
		SuspicionEvidence.Sense.HEARING, Vector3.ZERO, 4.5, 0.71, 0.62, 0.0
	)
	assert_null(evidence.source_player, "section 8's hearing example reads 'source: unknown'")
	assert_eq(evidence.source_confidence, 0.0)


## Consumers hold observations for as long as they like. Handing two subscribers the
## same instance means the second can mutate what the first is still reading.
func test_duplicate_evidence_is_independent() -> void:
	var original := SuspicionEvidence.make(
		SuspicionEvidence.Sense.TOUCH, Vector3(1, 1, 1), 0.1, 1.0, 1.0, 3.0
	)
	original.category = &"contact"
	var copy := original.duplicate_evidence()

	copy.position = Vector3(9, 9, 9)
	copy.strength = 0.0
	copy.category = &"mutated"

	assert_eq(original.position, Vector3(1, 1, 1), "the copy must not alias the original")
	assert_eq(original.strength, 1.0)
	assert_eq(original.category, &"contact")
	assert_eq(copy.observed_at, 3.0, "everything else still copied across")


func test_sense_names_cover_every_enum_value() -> void:
	var seen: Array[String] = []
	for sense: int in [
		SuspicionEvidence.Sense.HEARING,
		SuspicionEvidence.Sense.VISION,
		SuspicionEvidence.Sense.TOUCH,
	]:
		var evidence := SuspicionEvidence.make(sense, Vector3.ZERO, 0.0, 0.0, 0.0, 0.0)
		seen.append(evidence.sense_name())
	assert_eq(seen, ["HEARING", "VISION", "TOUCH"])


func test_disconfirmation_sense_mask_round_trips() -> void:
	var observation := DisconfirmationObservation.make(
		Vector3(0, -4, 0),
		5.0,
		0.9,
		2.0,
		(
			DisconfirmationObservation.sense_bit(SuspicionEvidence.Sense.VISION)
			| DisconfirmationObservation.sense_bit(SuspicionEvidence.Sense.TOUCH)
		)
	)

	assert_true(observation.has_sense(SuspicionEvidence.Sense.VISION))
	assert_true(observation.has_sense(SuspicionEvidence.Sense.TOUCH))
	assert_false(
		observation.has_sense(SuspicionEvidence.Sense.HEARING),
		"hearing is event-driven; it does not participate in a deliberate search"
	)
	assert_eq(observation.sense_count(), 2)


## Section 9's two worked examples, as an assertion. A thorough sweep and a glance
## must be distinguishable by strength alone, because that is the only thing
## Suspicion is given to scale how much it clears.
func test_disconfirmation_strength_separates_a_sweep_from_a_glance() -> void:
	var sweep := DisconfirmationObservation.make(Vector3.ZERO, 5.0, 0.9, 0.0)
	var glance := DisconfirmationObservation.make(Vector3.ZERO, 5.0, 0.2, 0.0)
	assert_gt(sweep.strength, glance.strength)


func test_geometry_observation_derives_its_position_from_its_region() -> void:
	var region := AABB(Vector3(2, 2, 2), Vector3(2, 2, 2))
	var observation := GeometryObservation.make(
		GeometryObservation.ObservationType.FREE, region, 0.8, 1.0
	)

	assert_eq(observation.position, Vector3(3, 3, 3), "position is the region's centre")
	assert_eq(observation.region, region)
	assert_eq(observation.confidence, 0.8)
	assert_eq(observation.clearance, 0.0)


func test_geometry_observation_type_names_cover_every_enum_value() -> void:
	var seen: Array[String] = []
	for type: int in [
		GeometryObservation.ObservationType.FREE,
		GeometryObservation.ObservationType.SOLID,
		GeometryObservation.ObservationType.CLEARANCE,
	]:
		seen.append(GeometryObservation.make(type, AABB(), 1.0, 0.0).type_name())
	assert_eq(seen, ["FREE", "SOLID", "CLEARANCE"])
