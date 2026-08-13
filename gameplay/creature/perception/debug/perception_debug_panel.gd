class_name PerceptionDebugPanel
extends PanelContainer

## Section 30's text readout, near enough verbatim:
##
##     HEARING
##     Event:               Drill
##     Raw loudness:        1.00
##     Distance:            23.2m
##     Received:            .61
##     Estimated uncertainty: 4.8m
##     Submitted:           SuspicionEvidence #143
##
## The numbers that matter here are the ones NOT on the observation: raw loudness,
## distance and obstruction are inputs perception consumed and did not keep. Without
## them "the alien didn't hear me" and "the alien heard me faintly" look identical
## from the outside, which is the confusion section 29 exists to prevent.
##
## Fed entirely by signals. It asks perception for nothing except debug_state(),
## which is computed rather than remembered -- so nothing on this panel implies any
## storage on the creature.

const MAX_LOG_LINES: int = 12

@export var perception: CreaturePerception = null
@export var debug_draw: PerceptionDebugDraw = null

var _label: RichTextLabel = null
var _log: Array[String] = []
var _evidence_count: int = 0
var _last_noise: String = "(none yet)"


func _ready() -> void:
	_label = RichTextLabel.new()
	_label.bbcode_enabled = false
	_label.fit_content = true
	_label.custom_minimum_size = Vector2(420, 0)
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	add_child(_label)

	if perception != null:
		perception.noise_evaluated.connect(_on_noise_evaluated)
		perception.evidence_observed.connect(_on_evidence)
		perception.disconfirmation_observed.connect(_on_disconfirmation)
		perception.geometry_observed.connect(_on_geometry)
		perception.activity_scan_finished.connect(_on_activity_finished)


func _process(_delta: float) -> void:
	if not visible or perception == null:
		return
	_label.text = _compose()


func _compose() -> String:
	var state: Dictionary = perception.debug_state()
	var lines: Array[String] = [
		"PERCEPTION      t=%6.2fs" % float(state["clock"]),
		"",
		"alertness:      %.2f" % float(state["alertness"]),
		(
			"vision:         %s  every %.2fs"
			% ["ON " if bool(state["vision_active"]) else "OFF", float(state["vision_interval"])]
		),
		"candidates:     %d" % int(state["candidates"]),
		"probe bound:    %s" % ("yes" if bool(state["probe_bound"]) else "NO"),
		"",
		(
			"activity scan:  %s"
			% _scan_line(
				bool(state["activity_scan_active"]), float(state["activity_scan_progress"])
			)
		),
		(
			"geometry scan:  %s"
			% _scan_line(
				bool(state["geometry_scan_active"]), float(state["geometry_scan_progress"])
			)
		),
		"",
		"HEARING (last)",
		_last_noise,
		"",
		"OBSERVATIONS",
	]
	lines.append_array(_log)
	return "\n".join(lines)


func _scan_line(active: bool, progress: float) -> String:
	if not active:
		return "idle"
	var filled: int = int(roundf(progress * 20.0))
	return "[%s%s] %3d%%" % ["#".repeat(filled), ".".repeat(20 - filled), int(progress * 100.0)]


## Fires for every noise, heard or not -- the whole reason it exists.
func _on_noise_evaluated(
	event: NoiseEvent, evidence: SuspicionEvidence, distance: float, obstruction: float
) -> void:
	var category: String = String(event.category) if event.category != &"" else "(untagged)"
	var submitted: String = "NOT HEARD"
	var uncertainty: String = "-"
	var received: String = "0.00"
	if evidence != null:
		submitted = "SuspicionEvidence #%d" % (_evidence_count + 1)
		uncertainty = "%.1fm" % evidence.uncertainty_radius
		received = "%.2f" % evidence.strength
	_last_noise = (
		"\n"
		. join(
			[
				"  event:        %s" % category,
				"  raw loudness: %.2f" % event.loudness,
				"  distance:     %.1fm" % distance,
				"  obstruction:  %.2f" % obstruction,
				"  received:     %s" % received,
				"  uncertainty:  %s" % uncertainty,
				"  submitted:    %s" % submitted,
			]
		)
	)


func _on_evidence(evidence: SuspicionEvidence) -> void:
	_evidence_count += 1
	_append(
		(
			"#%d %-7s s=%.2f c=%.2f r=%.1fm"
			% [
				_evidence_count,
				evidence.sense_name(),
				evidence.strength,
				evidence.confidence,
				evidence.uncertainty_radius
			]
		)
	)


func _on_disconfirmation(observation: DisconfirmationObservation) -> void:
	_append(
		(
			"   DISCONF  s=%.2f r=%.1fm senses=%d"
			% [observation.strength, observation.radius, observation.sense_count()]
		)
	)


func _on_geometry(observations: Array) -> void:
	var solid: int = 0
	for observation: Variant in observations:
		if (observation as GeometryObservation).type == GeometryObservation.ObservationType.SOLID:
			solid += 1
	_append("   GEOMETRY %d cells, %d solid" % [observations.size(), solid])


func _on_activity_finished(found_evidence: bool) -> void:
	_append("   SEARCH   %s" % ("found something" if found_evidence else "found nothing"))


func _append(line: String) -> void:
	_log.append(line)
	if _log.size() > MAX_LOG_LINES:
		_log.remove_at(0)
