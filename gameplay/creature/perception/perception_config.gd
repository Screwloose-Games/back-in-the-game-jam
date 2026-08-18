class_name PerceptionConfig
extends Resource

## Every tunable in the perception module, in one Resource (perception.md section 27).
##
## THIS IS THE WHOLE DIFFICULTY DIAL. Making the alien perceptually stronger or
## weaker means editing numbers here and nothing else -- no decision logic, no
## behaviour tree, no navigation. That property is the reason perception is kept
## thin (section 29), and it only survives if nothing outside this file hardcodes a
## sensing number.
##
## A bare `PerceptionConfig.new()` is fully usable. Every field has a working
## default, including the one Resource-typed field, so tests and a freshly dropped
## CreaturePerception both run without a .tres.

## Which physics layers count as world geometry for line-of-sight, sound occlusion
## and geometry probing. Defaults to bit 1 ("hull" in project.godot).
##
## A mask of 0 does not error. It makes every line-of-sight test succeed, every
## sound arrive unobstructed and every geometry probe report open space -- an
## omniscient alien in an empty universe, with nothing in the log. Left non-zero
## here and asserted in invariant_failures().
const DEFAULT_WORLD_MASK: int = 1

@export_flags_3d_physics var world_mask: int = DEFAULT_WORLD_MASK

@export_group("Hearing")
@export var hearing_enabled: bool = true
## Beyond this, a noise is not heard at all regardless of loudness.
@export_range(0.0, 200.0, 0.5, "or_greater", "suffix:m") var hearing_max_range: float = 40.0
## Multiplies received strength. The creature's ears, as one number.
@export_range(0.0, 4.0, 0.01) var hearing_sensitivity: float = 1.0
## Received fraction against normalised distance. NULL IS THE NORMAL CASE -- see
## distance_falloff(), which substitutes an analytic curve.
@export var hearing_distance_falloff: Curve = null
## Fraction of strength that survives full obstruction. At 0.0 a wall makes the
## creature completely deaf, which is rarely what you want in a cave.
@export_range(0.0, 1.0, 0.01) var hearing_obstruction_multiplier: float = 0.35
## Below this received strength, no evidence is produced at all.
@export_range(0.0, 1.0, 0.01) var hearing_min_detectable_strength: float = 0.05
## Uncertainty radius reported by a maximally clear noise.
@export_range(0.0, 20.0, 0.1, "suffix:m") var hearing_min_uncertainty: float = 1.0
## Uncertainty radius reported by a barely audible one.
@export_range(0.0, 60.0, 0.1, "suffix:m") var hearing_max_uncertainty: float = 12.0
## Fraction of the uncertainty radius by which the REPORTED origin is displaced
## from the true one.
##
## Without this, hearing hands Suspicion an exact point alongside a note saying it
## might be twelve metres out -- and any consumer that reads the point and ignores
## the radius gets a perfectly omniscient alien for free. The displacement is what
## makes section 11's uncertainty real rather than advisory. Set to 0.0 to report
## true positions; CreatureHearing.rng is seedable, so tests stay deterministic.
@export_range(0.0, 1.0, 0.01) var hearing_position_jitter: float = 1.0

@export_group("Vision")
@export var vision_enabled: bool = true
@export_range(0.0, 200.0, 0.5, "or_greater", "suffix:m") var vision_range: float = 18.0
## Full cone angle, not half-angle.
@export_range(0.0, 360.0, 1.0, "radians_as_degrees") var vision_angle: float = deg_to_rad(90.0)
## Alertness at or above which vision runs at all (section 14). At 0.0 vision is
## always on; at 1.0 it effectively never is.
@export_range(0.0, 1.0, 0.01) var vision_activation_suspicion: float = 0.25
@export_range(0.02, 5.0, 0.01, "suffix:s") var vision_scan_interval_calm: float = 0.6
@export_range(0.02, 5.0, 0.01, "suffix:s") var vision_scan_interval_alert: float = 0.1
## Below this computed visibility, the target is not seen.
@export_range(0.0, 1.0, 0.01) var vision_min_visibility: float = 0.15
## Uncertainty radius of a clear sighting. Small, but not zero -- perfect knowledge
## is exactly the claim perception exists to avoid making.
@export_range(0.0, 5.0, 0.05, "suffix:m") var vision_min_uncertainty: float = 0.25
## Uncertainty radius of a glimpse at the edge of what vision can resolve.
@export_range(0.0, 20.0, 0.05, "suffix:m") var vision_max_uncertainty: float = 2.0

@export_group("Touch")
@export var touch_enabled: bool = true
@export_range(0.0, 1.0, 0.01) var touch_strength: float = 1.0
## Contact is nearly exact, but not exact. Zero would claim perfect knowledge.
@export_range(0.0, 2.0, 0.01, "suffix:m") var touch_uncertainty: float = 0.1
@export_range(0.0, 10.0, 0.1, "suffix:m") var proximity_detection_range: float = 1.5

@export_group("Geometry")
@export var geometry_perception_enabled: bool = true
@export_range(0.5, 40.0, 0.5, "suffix:m") var geometry_passive_scan_radius: float = 6.0
@export_range(0.05, 10.0, 0.05, "suffix:s") var geometry_passive_scan_interval: float = 0.5
@export_range(0.5, 40.0, 0.5, "suffix:m") var geometry_validation_radius: float = 4.0
## Cell edge length for geometry sampling. Halving it multiplies the probe count by
## eight; see max_scan_samples, which is what stops that becoming a frame spike.
@export_range(0.1, 8.0, 0.1, "suffix:m") var geometry_clearance_resolution: float = 1.0
## A gap narrower than this is reported as CLEARANCE rather than FREE.
@export_range(0.1, 10.0, 0.1, "suffix:m") var geometry_min_clearance: float = 1.2
## How long a requested geometry validation takes. Navigation is usually blocked
## while it waits, so this is deliberately shorter than a search.
@export_range(0.0, 10.0, 0.05, "suffix:s") var geometry_scan_duration: float = 0.4

@export_group("Search")
@export_range(0.5, 40.0, 0.5, "suffix:m") var search_scan_radius: float = 5.0
@export_range(0.0, 30.0, 0.1, "suffix:s") var search_scan_duration_min: float = 0.5
@export_range(0.0, 60.0, 0.1, "suffix:s") var search_scan_duration_max: float = 4.0
## Disconfirmation strength produced by a maximally thorough search.
@export_range(0.0, 1.0, 0.01) var search_disconfirmation_strength: float = 0.9
## Upper bound on probes per scan, at thoroughness 1.0. The cost ceiling.
@export_range(1, 4096, 1) var max_scan_samples: int = 256


## Received fraction at `normalized_distance` (0 at the ear, 1 at hearing_max_range).
##
## THE CURVE EXPORT DEFAULTS TO NULL AND THAT IS THE COMMON CASE -- a fresh
## PerceptionConfig has no Curve, and so does one whose .tres was authored before
## anyone drew it. Calling sample_baked() on null is a hard crash inside a sense,
## which would surface as "the alien went deaf" rather than as a missing resource.
## The analytic branch is what every test exercises by default.
func distance_falloff(normalized_distance: float) -> float:
	var t: float = clampf(normalized_distance, 0.0, 1.0)
	if hearing_distance_falloff != null:
		return clampf(hearing_distance_falloff.sample_baked(t), 0.0, 1.0)
	return (1.0 - t) * (1.0 - t)


## How often vision samples, given the creature's current alertness (section 14).
##
## Suspicion changes HOW the alien looks, never WHAT it finds. Everything alertness
## touches lives in this function and in vision_gate() -- effort and scheduling. No
## observation's strength or confidence may depend on it.
func vision_scan_interval(alertness: float) -> float:
	var t: float = clampf(alertness, 0.0, 1.0)
	return lerpf(vision_scan_interval_calm, vision_scan_interval_alert, t)


## Whether vision runs at all right now.
func vision_gate(alertness: float) -> bool:
	return vision_enabled and clampf(alertness, 0.0, 1.0) >= vision_activation_suspicion


func scan_duration(thoroughness: float) -> float:
	var t: float = clampf(thoroughness, 0.0, 1.0)
	return lerpf(search_scan_duration_min, search_scan_duration_max, t)


## Probes a scan is allowed, given its thoroughness. At least one, always -- a scan
## budgeted zero samples can never find anything and always disconfirms, which is a
## silently wrong answer rather than a cheap one.
func scan_sample_count(thoroughness: float) -> int:
	var t: float = clampf(thoroughness, 0.0, 1.0)
	return maxi(1, int(roundf(lerpf(1.0, float(max_scan_samples), t))))


## Cross-field rules that no single @export_range can express. Called by the static
## verifier and by the tests, in the spirit of PrototypeSettings.invariant_failures().
func invariant_failures() -> PackedStringArray:
	var failures := PackedStringArray()
	if world_mask == 0:
		failures.append("world_mask is 0: every LOS test passes and every probe reports open space")
	if hearing_min_uncertainty > hearing_max_uncertainty:
		failures.append(
			(
				"hearing_min_uncertainty %.2f exceeds hearing_max_uncertainty %.2f"
				% [hearing_min_uncertainty, hearing_max_uncertainty]
			)
		)
	if search_scan_duration_min > search_scan_duration_max:
		failures.append(
			(
				"search_scan_duration_min %.2f exceeds search_scan_duration_max %.2f"
				% [search_scan_duration_min, search_scan_duration_max]
			)
		)
	if vision_scan_interval_alert > vision_scan_interval_calm:
		(
			failures
			. append(
				(
					"vision_scan_interval_alert %.2f is slower than calm %.2f; alertness would slow scanning"
					% [vision_scan_interval_alert, vision_scan_interval_calm]
				)
			)
		)
	if hearing_max_range <= 0.0 and hearing_enabled:
		failures.append("hearing is enabled with hearing_max_range 0")
	if vision_range <= 0.0 and vision_enabled:
		failures.append("vision is enabled with vision_range 0")
	if vision_min_uncertainty > vision_max_uncertainty:
		failures.append(
			(
				"vision_min_uncertainty %.2f exceeds vision_max_uncertainty %.2f"
				% [vision_min_uncertainty, vision_max_uncertainty]
			)
		)
	if geometry_clearance_resolution <= 0.0:
		failures.append("geometry_clearance_resolution is 0; subdivision would not terminate")
	return failures
